import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart';
import '../controllers/leave_controller.dart';
import '../models/calendar.dart';
import 'attendance_calendar.dart';
import 'attendance_detail.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Attendance History tab: filter chips, Sync Now, list of days / events.
class AttendanceView extends StatelessWidget {
  const AttendanceView({super.key});

  static const _filters = {
    HistoryFilter.all: 'All',
    HistoryFilter.synced: 'Synced',
    HistoryFilter.pending: 'Pending Sync',
    HistoryFilter.rejected: 'Rejected',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AttendanceController>();
    final tz = c.employee?.office.timezone;

    Widget body;
    if (c.status == LoadStatus.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (c.status == LoadStatus.error || tz == null) {
      body = ErrorView(message: c.error ?? 'Could not load attendance.', onRetry: c.load);
    } else {
      final items = c.history;
      final days = c.calendarDays(context.watch<LeaveController>().requests);
      body = RefreshIndicator(
        onRefresh: c.refresh,
        child: ResponsiveBody(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (c.fromCache) ...[
                const OfflineBanner('Offline. Showing saved attendance history.'),
                const SizedBox(height: 12),
              ],
              AttendanceCalendar(c: c, days: days, timezone: tz),
              const SizedBox(height: 12),
              _MonthCard(totalsOf(days)),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final e in _filters.entries) ...[
                    ChoiceChip(
                      label: Text(e.value),
                      selected: c.filter == e.key,
                      onSelected: (_) => c.setFilter(e.key),
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: c.syncing ? null : c.syncNow,
                  icon: c.syncing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(c.pendingCount > 0 ? 'Sync Now (${c.pendingCount})' : 'Sync Now'),
                ),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const EmptyView('Nothing here yet.')
              else
                for (final item in items) ...[
                  AttendanceCard(item: item, summary: c.summaryOfItem(item), timezone: tz),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(children: [
        PageHeader(
          title: 'Attendance History',
          subtitle: c.pendingCount > 0
              ? '${c.pendingCount} event${c.pendingCount == 1 ? '' : 's'} waiting to sync'
              : 'All events are synced',
          trailing: const Icon(Icons.history_rounded, color: Colors.white70, size: 30),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

/// Totals of the month shown in the calendar.
class _MonthCard extends StatelessWidget {
  const _MonthCard(this.stats);
  final MonthTotals stats;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(children: [
            _Cell('${stats.present}', 'Present days', successGreen),
            _Cell('${stats.leave}', 'Leave days\n(incl. short hours)', dangerRed),
            _Cell(stats.hours.inMinutes == 0 ? '0h 00m' : fmtDuration(stats.hours), 'Total hours', brandBlue),
          ]),
        ),
      );
}

class _Cell extends StatelessWidget {
  const _Cell(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
      );
}
