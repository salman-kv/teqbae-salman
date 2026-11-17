/// Plain data models. Dates without time are `yyyy-MM-dd` strings in the
/// company timezone (the "work date" / "leave date").
/// What the employee did. [checkIn] / [checkOut] are shown as "Punch In" /
/// "Punch Out" (wire names kept). [done] ends the day. The enum order matters:
/// it is the tie-break when two events share a timestamp.
enum AttendanceType {
  checkIn('check_in'),
  checkOut('check_out'),
  done('day_done');

  const AttendanceType(this.wire);
  final String wire;
  static AttendanceType fromWire(String s) =>
      AttendanceType.values.firstWhere((e) => e.wire == s);

  String get label => switch (this) {
        checkIn => 'Punch In',
        checkOut => 'Punch Out',
        done => 'Day Done',
      };
}

enum SyncStatus { pending, synced, rejected }

/// Where the employee is in today's day.
enum DayState { notStarted, working, onBreak, done }

/// Final verdict for a finished day.
enum DayResult { inProgress, present, shortHours }

class OfficeConfig {
  const OfficeConfig({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.timezone,
  });

  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String timezone;

  OfficeConfig copyWith({double? latitude, double? longitude, double? radiusMeters}) =>
      OfficeConfig(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        timezone: timezone,
      );

  factory OfficeConfig.fromJson(Map<String, dynamic> j) => OfficeConfig(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        radiusMeters: (j['radiusMeters'] as num).toDouble(),
        timezone: j['timezone'] as String,
      );

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'timezone': timezone,
      };
}

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.department,
    required this.office,
  });

  final String id;
  final String name;
  final String department;
  final OfficeConfig office;

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        id: j['id'] as String,
        name: j['name'] as String,
        department: j['department'] as String,
        office: OfficeConfig.fromJson(j['office'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'department': department,
        'office': office.toJson(),
      };
}

/// One check-in / check-out action, created once on the device.
/// [eventId] is the idempotency key: it never changes across retries.
class AttendanceEvent {
  const AttendanceEvent({
    required this.eventId,
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.workDate,
    this.seq,
    this.status = SyncStatus.pending,
    this.rejectReason,
  });

  final String eventId;
  final int? seq; // local insertion order (set by the DB)
  final AttendanceType type;
  final DateTime timestamp; // UTC
  final double latitude;
  final double longitude;
  final String workDate;
  final SyncStatus status;
  final String? rejectReason;

  Map<String, dynamic> toApiJson() => {
        'eventId': eventId,
        'type': type.wire,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'workDate': workDate,
      };
}

/// One punch (or "done") as the screens see it. [pending] = not yet on the server.
class Punch {
  const Punch({
    required this.eventId,
    required this.type,
    required this.timestamp,
    this.pending = false,
  });

  final String eventId;
  final AttendanceType type;
  final DateTime timestamp; // UTC
  final bool pending;

  factory Punch.fromJson(Map<String, dynamic> j) => Punch(
        eventId: j['eventId'] as String,
        type: AttendanceType.fromWire(j['type'] as String),
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'type': type.wire,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}

/// One day of attendance: every punch of the day (server data + local events).
class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    this.id,
    this.punches = const [],
    this.hasPending = false,
  });

  final String date;
  final String? id; // server id, e.g. ATT-1001 (null until synced)
  final List<Punch> punches;
  final bool hasPending;

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        date: j['date'] as String,
        id: j['id'] as String?,
        punches: [
          for (final e in (j['events'] as List? ?? const []))
            Punch.fromJson(e as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'id': id,
        'events': punches.map((p) => p.toJson()).toList(),
      };
}

/// One card in the Attendance History tab: a day, or one rejected punch.
class HistoryItem {
  const HistoryItem({
    required this.date,
    required this.status,
    this.id,
    this.punches = const [],
    this.reason,
  });

  final String date;
  final SyncStatus status;
  final String? id;
  final List<Punch> punches;
  final String? reason; // why it was rejected
}

class LeaveBalance {
  const LeaveBalance({required this.casual, required this.sick});
  final int casual;
  final int sick;

  int of(LeaveType t) => t == LeaveType.casual ? casual : sick;

  factory LeaveBalance.fromJson(Map<String, dynamic> j) =>
      LeaveBalance(casual: (j['casual'] as num).toInt(), sick: (j['sick'] as num).toInt());

  Map<String, dynamic> toJson() => {'casual': casual, 'sick': sick};
}

enum LeaveType {
  casual,
  sick;

  String get label => this == casual ? 'Casual' : 'Sick';
}

enum LeaveStatus { pending, approved, rejected }

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
  });

  final String id;
  final LeaveType type;
  final String startDate;
  final String endDate;
  final String reason;
  final LeaveStatus status;

  factory LeaveRequest.fromJson(Map<String, dynamic> j) => LeaveRequest(
        id: j['id'] as String,
        type: LeaveType.values.byName(j['type'] as String),
        startDate: j['startDate'] as String,
        endDate: j['endDate'] as String,
        reason: j['reason'] as String,
        status: LeaveStatus.values.byName(j['status'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'startDate': startDate,
        'endDate': endDate,
        'reason': reason,
        'status': status.name,
      };
}

class LeaveDraft {
  const LeaveDraft({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.reason,
  });

  final LeaveType type;
  final String? startDate;
  final String? endDate;
  final String reason;

  Map<String, dynamic> toApiJson() => {
        'type': type.name,
        'startDate': startDate,
        'endDate': endDate,
        'reason': reason.trim(),
      };
}
