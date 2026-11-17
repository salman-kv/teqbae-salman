import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/models/rules.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Pure rules: sessions, total hours, the 10 PM auto-done, short hours.
/// Company timezone is Asia/Kolkata (UTC+5:30), work date 2026-11-16.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  const tzName = 'Asia/Kolkata';
  const date = '2026-11-16';

  /// "HH:MM" company time -> UTC instant.
  DateTime ist(int h, int m) => DateTime.utc(2026, 11, 16, h, m).subtract(const Duration(hours: 5, minutes: 30));

  Punch p(AttendanceType type, DateTime at) =>
      Punch(eventId: '${type.wire}-${at.toIso8601String()}', type: type, timestamp: at);
  Punch inAt(int h, int m) => p(AttendanceType.checkIn, ist(h, m));
  Punch outAt(int h, int m) => p(AttendanceType.checkOut, ist(h, m));
  Punch doneAt(int h, int m) => p(AttendanceType.done, ist(h, m));

  DaySummary at(List<Punch> punches, DateTime now) =>
      AttendanceRules.summarize(date, punches, now, tzName);

  test('no punches: not started', () {
    final s = at([], ist(9, 0));
    expect(s.state, DayState.notStarted);
    expect(s.total, Duration.zero);
  });

  test('total is the sum of every in/out pair', () {
    final s = at([inAt(9, 0), outAt(13, 0), inAt(14, 0), outAt(18, 30)], ist(19, 0));
    expect(s.sessions.length, 2);
    expect(s.total, const Duration(hours: 8, minutes: 30));
    expect(s.state, DayState.onBreak);
    expect(s.firstIn, ist(9, 0));
    expect(s.lastOut, ist(18, 30));
  });

  test('an open session counts up to "now"', () {
    final s = at([inAt(9, 0), outAt(13, 0), inAt(14, 0)], ist(15, 30));
    expect(s.state, DayState.working);
    expect(s.total, const Duration(hours: 5, minutes: 30));
  });

  test('Done closes the day; under 8h is short hours (leave)', () {
    final s = at([inAt(9, 0), outAt(14, 0), doneAt(14, 1)], ist(15, 0));
    expect(s.state, DayState.done);
    expect(s.closedBy, 'manual');
    expect(s.total, const Duration(hours: 5));
    expect(s.result, DayResult.shortHours);
  });

  test('exactly 8h is a full day (present)', () {
    final s = at([inAt(9, 0), outAt(13, 0), inAt(14, 0), outAt(18, 0), doneAt(18, 1)], ist(19, 0));
    expect(s.total, const Duration(hours: 8));
    expect(s.result, DayResult.present);
  });

  test('day still open: result is in progress, not leave', () {
    final s = at([inAt(9, 0), outAt(11, 0)], ist(12, 0));
    expect(s.result, DayResult.inProgress);
  });

  group('10 PM auto-done', () {
    test('an open session is closed at 10 PM, not later', () {
      // Punched in at 14:00 and forgot to punch out. Looking at it next morning.
      final s = AttendanceRules.summarize(date, [inAt(14, 0)], ist(23, 59).add(const Duration(hours: 9)), tzName);
      expect(s.state, DayState.done);
      expect(s.closedBy, 'auto');
      expect(s.autoClosedAt, ist(22, 0));
      expect(s.total, const Duration(hours: 8)); // 14:00 -> 22:00
      expect(s.result, DayResult.present);
      expect(s.sessions.single.autoClosed, isTrue);
    });

    test('just before 10 PM the day is still open and counting', () {
      final s = at([inAt(14, 0)], ist(21, 59));
      expect(s.state, DayState.working);
      expect(s.dayOver, isFalse);
    });

    test('at 10 PM sharp the day closes by itself', () {
      final s = at([inAt(14, 0)], ist(22, 0));
      expect(s.state, DayState.done);
      expect(s.dayOver, isTrue);
    });

    test('a day that ended with a punch-out also closes at 10 PM (no Done needed)', () {
      final s = at([inAt(9, 0), outAt(13, 0)], ist(22, 30));
      expect(s.state, DayState.done);
      expect(s.closedBy, 'auto');
      expect(s.autoClosedAt, isNull); // nothing was open
      expect(s.total, const Duration(hours: 4));
      expect(s.result, DayResult.shortHours);
    });
  });

  group('validation', () {
    String? check(AttendanceType t, List<Punch> punches, DateTime now) =>
        AttendanceRules.validate(t, at(punches, now));

    test('punch in is allowed first thing and again after a punch out', () {
      expect(check(AttendanceType.checkIn, [], ist(9, 0)), isNull);
      expect(check(AttendanceType.checkIn, [inAt(9, 0), outAt(13, 0)], ist(14, 0)), isNull);
    });

    test('punch in twice in a row, or punch out first, is refused', () {
      expect(check(AttendanceType.checkIn, [inAt(9, 0)], ist(10, 0)), contains('already punched in'));
      expect(check(AttendanceType.checkOut, [], ist(10, 0)), contains('punch in'));
      expect(check(AttendanceType.checkOut, [inAt(9, 0), outAt(10, 0)], ist(11, 0)), contains('punch in'));
    });

    test('Done needs at least one punch; nothing is allowed after Done', () {
      expect(check(AttendanceType.done, [], ist(10, 0)), isNotNull);
      expect(check(AttendanceType.done, [inAt(9, 0)], ist(10, 0)), isNull);
      final after = [inAt(9, 0), outAt(10, 0), doneAt(10, 1)];
      expect(check(AttendanceType.checkIn, after, ist(11, 0)), contains('marked today as done'));
      expect(check(AttendanceType.done, after, ist(11, 0)), isNotNull);
    });

    test('after 10 PM no new punch in is allowed', () {
      expect(check(AttendanceType.checkIn, [], ist(22, 5)), contains('10:00 PM'));
    });
  });

  group('merge (server + local queue)', () {
    AttendanceEvent ev(String id, AttendanceType t, DateTime at, SyncStatus s) => AttendanceEvent(
        eventId: id, type: t, timestamp: at, latitude: 0, longitude: 0, workDate: date, status: s);

    test('an event on the server and in the local queue is counted once', () {
      final server = [
        AttendanceRecord(date: date, id: 'ATT-1', punches: [
          Punch(eventId: 'a', type: AttendanceType.checkIn, timestamp: ist(9, 0)),
        ]),
      ];
      final local = [
        ev('a', AttendanceType.checkIn, ist(9, 0), SyncStatus.synced),
        ev('b', AttendanceType.checkOut, ist(13, 0), SyncStatus.pending),
      ];
      final merged = mergeRecords(server, local).single;
      expect(merged.punches.map((x) => x.eventId), ['a', 'b']);
      expect(merged.hasPending, isTrue);
      expect(merged.id, 'ATT-1');
    });

    test('rejected events never join the day but get their own history item', () {
      final local = [
        ev('a', AttendanceType.checkIn, ist(9, 0), SyncStatus.synced),
        AttendanceEvent(
            eventId: 'x',
            type: AttendanceType.checkOut,
            timestamp: ist(10, 0),
            latitude: 0,
            longitude: 0,
            workDate: date,
            status: SyncStatus.rejected,
            rejectReason: 'nope'),
      ];
      expect(mergeRecords([], local).single.punches.length, 1);
      final history = buildHistory([], local);
      expect(history.where((h) => h.status == SyncStatus.rejected).single.reason, 'nope');
    });
  });
}
