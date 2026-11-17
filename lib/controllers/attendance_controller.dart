import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/calendar.dart';
import '../models/models.dart';
import '../models/rules.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../services/location_service.dart';
import '../services/sync_service.dart';
import 'settings_controller.dart';

enum LoadStatus { loading, ready, error }

enum HistoryFilter { all, synced, pending, rejected }

enum ActionOutcome { synced, savedPending, rejected, blocked, ignored }

class ActionResult {
  const ActionResult(this.outcome, this.message, {this.openSettings = false});
  final ActionOutcome outcome;
  final String message;
  final bool openSettings; // offer an "Open settings" button
}

class MonthStats {
  const MonthStats({required this.present, required this.shortDays, required this.total});
  final int present;
  final int shortDays; // finished days under 8 h (treated as leave)
  final Duration total;
}

/// Controller for Home, Attendance History and the sync queue.
/// Views read its fields and call its methods; it never touches widgets.
class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required RebsApi api,
    required LocalDb db,
    required LocationService location,
    required SyncService sync,
    required SettingsController settings,
    DateTime Function()? now,
    String Function()? newId,
  })  : _api = api,
        _db = db,
        _location = location,
        _sync = sync,
        _settings = settings,
        _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4()) {
    // After every sync run, refresh the screen from local data.
    _syncSub = _sync.changes.listen((_) => _backgroundRefresh = load(silent: true));
  }

  Future<void>? _backgroundRefresh;

  /// Completes when the refresh triggered by the latest sync run has finished.
  Future<void> get settled => _backgroundRefresh ?? Future.value();

  final RebsApi _api;
  final LocalDb _db;
  final LocationService _location;
  final SyncService _sync;
  final SettingsController _settings;
  final DateTime Function() _now;
  final String Function() _newId;
  StreamSubscription<SyncReport>? _syncSub;
  bool _disposed = false;

  // ---- state the views read ----
  LoadStatus status = LoadStatus.loading;
  String? error;
  bool errorOffline = false;
  Employee? employee;
  List<AttendanceRecord> records = [];
  List<HistoryItem> allHistory = [];
  LeaveBalance? balance;
  List<AttendanceEvent> events = [];
  int pendingCount = 0;
  bool fromCache = false; // showing saved data (offline / server down)
  DateTime? lastUpdated;
  bool busy = false; // a check-in/out is running
  bool syncing = false;
  HistoryFilter filter = HistoryFilter.all;

  /// One-shot message for a SnackBar. `messageId` changes on every new one.
  String? message;
  int messageId = 0;
  bool messageOpensSettings = false;

  // ---- derived values ----
  OfficeConfig? get office =>
      employee == null ? null : _settings.effectiveOffice(employee!.office);

  /// Today's date in the company timezone. Computed live so it rolls over at
  /// midnight even if the app stays open.
  String get workDate {
    final o = office;
    return o == null ? '' : companyDate(_now(), o.timezone);
  }

  AttendanceRecord? get today {
    for (final r in records) {
      if (r.date == workDate) return r;
    }
    return null;
  }

  String get _timezone => office?.timezone ?? 'Asia/Kolkata';

  /// Sessions, total hours and state for any day (uses the live clock, so the
  /// 10 PM auto-done applies as soon as the time passes).
  DaySummary summaryOf(String date, List<Punch> punches) =>
      AttendanceRules.summarize(date, punches, _now(), _timezone);

  DaySummary summaryOfItem(HistoryItem i) => summaryOf(i.date, i.punches);

  /// Today's punches, total worked time and state.
  DaySummary get todaySummary => summaryOf(workDate, today?.punches ?? const []);

  /// This month so far: present days, short-hours (leave) days, total hours.
  MonthStats get monthStats {
    final month = workDate.length >= 7 ? workDate.substring(0, 7) : '';
    var present = 0, short = 0;
    var total = Duration.zero;
    for (final r in records.where((r) => r.date.startsWith(month))) {
      final s = summaryOf(r.date, r.punches);
      total += s.total;
      if (s.result == DayResult.present) present++;
      if (s.result == DayResult.shortHours) short++;
    }
    return MonthStats(present: present, shortDays: short, total: total);
  }

  // ---- monthly calendar (Attendance tab) ----

  String _calendarMonth = ''; // 'yyyy-MM'; empty = the current month

  /// The month the calendar shows, as 'yyyy-MM'.
  String get shownMonth => _calendarMonth.isEmpty ? workDate.substring(0, 7) : _calendarMonth;

  // Data is loaded for this month and last month only.
  bool get canGoPrev => workDate.isNotEmpty && shownMonth.compareTo(_months().last) > 0;
  bool get canGoNext => workDate.isNotEmpty && shownMonth.compareTo(workDate.substring(0, 7)) < 0;

  void shiftCalendar(int delta) {
    if (delta < 0 && !canGoPrev) return;
    if (delta > 0 && !canGoNext) return;
    final y = int.parse(shownMonth.substring(0, 4));
    final m = int.parse(shownMonth.substring(5, 7));
    _calendarMonth = fmtDate(DateTime.utc(y, m + delta)).substring(0, 7);
    notifyListeners();
  }

  /// Every day of [shownMonth] with its mark (present / leave / off / ...).
  List<CalendarDay> calendarDays(List<LeaveRequest> leaves) {
    if (employee == null) return const [];
    return buildMonth(
      year: int.parse(shownMonth.substring(0, 4)),
      month: int.parse(shownMonth.substring(5, 7)),
      today: workDate,
      records: records,
      leaves: leaves,
      summarize: (r) => summaryOf(r.date, r.punches),
    );
  }

  List<HistoryItem> get recent => allHistory.take(5).toList();

  List<HistoryItem> get history => switch (filter) {
        HistoryFilter.all => allHistory,
        HistoryFilter.synced => allHistory.where((h) => h.status == SyncStatus.synced).toList(),
        HistoryFilter.pending => allHistory.where((h) => h.status == SyncStatus.pending).toList(),
        HistoryFilter.rejected => allHistory.where((h) => h.status == SyncStatus.rejected).toList(),
      };

  // ---- loading ----

  /// Network first, saved copy as fallback. `silent` keeps the current screen.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      status = LoadStatus.loading;
      notifyListeners();
    }
    fromCache = false;
    ApiException? firstError;

    try {
      final fresh = await _api.getEmployee();
      await _db.putCache('employee', fresh.toJson());
    } on ApiException catch (e) {
      firstError = e;
      fromCache = true;
    }

    final cached = await _db.getCache('employee');
    if (cached == null) {
      status = LoadStatus.error;
      error = firstError?.message ?? 'Could not load your profile.';
      errorOffline = firstError is NetworkException;
      notifyListeners();
      return;
    }
    employee = Employee.fromJson(cached as Map<String, dynamic>);

    // If the profile call failed we are offline: skip the other network calls.
    if (firstError == null) {
      for (final m in _months()) {
        try {
          final recs = await _api.getAttendance(m);
          await _db.putCache('attendance_$m', recs.map((r) => r.toJson()).toList());
        } on ApiException {
          fromCache = true;
        }
      }
      try {
        final b = await _api.getLeaveBalance();
        await _db.putCache('balance', b.toJson());
      } on ApiException {
        fromCache = true;
      }
    }

    await _readLocalData();
    lastUpdated = await _db.cacheUpdatedAt('employee');
    status = LoadStatus.ready;
    notifyListeners();
  }

  /// This month and last month (so "latest 5" works at the start of a month).
  List<String> _months() {
    final y = int.parse(workDate.substring(0, 4));
    final m = int.parse(workDate.substring(5, 7));
    String f(DateTime d) => fmtDate(d).substring(0, 7);
    return [f(DateTime.utc(y, m)), f(DateTime.utc(y, m - 1))];
  }

  /// Rebuild everything the screens show from the cache + local event queue.
  Future<void> _readLocalData() async {
    final server = <AttendanceRecord>[];
    for (final m in _months()) {
      final raw = await _db.getCache('attendance_$m');
      if (raw is List) {
        server.addAll(raw.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)));
      }
    }
    final local = await _db.allEvents();
    records = mergeRecords(server, local);
    allHistory = buildHistory(server, local);
    events = await _db.recentEvents();
    pendingCount = (await _db.pendingEvents()).length;
    final b = await _db.getCache('balance');
    balance = b == null ? null : LeaveBalance.fromJson(b as Map<String, dynamic>);
  }

  void setFilter(HistoryFilter f) {
    filter = f;
    notifyListeners();
  }

  // ---- check in / out ----

  Future<void> checkIn() => _act(AttendanceType.checkIn);
  Future<void> checkOut() => _act(AttendanceType.checkOut);

  /// "Done for today": ends the day (punches out first if still punched in).
  Future<void> markDone() => _act(AttendanceType.done);

  Future<void> _act(AttendanceType type) async {
    final result = await perform(type);
    if (result.outcome == ActionOutcome.ignored) return;
    _post(result.message, openSettings: result.openSettings);
    await load(silent: true);
  }

  Future<ActionResult> perform(AttendanceType type) async {
    // Guard 1: ignore extra taps while one is running.
    if (busy) return const ActionResult(ActionOutcome.ignored, 'Please wait…');
    busy = true;
    notifyListeners();
    try {
      return await _perform(type);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<ActionResult> _perform(AttendanceType type) async {
    final emp = employee;
    if (emp == null) {
      return const ActionResult(ActionOutcome.blocked, 'Open the app online once to load your profile.');
    }
    final office = _settings.effectiveOffice(emp.office);
    final now = _now().toUtc();
    final date = companyDate(now, office.timezone);

    // Rules: punch in/out alternate, any number per day; Done ends the day;
    // nothing is allowed after the day is closed (Done, or 10 PM auto-done).
    await _readLocalData();
    final todayRec = records.where((r) => r.date == date).firstOrNull;
    final summary = AttendanceRules.summarize(date, todayRec?.punches ?? const [], now, office.timezone);
    final violation = AttendanceRules.validate(type, summary);
    if (violation != null) return ActionResult(ActionOutcome.blocked, violation);

    final saved = <AttendanceEvent>[];

    // Punch In / Punch Out need a location inside the geofence. "Done" needs
    // none, unless it must punch you out first.
    if (type != AttendanceType.done || summary.state == DayState.working) {
      final punch = type == AttendanceType.done ? AttendanceType.checkOut : type;
      final captured = await _capturePunch(punch, now, date, office);
      if (captured.blocked != null) return captured.blocked!;
      saved.add(captured.event!);
    }

    if (type == AttendanceType.done) {
      try {
        saved.add(await _db.insertEvent(AttendanceEvent(
          eventId: _newId(),
          type: AttendanceType.done,
          timestamp: now.add(const Duration(milliseconds: 1)), // sorts after the punch-out
          latitude: 0,
          longitude: 0,
          workDate: date,
        )));
      } on DuplicateEventException {
        return const ActionResult(ActionOutcome.blocked, 'Today is already marked as done.');
      }
    }

    await _sync.syncNow(); // try now; events stay pending if offline
    final after = [for (final e in saved) await _db.getEvent(e.eventId)];
    final label = switch (type) {
      AttendanceType.checkIn => 'Punch-in',
      AttendanceType.checkOut => 'Punch-out',
      AttendanceType.done => 'Day done',
    };
    final rejected = after.where((e) => e?.status == SyncStatus.rejected).firstOrNull;
    if (rejected != null) {
      return ActionResult(
          ActionOutcome.rejected, '$label rejected: ${rejected.rejectReason ?? 'refused by server'}');
    }
    if (after.any((e) => e?.status != SyncStatus.synced)) {
      return ActionResult(ActionOutcome.savedPending,
          '$label saved on this device. It will sync when the server is reachable.');
    }
    return ActionResult(ActionOutcome.synced, '$label recorded.');
  }

  /// Location + geofence check, then store one punch event in the local queue.
  Future<({ActionResult? blocked, AttendanceEvent? event})> _capturePunch(
    AttendanceType type,
    DateTime now,
    String date,
    OfficeConfig office,
  ) async {
    ({ActionResult? blocked, AttendanceEvent? event}) block(ActionResult r) => (blocked: r, event: null);

    // Location (real GPS, or the Profile > Location Simulator).
    final LocationResult loc =
        _settings.gpsEnabled ? LocationOk(_settings.gpsLat, _settings.gpsLng) : await _location.current();
    switch (loc) {
      case LocationDenied():
        return block(const ActionResult(
            ActionOutcome.blocked, 'Location permission is required to record attendance.'));
      case LocationDeniedForever():
        return block(const ActionResult(ActionOutcome.blocked,
            'Location permission is permanently denied. Enable it in app settings.',
            openSettings: true));
      case LocationServiceOff():
        return block(const ActionResult(
            ActionOutcome.blocked, 'Location services are off. Turn on GPS and try again.'));
      case LocationUnavailable():
        return block(const ActionResult(
            ActionOutcome.blocked, 'Could not get your location. Move outdoors and try again.'));
      case LocationOk(:final latitude, :final longitude):
        // Geofence (device check only - the server must repeat it).
        final d = distanceMeters(latitude, longitude, office.latitude, office.longitude);
        if (d > office.radiusMeters) {
          return block(ActionResult(
              ActionOutcome.blocked,
              'You are ${d.round()} m from the office. Attendance is only allowed within '
              '${office.radiusMeters.round()} m.'));
        }
        final event = await _db.insertEvent(AttendanceEvent(
          eventId: _newId(),
          type: type,
          timestamp: now,
          latitude: latitude,
          longitude: longitude,
          workDate: date,
        ));
        return (blocked: null, event: event);
    }
  }
  // ---- sync ----

  Future<void> syncNow() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    final r = await _sync.syncNow();
    syncing = false;
    if (r.remaining > 0) {
      _post('${r.remaining} event(s) still pending '
          '(${r.stoppedBy == 'network' ? 'no connection' : 'server problem'}).');
    } else if (r.synced + r.rejected == 0) {
      _post('Nothing to sync.');
    } else {
      _post('Synced ${r.synced}, rejected ${r.rejected}.');
    }
  }

  /// Pull-to-refresh / app resume: push pending events, then reload the screen.
  Future<void> refresh() async {
    await _sync.syncNow();
    await load(silent: true);
  }

  /// Rebuild the screens after time alone changed the state (10 PM auto-done).
  void refreshClock() => notifyListeners();

  /// Reads the phone's real GPS once (the Location Simulator shows it, so you can see
  /// where the phone thinks it is). Asks for permission if needed.
  Future<LocationResult> readRealLocation() => _location.current();

  Future<void> openAppSettings() => _location.openAppSettings();

  void _post(String text, {bool openSettings = false}) {
    message = text;
    messageId++;
    messageOpensSettings = openSettings;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncSub?.cancel();
    super.dispose();
  }
}
