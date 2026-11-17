import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

class DuplicateEventException implements Exception {
  const DuplicateEventException();
}

/// SQLite storage for (1) the offline queue / event log and (2) a JSON cache.
///
/// The queue lives in a real table (not a JSON blob) so ordering and the
/// "one Done per day" rule are enforced by the database.
class LocalDb {
  LocalDb._(this._db);
  final Database _db;

  /// A day can be marked done only once (a double tap on "Done" can't create two).
  /// Punches alternate in/out, which the controller checks (and its `busy` flag
  /// ignores taps while one is running).
  static const _doneIndexSql = '''
    CREATE UNIQUE INDEX uq_done_event
    ON attendance_events(work_date)
    WHERE type = 'day_done' AND status != 'rejected' ''';

  static Future<LocalDb> open(String path, {DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: (db, oldVersion, _) async {
          // v2: many punches per day are allowed; only "done" stays unique.
          if (oldVersion < 2) {
            await db.execute('DROP INDEX IF EXISTS uq_active_event');
            await db.execute(_doneIndexSql);
          }
        },
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE cache(
              key TEXT PRIMARY KEY,
              json TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )''');
          await db.execute('''
            CREATE TABLE attendance_events(
              seq INTEGER PRIMARY KEY AUTOINCREMENT,
              event_id TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              lat REAL NOT NULL,
              lng REAL NOT NULL,
              work_date TEXT NOT NULL,
              status TEXT NOT NULL,
              reject_reason TEXT
            )''');
          await db.execute(_doneIndexSql);
        },
      ),
    );
    return LocalDb._(db);
  }

  Future<void> close() => _db.close();

  // ------------------------------------------------------------- cache ----

  Future<void> putCache(String key, Object json) async {
    await _db.insert(
      'cache',
      {'key': key, 'json': jsonEncode(json), 'updated_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCache(String key) async {
    await _db.delete('cache', where: 'key = ?', whereArgs: [key]);
  }

  Future<dynamic> getCache(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String);
  }

  Future<DateTime?> cacheUpdatedAt(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['updated_at'] as int);
  }

  // ------------------------------------------------------------ events ----

  /// Insert a new pending event. Throws [DuplicateEventException] if the day
  /// is already marked done.
  Future<AttendanceEvent> insertEvent(AttendanceEvent e) async {
    try {
      final seq = await _db.insert('attendance_events', {
        'event_id': e.eventId,
        'type': e.type.wire,
        'timestamp': e.timestamp.toUtc().toIso8601String(),
        'lat': e.latitude,
        'lng': e.longitude,
        'work_date': e.workDate,
        'status': SyncStatus.pending.name,
      });
      return AttendanceEvent(
        eventId: e.eventId,
        type: e.type,
        timestamp: e.timestamp,
        latitude: e.latitude,
        longitude: e.longitude,
        workDate: e.workDate,
        seq: seq,
      );
    } on DatabaseException catch (ex) {
      if (ex.isUniqueConstraintError()) throw const DuplicateEventException();
      rethrow;
    }
  }

  Future<AttendanceEvent?> getEvent(String eventId) async {
    final rows = await _db.query('attendance_events', where: 'event_id = ?', whereArgs: [eventId]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// All non-rejected + rejected events, oldest first.
  Future<List<AttendanceEvent>> allEvents() async =>
      (await _db.query('attendance_events', orderBy: 'seq ASC')).map(_fromRow).toList();

  /// Latest events first (for the activity list).
  Future<List<AttendanceEvent>> recentEvents({int limit = 10}) async =>
      (await _db.query('attendance_events', orderBy: 'seq DESC', limit: limit))
          .map(_fromRow)
          .toList();

  /// Pending events in the exact order they were created.
  Future<List<AttendanceEvent>> pendingEvents() async => (await _db.query(
        'attendance_events',
        where: 'status = ?',
        whereArgs: [SyncStatus.pending.name],
        orderBy: 'seq ASC',
      ))
          .map(_fromRow)
          .toList();

  Future<void> setStatus(String eventId, SyncStatus status, {String? reason}) async {
    await _db.update(
      'attendance_events',
      {'status': status.name, 'reject_reason': reason},
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
  }

  AttendanceEvent _fromRow(Map<String, Object?> r) => AttendanceEvent(
        eventId: r['event_id'] as String,
        seq: r['seq'] as int,
        type: AttendanceType.fromWire(r['type'] as String),
        timestamp: DateTime.parse(r['timestamp'] as String),
        latitude: (r['lat'] as num).toDouble(),
        longitude: (r['lng'] as num).toDouble(),
        workDate: r['work_date'] as String,
        status: SyncStatus.values.byName(r['status'] as String),
        rejectReason: r['reject_reason'] as String?,
      );
}
