import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

// ---------------------------------------------------------------- dates ----

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) => DateTime.parse('${s}T00:00:00Z');

/// Company calendar date for an instant. Needs `tz.initializeTimeZones()`.
String companyDate(DateTime instant, String timezone) {
  final local = tz.TZDateTime.from(instant.toUtc(), tz.getLocation(timezone));
  return fmtDate(local);
}

int leaveDayCount(String start, String end) =>
    parseDate(end).difference(parseDate(start)).inDays + 1;

// ------------------------------------------------------------- geofence ----

/// Great-circle distance in metres (haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

// ----------------------------------------------------------- attendance ----

/// One stretch of work: a punch-in and its punch-out. [outAt] is null while the
/// employee is still punched in. [autoClosed] = ended by the 10 PM auto-done.
class Session {
  const Session(this.inAt, this.outAt, {this.autoClosed = false});
  final DateTime inAt;
  final DateTime? outAt;
  final bool autoClosed;

  Duration duration(DateTime now) {
    final d = (outAt ?? now).difference(inAt);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Everything the screens need to know about one day, derived from its punches.
class DaySummary {
  const DaySummary({
    required this.date,
    required this.punches,
    required this.sessions,
    required this.total,
    required this.state,
    required this.result,
    required this.dayOver,
    this.closedBy,
    this.autoClosedAt,
  });

  final String date;
  final List<Punch> punches; // sorted by time
  final List<Session> sessions;
  final Duration total; // sum of all sessions (an open one counts up to "now")
  final DayState state;
  final DayResult result;
  final bool dayOver; // the 10 PM cut-off has passed
  final String? closedBy; // 'manual' | 'auto' | null
  final DateTime? autoClosedAt;

  DateTime? get firstIn => sessions.isEmpty ? null : sessions.first.inAt;
  DateTime? get lastOut {
    for (final s in sessions.reversed) {
      if (s.outAt != null) return s.outAt;
    }
    return null;
  }

  bool get isOpen => state == DayState.working;
  Duration get remaining {
    final r = AttendanceRules.target - total;
    return r.isNegative ? Duration.zero : r;
  }
}

class AttendanceRules {
  /// A full working day. Less than this counts as leave (short hours).
  static const target = Duration(hours: 8);

  /// Company-time hour at which an unfinished day is closed automatically.
  static const autoDoneHour = 22;

  /// The auto-done instant (UTC) of a work date in the company timezone.
  static DateTime cutoffOf(String date, String timezone) {
    final d = parseDate(date);
    return tz.TZDateTime(tz.getLocation(timezone), d.year, d.month, d.day, autoDoneHour).toUtc();
  }

  /// Turn a day's punches into sessions, a total and a state.
  ///  * Punch In starts a session, Punch Out ends it; any number per day.
  ///  * "Done" ends the day. An open session is closed at that moment.
  ///  * At 10 PM an unfinished day is closed automatically (open session ends at 10 PM).
  ///  * A finished day with a total under 8 h is "short hours" (treated as leave).
  static DaySummary summarize(
    String date,
    List<Punch> punches,
    DateTime now,
    String timezone,
  ) {
    final sorted = [...punches]..sort((a, b) {
        final c = a.timestamp.compareTo(b.timestamp);
        return c != 0 ? c : a.type.index.compareTo(b.type.index);
      });
    final cutoff = cutoffOf(date, timezone);
    final dayOver = !now.toUtc().isBefore(cutoff);

    final sessions = <Session>[];
    DateTime? openIn;
    DateTime? doneAt;
    for (final p in sorted) {
      if (p.type == AttendanceType.checkIn) {
        openIn ??= p.timestamp;
      } else if (p.type == AttendanceType.checkOut) {
        if (openIn != null) {
          sessions.add(Session(openIn, p.timestamp));
          openIn = null;
        }
      } else {
        doneAt = p.timestamp;
        break;
      }
    }

    DateTime? autoClosedAt;
    if (openIn != null && doneAt != null) {
      sessions.add(Session(openIn, doneAt));
      openIn = null;
    } else if (openIn != null && dayOver) {
      final end = openIn.isBefore(cutoff) ? cutoff : openIn;
      sessions.add(Session(openIn, end, autoClosed: true));
      autoClosedAt = end;
      openIn = null;
    }
    if (openIn != null) sessions.add(Session(openIn, null));

    final closed = doneAt != null || (dayOver && sorted.isNotEmpty);
    final total = sessions.fold(Duration.zero, (sum, s) => sum + s.duration(now));
    final state = closed
        ? DayState.done
        : openIn != null
            ? DayState.working
            : sessions.isNotEmpty
                ? DayState.onBreak
                : DayState.notStarted;
    final result = !closed
        ? DayResult.inProgress
        : total >= target
            ? DayResult.present
            : DayResult.shortHours;

    return DaySummary(
      date: date,
      punches: sorted,
      sessions: sessions,
      total: total,
      state: state,
      result: result,
      dayOver: dayOver,
      closedBy: doneAt != null ? 'manual' : (closed ? 'auto' : null),
      autoClosedAt: autoClosedAt,
    );
  }

  /// Returns an error message, or null when the action is allowed.
  static String? validate(AttendanceType type, DaySummary s) {
    switch (type) {
      case AttendanceType.checkIn:
        if (s.state == DayState.done || s.dayOver) {
          return s.closedBy == 'manual'
              ? 'You marked today as done. You can punch in again tomorrow.'
              : 'The day closes at 10:00 PM. You can punch in again tomorrow.';
        }
        if (s.state == DayState.working) return 'You are already punched in.';
        return null;
      case AttendanceType.checkOut:
        if (s.state == DayState.working) return null;
        if (s.state == DayState.done) return 'Your day is already closed.';
        return 'You must punch in before punching out.';
      case AttendanceType.done:
        if (s.state == DayState.done) return 'Today is already marked as done.';
        if (s.state == DayState.notStarted) return 'Punch in at least once before marking the day done.';
        return null;
    }
  }
}

/// Overlay local events on server records, one row per day, newest first.
/// Punches are matched by eventId, so an event that is both on the server and
/// in the local queue is counted once. Rejected events never appear in a day.
List<AttendanceRecord> mergeRecords(
  List<AttendanceRecord> server,
  List<AttendanceEvent> local,
) {
  final ids = <String, String?>{};
  final byDate = <String, Map<String, Punch>>{};
  final pending = <String>{};
  for (final r in server) {
    ids[r.date] = r.id;
    byDate[r.date] = {for (final p in r.punches) p.eventId: p};
  }
  for (final e in local) {
    if (e.status == SyncStatus.rejected) continue;
    final isPending = e.status == SyncStatus.pending;
    (byDate[e.workDate] ??= {})[e.eventId] =
        Punch(eventId: e.eventId, type: e.type, timestamp: e.timestamp, pending: isPending);
    if (isPending) pending.add(e.workDate);
  }
  final list = [
    for (final d in byDate.entries)
      AttendanceRecord(
        date: d.key,
        id: ids[d.key],
        punches: d.value.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
        hasPending: pending.contains(d.key),
      ),
  ]..sort((a, b) => b.date.compareTo(a.date));
  return list;
}

/// Cards for the Attendance History tab: one per day (synced or pending),
/// plus one per rejected event. Newest first.
List<HistoryItem> buildHistory(List<AttendanceRecord> server, List<AttendanceEvent> local) {
  final items = <HistoryItem>[
    for (final r in mergeRecords(server, local))
      HistoryItem(
        date: r.date,
        id: r.id,
        punches: r.punches,
        status: r.hasPending ? SyncStatus.pending : SyncStatus.synced,
      ),
    for (final e in local)
      if (e.status == SyncStatus.rejected)
        HistoryItem(
          date: e.workDate,
          status: SyncStatus.rejected,
          punches: [Punch(eventId: e.eventId, type: e.type, timestamp: e.timestamp)],
          reason: e.rejectReason,
        ),
  ];
  items.sort((a, b) => b.date.compareTo(a.date));
  return items;
}

// ---------------------------------------------------------------- leave ----

class LeaveRules {
  /// Returns field -> message. Keys: startDate, endDate, reason, general.
  /// Empty map = valid.
  static Map<String, String> validate({
    required LeaveDraft draft,
    required String today,
    required int available,
    required List<LeaveRequest> existing,
  }) {
    final errors = <String, String>{};
    final start = draft.startDate;
    final end = draft.endDate;

    if (start == null) errors['startDate'] = 'Select a start date.';
    if (end == null) errors['endDate'] = 'Select an end date.';
    if (start != null && start.compareTo(today) < 0) {
      errors['startDate'] = 'Start date cannot be before today ($today).';
    }
    if (start != null && end != null && end.compareTo(start) < 0) {
      errors['endDate'] = 'End date cannot be before the start date.';
    }
    if (draft.reason.replaceAll(RegExp(r'\s'), '').length < 10) {
      errors['reason'] = 'Reason needs at least 10 non-space characters.';
    }

    if (start != null && end != null && !errors.containsKey('startDate') && !errors.containsKey('endDate')) {
      final days = leaveDayCount(start, end);
      if (days > available) {
        errors['endDate'] = 'Requested $days day(s) but only $available available.';
      }
      for (final r in existing) {
        if (r.status == LeaveStatus.rejected) continue;
        final overlaps = start.compareTo(r.endDate) <= 0 && end.compareTo(r.startDate) >= 0;
        if (overlaps) {
          errors['startDate'] =
              'Overlaps your ${r.status.name} request (${r.startDate} to ${r.endDate}).';
          break;
        }
      }
    }
    return errors;
  }
}
