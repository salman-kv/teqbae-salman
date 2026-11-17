import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae_salman/models/calendar.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/models/rules.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'helpers.dart';

/// Calendar rules for November 2026 (company timezone Asia/Kolkata).
/// 1 Nov is a Sunday, so 7/8, 14/15, 21/22, 28/29 are weekends.
void main() {
  setUpAll(tz_data.initializeTimeZones);

  const tzName = 'Asia/Kolkata';
  // "Today" is Tuesday 17 Nov, 10:00 company time.
  final now = DateTime.utc(2026, 11, 17, 4, 30);

  DateTime ist(String date, int h, int m) =>
      DateTime.parse('${date}T00:00:00Z').add(Duration(hours: h, minutes: m)).subtract(const Duration(hours: 5, minutes: 30));

  /// A finished day: in at 09:00, out at [outH]:00, then Done.
  AttendanceRecord day(String date, int outH) => AttendanceRecord(date: date, punches: [
        Punch(eventId: '$date-a', type: AttendanceType.checkIn, timestamp: ist(date, 9, 0)),
        Punch(eventId: '$date-b', type: AttendanceType.checkOut, timestamp: ist(date, outH, 0)),
        Punch(eventId: '$date-c', type: AttendanceType.done, timestamp: ist(date, outH, 1)),
      ]);

  List<CalendarDay> build({
    List<AttendanceRecord>? records,
    List<LeaveRequest> leaves = const [],
  }) =>
      buildMonth(
        year: 2026,
        month: 11,
        today: '2026-11-17',
        records: records ??
            [
              day('2026-11-11', 18), // 9 h -> present
              day('2026-11-12', 14), // 5 h -> short hours
              day('2026-11-16', 17), // 8 h -> present
            ],
        leaves: leaves,
        summarize: (r) => AttendanceRules.summarize(r.date, r.punches, now, tzName),
      );

  DayMark mark(List<CalendarDay> days, int d) => days[d - 1].mark;

  test('the month has one entry per day', () {
    expect(build().length, 30);
    expect(build().first.date, '2026-11-01');
    expect(build().last.date, '2026-11-30');
  });

  test('attendance days are present, or short hours when under 8 h', () {
    final d = build();
    expect(mark(d, 11), DayMark.present);
    expect(mark(d, 12), DayMark.shortHours);
    expect(mark(d, 16), DayMark.present);
  });

  test('Saturdays and Sundays are weekly off', () {
    final d = build();
    for (final n in [14, 15, 28, 29]) {
      expect(mark(d, n), DayMark.weeklyOff, reason: 'Nov $n');
    }
  });

  test('a past weekday with no punches after the first record is absent', () {
    expect(mark(build(), 13), DayMark.absent); // Friday
  });

  test('days before the first record and future days are left blank', () {
    final d = build();
    expect(mark(d, 10), DayMark.none); // before the first record
    expect(mark(d, 17), DayMark.none); // today, not punched in yet
    expect(mark(d, 19), DayMark.none); // future
  });

  test('approved leave is red leave, pending leave is amber, even on a weekend', () {
    final d = build(leaves: const [
      LeaveRequest(
          id: 'LV-1',
          type: LeaveType.casual,
          startDate: '2026-11-20',
          endDate: '2026-11-21',
          reason: 'Family function',
          status: LeaveStatus.approved),
      LeaveRequest(
          id: 'LV-2',
          type: LeaveType.sick,
          startDate: '2026-11-24',
          endDate: '2026-11-24',
          reason: 'Dental surgery',
          status: LeaveStatus.pending),
      LeaveRequest(
          id: 'LV-3',
          type: LeaveType.casual,
          startDate: '2026-11-26',
          endDate: '2026-11-26',
          reason: 'Rejected one here',
          status: LeaveStatus.rejected),
    ]);
    expect(mark(d, 20), DayMark.onLeave);
    expect(mark(d, 21), DayMark.onLeave); // Saturday, but on approved leave
    expect(d[19].leave?.id, 'LV-1');
    expect(mark(d, 24), DayMark.pendingLeave);
    expect(mark(d, 26), DayMark.none); // rejected leave changes nothing
  });

  test('an attendance record wins over a leave request on the same day', () {
    final d = build(leaves: const [
      LeaveRequest(
          id: 'LV-9',
          type: LeaveType.casual,
          startDate: '2026-11-11',
          endDate: '2026-11-11',
          reason: 'Overlaps a worked day',
          status: LeaveStatus.approved),
    ]);
    expect(mark(d, 11), DayMark.present);
  });

  test('today is in progress while the day is still open', () {
    final open = AttendanceRecord(date: '2026-11-17', punches: [
      Punch(eventId: 'x', type: AttendanceType.checkIn, timestamp: ist('2026-11-17', 9, 30)),
    ]);
    final d = build(records: [day('2026-11-16', 17), open]);
    expect(mark(d, 17), DayMark.inProgress);
  });

  test('with no records at all nothing is marked absent', () {
    final d = build(records: const []);
    expect(d.where((x) => x.mark == DayMark.absent), isEmpty);
  });

  test('totals: present days, leave days (short + approved + absent), hours', () {
    final d = build(leaves: const [
      LeaveRequest(
          id: 'LV-1',
          type: LeaveType.casual,
          startDate: '2026-11-20',
          endDate: '2026-11-21',
          reason: 'Family function',
          status: LeaveStatus.approved),
    ]);
    final t = totalsOf(d);
    expect(t.present, 2);
    expect(t.leave, 4); // 12th short + 13th absent + 20th & 21st leave
    expect(t.hours, const Duration(hours: 9 + 5 + 8));
  });

  group('month navigation (controller)', () {
    test('only this month and last month can be shown', () async {
      final env = await Env.create();
      await env.attendance.load();

      expect(env.attendance.shownMonth, '2026-11');
      expect(env.attendance.canGoNext, isFalse);
      expect(env.attendance.canGoPrev, isTrue);

      env.attendance.shiftCalendar(-1);
      expect(env.attendance.shownMonth, '2026-10');
      expect(env.attendance.canGoPrev, isFalse);
      env.attendance.shiftCalendar(-1); // refused
      expect(env.attendance.shownMonth, '2026-10');

      env.attendance.shiftCalendar(1);
      expect(env.attendance.shownMonth, '2026-11');
      env.attendance.shiftCalendar(1); // refused
      expect(env.attendance.shownMonth, '2026-11');
      await env.dispose();
    });

    test('the controller marks a punched day and weekends for the shown month', () async {
      final env = await Env.create();
      await env.attendance.load();
      await env.attendance.perform(AttendanceType.checkIn);
      await env.attendance.load(silent: true);

      final days = env.attendance.calendarDays(const []);
      expect(days.length, 30);
      expect(days[15].mark, DayMark.inProgress); // 16 Nov 09:30 IST, working
      expect(days[14].mark, DayMark.weeklyOff); // Sunday 15 Nov
      await env.dispose();
    });
  });
}
