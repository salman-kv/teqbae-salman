import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart';
import '../controllers/leave_controller.dart';
import '../models/models.dart';
import '../models/rules.dart';
import 'format.dart';
import 'leave_detail.dart';
import 'theme.dart';
import 'widgets.dart';

/// Reviewer tool: approve or reject Pending leave requests (stands in for a
/// manager; the mock server applies the decision).
Future<void> showLeaveApprovals(BuildContext context) {
  final leave = context.read<LeaveController>();
  final attendance = context.read<AttendanceController>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => ChangeNotifierProvider.value(
      value: leave,
      // The Home leave balance changes with a decision, so reload it too.
      child: _ApprovalsSheet(onDecided: () => attendance.load(silent: true)),
    ),
  );
}

class _ApprovalsSheet extends StatefulWidget {
  const _ApprovalsSheet({required this.onDecided});
  final VoidCallback onDecided;

  @override
  State<_ApprovalsSheet> createState() => _ApprovalsSheetState();
}

class _ApprovalsSheetState extends State<_ApprovalsSheet> {
  String? _busyId;
  String? _note;
  bool _noteIsError = false;

  Future<void> _decide(LeaveRequest r, bool approve) async {
    final c = context.read<LeaveController>();
    setState(() {
      _busyId = r.id;
      _note = null;
    });
    final err = await c.review(r, approve: approve);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      _noteIsError = err != null;
      _note = err ?? 'Request ${r.id} ${approve ? 'approved' : 'rejected'}.';
    });
    if (err == null) widget.onDecided();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LeaveController>();
    final pending = c.requests.where((r) => r.status == LeaveStatus.pending).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconTile(Icons.fact_check_outlined, successGreen, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Leave approvals',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                'Reviewer tool. A manager would do this in a real system. '
                'The mock server applies the decision.',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ]),
          ),
        ]),
        if (_note != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_noteIsError ? dangerRed : successGreen).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_note!,
                style: TextStyle(
                    color: _noteIsError ? dangerRed : successGreen, fontWeight: FontWeight.w700)),
          ),
        ],
        const SizedBox(height: 14),
        if (pending.isEmpty)
          const EmptyView('No pending requests.\nApply for leave first, then come back here.')
        else
          for (final r in pending) ...[
            _PendingCard(
              request: r,
              busy: _busyId == r.id,
              onApprove: _busyId == null ? () => _decide(r, true) : null,
              onReject: _busyId == null ? () => _decide(r, false) : null,
            ),
            const SizedBox(height: 12),
          ],
      ]),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });
  final LeaveRequest request;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final days = leaveDayCount(r.startDate, r.endDate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconTile(leaveTypeIcon(r.type), leaveTypeColor(r.type)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.type.label} Leave • $days day${days == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(r.startDate == r.endDate
                    ? fmtDmy(r.startDate)
                    : '${fmtDmy(r.startDate)} - ${fmtDmy(r.endDate)}'),
                Text(r.reason, style: Theme.of(context).textTheme.bodySmall),
                Text(r.id, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (busy)
            const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6)))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: dangerRed,
                    side: const BorderSide(color: dangerRed),
                  ),
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: successGreen,
                  ),
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text('Approve'),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}
