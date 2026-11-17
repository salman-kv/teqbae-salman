// Mock REBS HRMS API.
//
// Run:  dart run bin/server.dart
// State is in memory; restart (or GET /__reset) to start clean.
//
// Scenario control (applies to the real endpoints, not the /__ admin ones):
//   GET /__scenario/<name>            -> activate until changed
//   GET /__scenario/<name>?count=1    -> activate for N requests, then back to normal
//   GET /__scenario                   -> show current scenario
//   GET /__leave/<id>/approve|reject  -> decide a Pending leave request (reviewer tool)
//
// Scenarios:
//   normal                successful responses
//   slow                  every API call is delayed 3s (slow but successful)
//   timeout               server never answers (client times out; nothing is stored)
//   timeout_after_accept  POST /attendance/events STORES the event, then hangs
//                         (the "server accepted it but client never heard back" case)
//   server_error          every API call returns 500
//   duplicate_conflict    POST /attendance/events returns 409 ATTENDANCE_EXISTS
//   leave_reject          POST /leave/requests returns 422 with field errors
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

late Map<String, dynamic> config;

// ---- in-memory state ------------------------------------------------------
int attendanceCounter = 1000;

/// One work day: every punch of the day, in order.
/// event = {eventId, type: check_in | check_out | day_done, timestamp}
class AttendanceDay {
  AttendanceDay(this.date) : id = 'ATT-${++attendanceCounter}';
  final String date;
  final String id;
  final List<Map<String, dynamic>> events = [];

  bool get isDone => events.any((e) => e['type'] == 'day_done');
  // Punched in and not yet punched out.
  bool get isOpen =>
      events.where((e) => e['type'] == 'check_in').length >
      events.where((e) => e['type'] == 'check_out').length;
  DateTime? get lastTimestamp =>
      events.isEmpty ? null : DateTime.parse(events.last['timestamp'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'events': events};
}

final Map<String, AttendanceDay> days = {};
// eventId -> stored response (idempotency table)
final Map<String, Map<String, dynamic>> processedEvents = {};
final List<Map<String, dynamic>> leaveRequests = [];
int leaveCounter = 0;

String scenario = 'normal';
int? scenarioRemaining; // null = unlimited

// ---- helpers --------------------------------------------------------------
final _jsonHeaders = {'content-type': 'application/json'};

Response jsonResponse(int status, Object body) =>
    Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response error(int status, String code, String message,
        [Map<String, String>? errors]) =>
    jsonResponse(status, {
      'code': code,
      'message': message,
      if (errors != null) 'errors': errors,
    });

int get offsetMinutes => (config['office']['utcOffsetMinutes'] as num).toInt();

DateTime companyNow() =>
    DateTime.now().toUtc().add(Duration(minutes: offsetMinutes));

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String companyToday() => fmtDate(companyNow());

DateTime parseDate(String s) => DateTime.parse('${s}T00:00:00Z');

/// Unfinished days are closed automatically at this company-time hour.
const autoDoneHour = 22;

/// The auto-done instant (UTC) of a work date.
DateTime autoDoneAt(String workDate) => parseDate(workDate)
    .add(const Duration(hours: autoDoneHour))
    .subtract(Duration(minutes: offsetMinutes));

double haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

int leaveDays(String start, String end) =>
    parseDate(end).difference(parseDate(start)).inDays + 1;

/// Remaining days for one leave type (pending + approved requests reserve days).
int availableBalance(String type) {
  final used = leaveRequests
      .where((r) =>
          r['type'] == type && (r['status'] == 'pending' || r['status'] == 'approved'))
      .fold<int>(0, (s, r) => s + leaveDays(r['startDate'], r['endDate']));
  return (config['leaveTotalDays'][type] as int) - used;
}

void seed() {
  days.clear();
  processedEvents.clear();
  leaveRequests.clear();
  leaveCounter = 0;
  attendanceCounter = 1000;
  final today = companyNow();
  // Previous 6 days with several punches each. Times are "HH:MM" company time:
  // [in, out, in, out, ..., 'done' time or null]. Day 2 and 5 are under 8 h
  // (short hours); day 6 is never punched out or marked done (auto-closed 10 PM).
  const pattern = <int, List<String?>>{
    1: ['09:00', '13:10', '14:00', '18:05', '18:06'],
    2: ['09:10', '12:40', '13:30', '17:00', '17:01'],
    3: ['08:55', '13:00', '14:00', '18:10', '18:11'],
    4: ['09:05', '17:50', '17:51'],
    5: ['09:20', '14:00', '14:01'],
    6: ['09:00', '13:00', '14:00'],
  };
  // The last 6 working days (Saturday and Sunday are weekly offs: no records).
  final workDays = <DateTime>[];
  var cursor = DateTime.utc(today.year, today.month, today.day);
  while (workDays.length < pattern.length) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (cursor.weekday != DateTime.saturday && cursor.weekday != DateTime.sunday) {
      workDays.add(cursor);
    }
  }
  for (final entry in pattern.entries) {
    final d = workDays[entry.key - 1];
    final rec = AttendanceDay(fmtDate(d));
    final localMidnightUtc = d.subtract(Duration(minutes: offsetMinutes));
    final times = entry.value;
    final hasDone = entry.key != 6;
    for (var n = 0; n < times.length; n++) {
      final parts = times[n]!.split(':');
      final ts = localMidnightUtc
          .add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
      final isDone = hasDone && n == times.length - 1;
      rec.events.add({
        'eventId': 'seed-${entry.key}-$n',
        'type': isDone ? 'day_done' : (n.isEven ? 'check_in' : 'check_out'),
        'timestamp': ts.toIso8601String(),
      });
    }
    days[rec.date] = rec;
  }
  final base = DateTime.utc(today.year, today.month, today.day);
  void addLeave(String type, int fromDays, int toDays, String reason,
      String status) {
    leaveCounter++;
    leaveRequests.add({
      'id': 'LV-$leaveCounter',
      'type': type,
      'startDate': fmtDate(base.add(Duration(days: fromDays))),
      'endDate': fmtDate(base.add(Duration(days: toDays))),
      'reason': reason,
      'status': status,
    });
  }

  addLeave('casual', 10, 11, 'Family function out of town', 'approved');
  addLeave('sick', 20, 20, 'Scheduled dental surgery', 'pending');
  addLeave('casual', -20, -19, 'Personal errands at the bank', 'rejected');
}

// ---- scenario middleware --------------------------------------------------
bool _consumeScenario() {
  if (scenarioRemaining != null) {
    scenarioRemaining = scenarioRemaining! - 1;
    if (scenarioRemaining! <= 0) {
      scenario = 'normal';
      scenarioRemaining = null;
    }
  }
  return true;
}

Middleware scenarioMiddleware() => (inner) => (request) async {
      final path = '/${request.url.path}';
      if (path.startsWith('/__')) return inner(request);
      final active = scenario;
      switch (active) {
        case 'slow':
          _consumeScenario();
          await Future<void>.delayed(const Duration(seconds: 3));
          return inner(request);
        case 'timeout':
          _consumeScenario();
          await Future<void>.delayed(const Duration(minutes: 2));
          return error(504, 'TIMEOUT', 'Gateway timeout');
        case 'server_error':
          _consumeScenario();
          return error(500, 'SERVER_ERROR', 'Simulated internal server error');
        case 'timeout_after_accept':
          if (request.method == 'POST' && path == '/attendance/events') {
            _consumeScenario();
            // Process the event for real, then never answer in time.
            await inner(request);
            await Future<void>.delayed(const Duration(minutes: 2));
            return error(504, 'TIMEOUT', 'Gateway timeout');
          }
          return inner(request);
        case 'duplicate_conflict':
          if (request.method == 'POST' && path == '/attendance/events') {
            _consumeScenario();
            return error(409, 'ATTENDANCE_EXISTS',
                'Attendance already exists for this day.');
          }
          return inner(request);
        case 'leave_reject':
          if (request.method == 'POST' && path == '/leave/requests') {
            _consumeScenario();
            return error(422, 'LEAVE_REJECTED',
                'Leave request rejected by server policy.', {
              'startDate': 'Leave is blocked during the payroll freeze window.',
            });
          }
          return inner(request);
        default:
          return inner(request);
      }
    };

// ---- handlers -------------------------------------------------------------
Response getEmployee(Request _) => jsonResponse(200, {
      ...config['employee'] as Map<String, dynamic>,
      'office': {
        'latitude': config['office']['latitude'],
        'longitude': config['office']['longitude'],
        'radiusMeters': config['office']['radiusMeters'],
        'timezone': config['office']['timezone'],
      },
    });

Response getAttendance(Request r) {
  final month = r.url.queryParameters['month'] ?? companyToday().substring(0, 7);
  final records = days.values.where((d) => d.date.startsWith(month)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return jsonResponse(200, {'records': records.map((e) => e.toJson()).toList()});
}

Future<Response> postEvent(Request r) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return error(400, 'BAD_REQUEST', 'Malformed JSON');
  }
  final eventId = body['eventId'] as String?;
  final type = body['type'] as String?;
  final workDate = body['workDate'] as String?;
  final ts = DateTime.tryParse('${body['timestamp']}');
  final lat = (body['latitude'] as num?)?.toDouble();
  final lng = (body['longitude'] as num?)?.toDouble();
  if (eventId == null || workDate == null || ts == null || lat == null || lng == null ||
      (type != 'check_in' && type != 'check_out' && type != 'day_done')) {
    return error(400, 'BAD_REQUEST', 'Missing or invalid fields');
  }

  // IDEMPOTENCY: same eventId => same answer, no second record.
  final previous = processedEvents[eventId];
  if (previous != null) {
    return jsonResponse(200, {...previous, 'duplicate': true});
  }

  // Server-side re-validation (never trust the device).
  final office = config['office'] as Map<String, dynamic>;
  if (type != 'day_done') {
    // "Done" carries no position; punches must be inside the office radius.
    final dist = haversine(lat, lng, (office['latitude'] as num).toDouble(),
        (office['longitude'] as num).toDouble());
    if (dist > (office['radiusMeters'] as num)) {
      return error(422, 'OUTSIDE_GEOFENCE',
          'Outside permitted area (${dist.round()} m from office).');
    }
  }
  if (ts.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
    return error(422, 'TIMESTAMP_IN_FUTURE', 'Event timestamp is in the future.');
  }
  // The work date must be the company date of the timestamp (server's own calculation).
  if (fmtDate(ts.toUtc().add(Duration(minutes: offsetMinutes))) != workDate) {
    return error(422, 'WORKDATE_MISMATCH', 'Work date does not match the timestamp.');
  }

  final day = days[workDate] ?? AttendanceDay(workDate); // stored only on success
  final last = day.lastTimestamp;
  if (last != null && ts.isBefore(last)) {
    return error(422, 'OUT_OF_ORDER', 'This event is older than the last one for $workDate.');
  }
  if (day.isDone) {
    return error(409, 'DAY_CLOSED', 'The day $workDate is already marked as done.');
  }
  switch (type) {
    case 'check_in':
      if (!ts.isBefore(autoDoneAt(workDate))) {
        return error(422, 'DAY_CLOSED', 'The day closes automatically at $autoDoneHour:00.');
      }
      if (day.isOpen) {
        return error(409, 'ALREADY_PUNCHED_IN', 'Already punched in for $workDate.');
      }
    case 'check_out':
      if (!day.isOpen) {
        return error(422, 'CHECKIN_REQUIRED', 'Cannot punch out before punching in.');
      }
    case 'day_done':
      if (day.events.isEmpty) {
        return error(422, 'NO_PUNCHES', 'Punch in at least once before marking the day done.');
      }
      if (day.isOpen) {
        return error(422, 'PUNCH_OUT_REQUIRED', 'Punch out before marking the day done.');
      }
  }
  day.events.add({
    'eventId': eventId,
    'type': type,
    'timestamp': ts.toUtc().toIso8601String(),
  });
  days[workDate] = day;
  final stored = {'status': 'accepted', 'eventId': eventId, 'duplicate': false};
  processedEvents[eventId] = stored;
  return jsonResponse(201, stored);
}
Response getBalance(Request _) => jsonResponse(
    200, {'casual': availableBalance('casual'), 'sick': availableBalance('sick')});

Response getLeaves(Request _) => jsonResponse(200, {'requests': leaveRequests});

Future<Response> postLeave(Request r) async {
  final Map<String, dynamic> b;
  try {
    b = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return error(400, 'BAD_REQUEST', 'Malformed JSON');
  }
  final type = b['type'] as String?;
  final start = b['startDate'] as String?;
  final end = b['endDate'] as String?;
  final reason = (b['reason'] as String? ?? '');
  final errors = <String, String>{};
  if (type != 'casual' && type != 'sick') errors['type'] = 'Invalid leave type.';
  DateTime? s, e;
  try {
    s = parseDate(start ?? '');
    e = parseDate(end ?? '');
  } catch (_) {
    errors['startDate'] = 'Invalid date.';
  }
  if (s != null && e != null) {
    if (start!.compareTo(companyToday()) < 0) {
      errors['startDate'] = 'Start date is in the past.';
    }
    if (e.isBefore(s)) errors['endDate'] = 'End date is before start date.';
    if (errors.isEmpty) {
      if (leaveDays(start, end!) > availableBalance(type!)) {
        errors['endDate'] = 'Not enough $type leave balance.';
      }
      for (final x in leaveRequests) {
        if (x['status'] == 'rejected') continue;
        final xs = parseDate(x['startDate']), xe = parseDate(x['endDate']);
        if (!s.isAfter(xe) && !e.isBefore(xs)) {
          errors['startDate'] = 'Overlaps existing ${x['status']} request ${x['id']}.';
        }
      }
    }
  }
  if (reason.replaceAll(RegExp(r'\s'), '').length < 10) {
    errors['reason'] = 'Reason must have at least 10 non-space characters.';
  }
  if (errors.isNotEmpty) {
    return error(422, 'VALIDATION_FAILED', 'Leave request failed validation.', errors);
  }
  leaveCounter++;
  final created = {
    'id': 'LV-$leaveCounter',
    'type': type,
    'startDate': start,
    'endDate': end,
    'reason': reason.trim(),
    'status': 'pending',
  };
  leaveRequests.add(created);
  return jsonResponse(201, created);
}

// ---- admin ----------------------------------------------------------------

/// Reviewer control (stands in for a manager): GET /__leave/<id>/approve or /reject.
/// Only a Pending request can be decided. A rejected request frees its days
/// (the balance counts Pending and Approved requests only).
Response reviewLeave(Request r, String id, String action) {
  if (action != 'approve' && action != 'reject') {
    return error(400, 'BAD_ACTION', 'Use approve or reject.');
  }
  final i = leaveRequests.indexWhere((x) => x['id'] == id);
  if (i < 0) return error(404, 'NOT_FOUND', 'Leave request $id not found.');
  final req = leaveRequests[i];
  if (req['status'] != 'pending') {
    return error(409, 'NOT_PENDING', 'Request $id is already ${req['status']}.');
  }
  req['status'] = action == 'approve' ? 'approved' : 'rejected';
  return jsonResponse(200, req);
}

Response setScenario(Request r, String name) {
  const known = {
    'normal', 'slow', 'timeout', 'timeout_after_accept',
    'server_error', 'duplicate_conflict', 'leave_reject',
  };
  if (!known.contains(name)) {
    return jsonResponse(400, {'message': 'Unknown scenario', 'known': known.toList()});
  }
  scenario = name;
  scenarioRemaining = int.tryParse(r.url.queryParameters['count'] ?? '');
  return jsonResponse(200, {'scenario': scenario, 'remaining': scenarioRemaining});
}

Future<Response> setConfig(Request r) async {
  // POST /__config  {"latitude":..,"longitude":..,"radiusMeters":..}
  final b = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final office = config['office'] as Map<String, dynamic>;
  for (final k in ['latitude', 'longitude', 'radiusMeters']) {
    if (b[k] is num) office[k] = b[k];
  }
  return jsonResponse(200, office);
}

Future<void> main() async {
  config = jsonDecode(File('config.json').readAsStringSync()) as Map<String, dynamic>;
  seed();

  final router = Router()
    ..get('/employee/me', getEmployee)
    ..get('/attendance', getAttendance)
    ..post('/attendance/events', postEvent)
    ..get('/leave/balance', getBalance)
    ..get('/leave/requests', getLeaves)
    ..post('/leave/requests', postLeave)
    ..get('/__scenario', (Request _) =>
        jsonResponse(200, {'scenario': scenario, 'remaining': scenarioRemaining}))
    ..get('/__scenario/<name>', setScenario)
    ..get('/__leave/<id>/<action>', reviewLeave)
    ..post('/__config', setConfig)
    ..get('/__config', (Request _) => jsonResponse(200, config['office']))
    ..get('/__reset', (Request _) {
      seed();
      scenario = 'normal';
      scenarioRemaining = null;
      return jsonResponse(200, {'reset': true});
    });

  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: (m, isError) => print('[mock] $m')))
      .addMiddleware(scenarioMiddleware())
      .addHandler(router.call);

  final port = (config['port'] as num).toInt();
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('REBS mock API on http://0.0.0.0:${server.port}  (emulator: http://10.0.2.2:$port)');
  print('Office: ${config['office']}');
}
