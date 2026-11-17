import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart' show LoadStatus;
import '../controllers/leave_controller.dart';
import '../models/models.dart';
import 'format.dart';
import 'leave_detail.dart';
import 'leave_form_sheet.dart';
import 'widgets.dart';

/// Leaves tab: balances + my requests. "Apply" opens the bottom sheet.
class LeaveView extends StatelessWidget {
  const LeaveView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LeaveController>();

    Widget body;
    switch (c.status) {
      case LoadStatus.loading:
        body = const Center(child: CircularProgressIndicator());
      case LoadStatus.error:
        body = ErrorView(message: c.error ?? 'Could not load leave data.', onRetry: c.load);
      case LoadStatus.ready:
        body = RefreshIndicator(
          onRefresh: () => c.load(silent: true),
          child: ResponsiveBody(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                if (c.fromCache) ...[
                  const OfflineBanner('Offline. Showing previously loaded requests.'),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Expanded(child: _Balance('Casual', c.balance!.casual, const Color(0xFF1E9E4A))),
                  const SizedBox(width: 14),
                  Expanded(child: _Balance('Sick', c.balance!.sick, const Color(0xFFD93025))),
                ]),
                const SizedBox(height: 20),
                const SectionTitle('My leave requests'),
                const SizedBox(height: 6),
                if (c.requests.isEmpty)
                  const EmptyView('No leave requests yet.')
                else
                  for (final r in c.requests.reversed) ...[_RequestCard(r), const SizedBox(height: 10)],
              ],
            ),
          ),
        );
    }

    final pending = c.requests.where((r) => r.status == LeaveStatus.pending).length;
    return Scaffold(
      body: Column(children: [
        PageHeader(
          title: 'Leaves',
          subtitle: c.status == LoadStatus.ready
              ? (pending > 0 ? '$pending request${pending == 1 ? '' : 's'} awaiting approval' : 'Balances and requests')
              : 'Balances and requests',
          trailing: const Icon(Icons.event_note_rounded, color: Colors.white70, size: 30),
        ),
        Expanded(child: body),
        if (c.status == LoadStatus.ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: ResponsiveBody(
              child: GradientButton(
                label: 'Apply for Leave',
                icon: Icons.add_rounded,
                onPressed: () => showLeaveSheet(context),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance(this.label, this.days, this.color);
  final String label;
  final int days;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(Icons.event_available, color, size: 44),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label balance', style: const TextStyle(fontSize: 12)),
              Text('$days Days', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
          ]),
        ),
      );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(this.r);
  final LeaveRequest r;

  @override
  Widget build(BuildContext context) {
    final days = leaveDays(r);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
       onTap: () => showLeaveDetail(context, r),
       child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          IconTile(leaveTypeIcon(r.type), leaveTypeColor(r.type)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.type.label} Leave • $days day${days == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(r.startDate == r.endDate
                  ? fmtDmy(r.startDate)
                  : '${fmtDmy(r.startDate)} - ${fmtDmy(r.endDate)}'),
              Text(r.reason, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          LeaveStatusChip(r.status),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
       ),
      ),
    );
  }

  int leaveDays(LeaveRequest r) =>
      DateTime.parse(r.endDate).difference(DateTime.parse(r.startDate)).inDays + 1;
}
