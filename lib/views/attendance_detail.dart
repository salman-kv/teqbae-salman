import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/rules.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

Color resultColor(DayResult r) => switch (r) {
      DayResult.present => successGreen,
      DayResult.shortHours => warnAmber,
      DayResult.inProgress => brandBlue,
    };

String resultLabel(DayResult r) => switch (r) {
      DayResult.present => 'Present',
      DayResult.shortHours => 'Short hours · Leave',
      DayResult.inProgress => 'In progress',
    };

/// One day in the history list (Home "Recent attendance" and the Attendance tab).
/// Tap it to open the full punch-by-punch details.
class AttendanceCard extends StatelessWidget {
  const AttendanceCard({
    super.key,
    required this.item,
    required this.summary,
    required this.timezone,
  });
  final HistoryItem item;
  final DaySummary summary;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final rejected = item.status == SyncStatus.rejected;
    final color = rejected ? dangerRed : resultColor(summary.result);
    final end = summary.sessions.isEmpty ? null : summary.sessions.last.outAt;
    final sessions = summary.sessions.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAttendanceDetail(context, item, summary, timezone),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(
              rejected
                  ? Icons.event_busy
                  : switch (summary.result) {
                      DayResult.present => Icons.event_available,
                      DayResult.shortHours => Icons.hourglass_bottom_rounded,
                      DayResult.inProgress => Icons.timelapse_rounded,
                    },
              color,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtDayLabel(item.date),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                if (rejected)
                  Text('${item.punches.first.type.label} · ${fmtTime(item.punches.first.timestamp, timezone)}',
                      style: Theme.of(context).textTheme.bodySmall)
                else
                  Text('${fmtTime(summary.firstIn, timezone)} - ${fmtTime(end, timezone)}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                if (rejected)
                  Text(item.reason ?? 'Rejected by the server',
                      style: const TextStyle(color: dangerRed, fontSize: 12))
                else
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Pill(resultLabel(summary.result), color),
                    Text('$sessions session${sessions == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              SyncChip(item.status),
              if (!rejected) ...[
                const SizedBox(height: 8),
                Text(fmtDuration(summary.total),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ]),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}

/// Full details of one day: total, every session, how the day ended.
void showAttendanceDetail(
  BuildContext context,
  HistoryItem item,
  DaySummary s,
  String timezone,
) {
  showDetailSheet(context, (ctx) {
    final rejected = item.status == SyncStatus.rejected;
    final color = rejected ? dangerRed : resultColor(s.result);
    final progress = (s.total.inSeconds / AttendanceRules.target.inSeconds).clamp(0.0, 1.0);
    final short = AttendanceRules.target - s.total;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(fmtLongDate(item.date),
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        SyncChip(item.status),
      ]),
      const SizedBox(height: 4),
      if (item.id != null)
        Text('Record #${item.id}', style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 13)),
      const SizedBox(height: 16),
      if (rejected) ...[
        _Note(
          icon: Icons.error_outline,
          color: dangerRed,
          text: 'This ${item.punches.first.type.label} at ${fmtTime(item.punches.first.timestamp, timezone)} '
              'was rejected: ${item.reason ?? 'refused by the server'}',
        ),
      ] else ...[
        // Total worked + progress to the 8 h target
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(fmtDuration(s.total),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color)),
              ),
              Pill(resultLabel(s.result), color),
            ]),
            const SizedBox(height: 4),
            Text('Total worked · target ${AttendanceRules.target.inHours}h',
                style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12.5)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.18),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat('First in', fmtTime(s.firstIn, timezone))),
          const SizedBox(width: 10),
          Expanded(
              child: _Stat('Last out',
                  fmtTime(s.sessions.isEmpty ? null : s.sessions.last.outAt, timezone))),
          const SizedBox(width: 10),
          Expanded(child: _Stat('Sessions', '${s.sessions.length}')),
        ]),
        const SizedBox(height: 18),
        const Text('Punch history', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        for (var i = 0; i < s.sessions.length; i++)
          SessionRow(index: i + 1, session: s.sessions[i], timezone: timezone, now: DateTime.now()),
        if (s.closedBy != null)
          _EndRow(
            icon: s.closedBy == 'manual' ? Icons.check_circle_rounded : Icons.nightlight_round,
            text: s.closedBy == 'manual'
                ? 'Day marked done at ${fmtTime(s.punches.where((p) => p.type == AttendanceType.done).first.timestamp, timezone)}'
                : s.autoClosedAt != null
                    ? 'Auto punch-out and day closed at ${fmtTime(s.autoClosedAt, timezone)}'
                    : 'Day closed automatically at ${AttendanceRules.autoDoneHour}:00',
          )
        else
          const _EndRow(
              icon: Icons.timelapse_rounded,
              text: 'Day still open. It closes automatically at 10:00 PM.'),
        const SizedBox(height: 14),
        switch (s.result) {
          DayResult.present =>
            const _Note(icon: Icons.check_circle_outline, color: successGreen, text: 'Full day completed.'),
          DayResult.shortHours => _Note(
              icon: Icons.info_outline,
              color: warnAmber,
              text: 'Worked ${fmtDuration(s.total)}, which is ${fmtDuration(short)} short of '
                  '${AttendanceRules.target.inHours}h. This day is treated as leave.'),
          DayResult.inProgress => const _Note(
              icon: Icons.info_outline,
              color: brandBlue,
              text: 'Less than 8h worked counts as leave once the day is done.'),
        },
        if (item.status == SyncStatus.pending) ...[
          const SizedBox(height: 10),
          const _Note(
              icon: Icons.schedule,
              color: warnAmber,
              text: 'Some punches are saved on this device and waiting to sync.'),
        ],
      ],
    ]);
  });
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
        ]),
      );
}

class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.index,
    required this.session,
    required this.timezone,
    required this.now,
  });
  final int index;
  final Session session;
  final String timezone;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final open = session.outAt == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: brandBlue.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Text('$index',
              style: const TextStyle(color: brandBlue, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.login_rounded, size: 15, color: successGreen),
              const SizedBox(width: 4),
              Text('Punch In  ${fmtTime(session.inAt, timezone)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Icon(session.autoClosed ? Icons.nightlight_round : Icons.logout_rounded,
                  size: 15, color: open ? Colors.grey : warnAmber),
              const SizedBox(width: 4),
              Text(
                open
                    ? 'Punch Out  still working'
                    : '${session.autoClosed ? 'Auto Out' : 'Punch Out'}  ${fmtTime(session.outAt, timezone)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ]),
          ]),
        ),
        Text(fmtDuration(session.duration(now)),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }
}

class _EndRow extends StatelessWidget {
  const _EndRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: Theme.of(context).hintColor),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).hintColor))),
        ]),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      );
}
