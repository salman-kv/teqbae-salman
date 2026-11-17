import 'models.dart';
import 'rules.dart';

/// How one calendar day is shown on the monthly attendance calendar.
enum DayMark {
  present, // worked a full day
  shortHours, // finished under 8 h: treated as leave
  onLeave, // approved leave request
  pendingLeave, // leave request waiting for approval
  weeklyOff, // Saturday / Sunday
  absent, // past weekday with no punches and no leave
  inProgress, // today, day not finished yet
  none, // future day, today before punching, or before the first record
}

class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.mark,
    this.record,
    this.summary,
    this.leave,
  });

  final String date; // yyyy-MM-dd
  final DayMark mark;
  final AttendanceRecord? record;
  final DaySummary? summary;
  final LeaveRequest? leave;

  int get day => int.parse(date.substring(8, 10));

  /// Counts as a leave day in the month totals (red on the calendar).
  bool get isLeave =>
      mark == DayMark.shortHours || mark == DayMark.onLeave || mark == DayMark.absent;
}

/// One entry per day of the month (1st to last).
///
/// Priority for a day: attendance record -> approved leave -> pending leave ->
/// weekend -> (future / before the first record: nothing) -> absent.
List<CalendarDay> buildMonth({
  required int year,
  required int month,
  required String today,
  required List<AttendanceRecord> records,
  required List<LeaveRequest> leaves,
  required DaySummary Function(AttendanceRecord) summarize,
}) {
  final byDate = {for (final r in records) r.date: r};
  String? first;
  for (final r in records) {
    if (first == null || r.date.compareTo(first) < 0) first = r.date;
  }

  LeaveRequest? leaveOn(String date) {
    LeaveRequest? pending;
    for (final l in leaves) {
      if (date.compareTo(l.startDate) < 0 || date.compareTo(l.endDate) > 0) continue;
      if (l.status == LeaveStatus.approved) return l;
      if (l.status == LeaveStatus.pending) pending = l;
    }
    return pending;
  }

  final count = DateTime.utc(year, month + 1, 0).day;
  final days = <CalendarDay>[];
  for (var d = 1; d <= count; d++) {
    final dt = DateTime.utc(year, month, d);
    final date = fmtDate(dt);
    final weekend = dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
    final rec = byDate[date];
    final leave = leaveOn(date);

    if (rec != null) {
      final s = summarize(rec);
      final mark = switch (s.result) {
        DayResult.present => DayMark.present,
        DayResult.shortHours => DayMark.shortHours,
        DayResult.inProgress => DayMark.inProgress,
      };
      days.add(CalendarDay(date: date, mark: mark, record: rec, summary: s, leave: leave));
    } else if (leave != null) {
      days.add(CalendarDay(
        date: date,
        mark: leave.status == LeaveStatus.approved ? DayMark.onLeave : DayMark.pendingLeave,
        leave: leave,
      ));
    } else if (weekend) {
      days.add(CalendarDay(date: date, mark: DayMark.weeklyOff));
    } else if (date.compareTo(today) >= 0 || first == null || date.compareTo(first) < 0) {
      days.add(CalendarDay(date: date, mark: DayMark.none));
    } else {
      days.add(CalendarDay(date: date, mark: DayMark.absent));
    }
  }
  return days;
}

/// Totals shown under the calendar.
class MonthTotals {
  const MonthTotals({required this.present, required this.leave, required this.hours});
  final int present;
  final int leave; // short hours + approved leave + absent (weekends not counted)
  final Duration hours;
}

MonthTotals totalsOf(List<CalendarDay> days) {
  var present = 0, leave = 0;
  var hours = Duration.zero;
  for (final d in days) {
    if (d.mark == DayMark.present) present++;
    if (d.isLeave) leave++;
    hours += d.summary?.total ?? Duration.zero;
  }
  return MonthTotals(present: present, leave: leave, hours: hours);
}
