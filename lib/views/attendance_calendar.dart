import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/attendance_controller.dart';
import '../models/calendar.dart';
import '../models/models.dart';
import 'attendance_detail.dart';
import 'format.dart';
import 'leave_detail.dart';
import 'theme.dart';
import 'widgets.dart';

/// Colours and the one-letter label of each kind of day.
({Color color, double bg, String label}) _style(DayMark m) => switch (m) {
      DayMark.present => (color: successGreen, bg: 0.14, label: 'P'),
      DayMark.shortHours => (color: dangerRed, bg: 0.14, label: 'L'),
      DayMark.onLeave => (color: dangerRed, bg: 0.14, label: 'L'),
      DayMark.absent => (color: dangerRed, bg: 0.14, label: 'A'),
      DayMark.weeklyOff => (color: dangerRed, bg: 0.05, label: 'Off'),
      DayMark.pendingLeave => (color: warnAmber, bg: 0.16, label: 'L?'),
      DayMark.inProgress => (color: brandBlue, bg: 0.14, label: 'In'),
      DayMark.none => (color: Colors.grey, bg: 0.0, label: ''),
    };

/// Monthly attendance at a glance: green = present, red = leave / short hours /
/// absent, light red = weekly off, amber = leave waiting for approval.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({
    super.key,
    required this.c,
    required this.days,
    required this.timezone,
  });
  final AttendanceController c;
  final List<CalendarDay> days;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final month = c.shownMonth;
    final y = int.parse(month.substring(0, 4));
    final m = int.parse(month.substring(5, 7));
    final lead = DateTime.utc(y, m, 1).weekday % 7; // Sunday = 0
    final cells = <CalendarDay?>[...List.filled(lead, null), ...days];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final hint = Theme.of(context).hintColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: c.canGoPrev ? () => c.shiftCalendar(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Center(
                child: Text(DateFormat('MMMM yyyy').format(DateTime(y, m)),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: c.canGoNext ? () => c.shiftCalendar(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          Row(children: [
            for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(color: hint, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          for (var r = 0; r < cells.length; r += 7)
            Row(children: [
              for (var i = r; i < r + 7; i++)
                Expanded(
                  child: cells[i] == null
                      ? const SizedBox(height: 52)
                      : _Cell(
                          day: cells[i]!,
                          isToday: cells[i]!.date == c.workDate,
                          onTap: () => _open(context, cells[i]!),
                        ),
                ),
            ]),
          const SizedBox(height: 12),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              _Legend('Present', successGreen),
              _Legend('Leave / short hours', dangerRed),
              _Legend('Weekly off', Color(0xFFE9A9A4)),
              _Legend('Leave pending', warnAmber),
            ],
          ),
        ]),
      ),
    );
  }

  /// Tap a day: attendance and leave open their detail sheets.
  void _open(BuildContext context, CalendarDay d) {
    final rec = d.record;
    if (rec != null && d.summary != null) {
      showAttendanceDetail(
        context,
        HistoryItem(
          date: rec.date,
          id: rec.id,
          punches: rec.punches,
          status: rec.hasPending ? SyncStatus.pending : SyncStatus.synced,
        ),
        d.summary!,
        timezone,
      );
    } else if (d.leave != null) {
      showLeaveDetail(context, d.leave!);
    } else if (d.mark == DayMark.weeklyOff || d.mark == DayMark.absent) {
      final off = d.mark == DayMark.weeklyOff;
      showDetailSheet(
        context,
        (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmtLongDate(d.date),
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Pill(off ? 'Weekly off' : 'Absent', dangerRed),
          const SizedBox(height: 12),
          Text(off
              ? 'Saturday and Sunday are weekly offs. No attendance is needed.'
              : 'No punches were recorded and no leave was approved for this day. '
                  'It is treated as leave.'),
        ]),
      );
    }
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.isToday, required this.onTap});
  final CalendarDay day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = _style(day.mark);
    final tappable = day.mark != DayMark.none;
    final numberColor = day.mark == DayMark.none ? null : s.color;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: s.color.withValues(alpha: s.bg),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tappable ? onTap : null,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isToday ? Border.all(color: brandBlue, width: 2) : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${day.day}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: day.mark == DayMark.weeklyOff
                          ? dangerRed.withValues(alpha: 0.7)
                          : numberColor)),
              if (s.label.isNotEmpty)
                Text(s.label,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: day.mark == DayMark.weeklyOff
                            ? dangerRed.withValues(alpha: 0.6)
                            : s.color)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ]);
}
