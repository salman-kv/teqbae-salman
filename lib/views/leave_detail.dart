import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/rules.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

Color leaveTypeColor(LeaveType t) => t == LeaveType.casual ? successGreen : dangerRed;

IconData leaveTypeIcon(LeaveType t) =>
    t == LeaveType.casual ? Icons.beach_access : Icons.medical_services_outlined;

/// Full details of one leave request (opened by tapping a request card).
void showLeaveDetail(BuildContext context, LeaveRequest r) {
  final days = leaveDayCount(r.startDate, r.endDate);
  final (color, note) = switch (r.status) {
    LeaveStatus.pending => (warnAmber, 'Waiting for approval. These days are reserved from your balance.'),
    LeaveStatus.approved => (successGreen, 'Approved. The days were deducted from your balance.'),
    LeaveStatus.rejected => (dangerRed, 'Rejected. The days were returned to your balance.'),
  };

  showDetailSheet(context, (ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconTile(leaveTypeIcon(r.type), leaveTypeColor(r.type), size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.type.label} Leave',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('$days day${days == 1 ? '' : 's'}',
                style: TextStyle(color: Theme.of(ctx).hintColor)),
          ]),
        ),
        LeaveStatusChip(r.status),
      ]),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(note, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 10),
      DetailRow('Request ID', r.id),
      const Divider(height: 1),
      DetailRow('From', fmtLongDate(r.startDate)),
      const Divider(height: 1),
      DetailRow('To', fmtLongDate(r.endDate)),
      const Divider(height: 1),
      DetailRow('Duration', '$days calendar day${days == 1 ? '' : 's'}'),
      const Divider(height: 1),
      DetailRow('Reason', r.reason),
    ]);
  });
}
