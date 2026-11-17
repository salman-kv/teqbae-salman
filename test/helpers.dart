import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teqbae_salman/controllers/attendance_controller.dart';
import 'package:teqbae_salman/controllers/leave_controller.dart';
import 'package:teqbae_salman/controllers/settings_controller.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/services/api_service.dart';
import 'package:teqbae_salman/services/local_db.dart';
import 'package:teqbae_salman/services/location_service.dart';
import 'package:teqbae_salman/services/sync_service.dart';

const officeLat = 12.9716;
const officeLng = 77.5946;

/// Fixed "now": 2026-11-16 09:30 in Asia/Kolkata.
final fixedNow = DateTime.utc(2026, 11, 16, 4, 0);

/// In-memory stand-in for the backend. Mirrors the real contract:
/// events are deduplicated by eventId.
class FakeApi implements RebsApi {
  bool offline = false;
  bool serverError = false;
  bool conflict = false;

  /// Save the next event, but pretend the response never arrived (timeout).
  bool dropResponseOnce = false;

  final Map<String, AttendanceEvent> accepted = {}; // what the "server" stored
  final List<String> postedIds = []; // every POST attempt, in order
  final List<AttendanceType> postedTypes = [];
  int leavePosts = 0;

  final List<LeaveRequest> leave = [
    const LeaveRequest(
      id: 'LV-1',
      type: LeaveType.casual,
      startDate: '2026-11-20',
      endDate: '2026-11-21',
      reason: 'Family function out of town',
      status: LeaveStatus.approved,
    ),
  ];

  void _check() {
    if (offline) throw const NetworkException();
    if (serverError) throw const ServerException();
  }

  @override
  Future<Employee> getEmployee() async {
    _check();
    return const Employee(
      id: 'EMP-1',
      name: 'Test User',
      department: 'QA',
      office: OfficeConfig(
          latitude: officeLat, longitude: officeLng, radiusMeters: 200, timezone: 'Asia/Kolkata'),
    );
  }

  @override
  Future<List<AttendanceRecord>> getAttendance(String month) async {
    _check();
    return [];
  }

  @override
  Future<void> postAttendanceEvent(AttendanceEvent e) async {
    if (offline) throw const NetworkException(); // never reached the server
    postedIds.add(e.eventId);
    postedTypes.add(e.type);
    if (serverError) throw const ServerException();
    if (conflict) throw const ConflictException('Attendance already exists for this day.');
    accepted.putIfAbsent(e.eventId, () => e); // idempotent on eventId
    if (dropResponseOnce) {
      dropResponseOnce = false;
      throw const NetworkException('timeout');
    }
  }

  @override
  Future<LeaveBalance> getLeaveBalance() async {
    _check();
    return const LeaveBalance(casual: 8, sick: 5);
  }

  @override
  Future<List<LeaveRequest>> getLeaveRequests() async {
    _check();
    return List.of(leave);
  }

  @override
  Future<LeaveRequest> postLeaveRequest(LeaveDraft d) async {
    _check();
    leavePosts++;
    return LeaveRequest(
      id: 'LV-${leave.length + 1}',
      type: d.type,
      startDate: d.startDate!,
      endDate: d.endDate!,
      reason: d.reason,
      status: LeaveStatus.pending,
    );
  }

  @override
  Future<void> setMockScenario(String name, {bool once = false}) async {}

  @override
  Future<LeaveRequest> reviewLeave(String id, {required bool approve}) async {
    _check();
    final i = leave.indexWhere((r) => r.id == id);
    final old = leave[i];
    if (old.status != LeaveStatus.pending) {
      throw ConflictException('Request $id is already ${old.status.name}.');
    }
    final updated = LeaveRequest(
      id: old.id,
      type: old.type,
      startDate: old.startDate,
      endDate: old.endDate,
      reason: old.reason,
      status: approve ? LeaveStatus.approved : LeaveStatus.rejected,
    );
    leave[i] = updated;
    return updated;
  }
}

class FakeLocation implements LocationService {
  LocationResult result = const LocationOk(officeLat, officeLng);

  @override
  Future<LocationResult> current() async => result;

  @override
  Future<void> openAppSettings() async {}
}

/// Opens a file-backed SQLite DB (so tests can close and reopen it).
Future<LocalDb> openTestDb(String path) {
  sqfliteFfiInit();
  return LocalDb.open(path, factory: databaseFactoryFfi);
}

String tempDbPath() =>
    '${Directory.systemTemp.createTempSync('rebs_test_').path}${Platform.pathSeparator}test.db';

/// Everything wired together like in main(), but with fakes.
class Env {
  Env._(this.path, this.db, this.api, this.location, this.sync, this.settings, this.attendance, this.leave);

  final String path;
  final LocalDb db;
  final FakeApi api;
  final FakeLocation location;
  final SyncService sync;
  final SettingsController settings;
  final AttendanceController attendance;
  final LeaveController leave;

  static Future<Env> create(
      {String? path, FakeApi? api, DateTime? now, DateTime Function()? clock}) async {
    final p = path ?? tempDbPath();
    final db = await openTestDb(p);
    final fake = api ?? FakeApi();
    final location = FakeLocation();
    final sync = SyncService(fake, db);
    final settings = SettingsController(db, fake);
    var n = 0;
    DateTime nowFn() => clock?.call() ?? now ?? fixedNow;
    final attendance = AttendanceController(
      api: fake,
      db: db,
      location: location,
      sync: sync,
      settings: settings,
      now: nowFn,
      newId: () => 'evt-${++n}',
    );
    final leave = LeaveController(fake, db, now: nowFn);
    return Env._(p, db, fake, location, sync, settings, attendance, leave);
  }

  Future<void> dispose() async {
    await attendance.settled; // let any background refresh finish before closing the DB
    attendance.dispose();
    await sync.dispose();
    await db.close();
  }
}
