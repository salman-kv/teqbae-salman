import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart';
import '../controllers/leave_controller.dart';
import '../models/models.dart';
import '../models/rules.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showLeaveSheet(BuildContext context) async {
  final controller = context.read<LeaveController>();
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => ChangeNotifierProvider.value(value: controller, child: const LeaveFormSheet()),
  );
  if (submitted == true && context.mounted) {
    showMessage(context, 'Leave request submitted.');
    // The Home tab shows the balance too: refresh it.
    context.read<AttendanceController>().load(silent: true);
  }
}

/// "Apply for Leave" bottom sheet. Local state = what the user typed.
class LeaveFormSheet extends StatefulWidget {
  const LeaveFormSheet({super.key});

  @override
  State<LeaveFormSheet> createState() => _LeaveFormSheetState();
}

class _LeaveFormSheetState extends State<LeaveFormSheet> {
  LeaveType _type = LeaveType.casual;
  String? _start;
  String? _end;
  final _reason = TextEditingController();
  Map<String, String> _errors = {};
  String? _banner;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        _type = LeaveType.casual;
        _start = _end = null;
        _reason.clear();
        _errors = {};
        _banner = null;
      });

  Future<void> _pick(bool isStart) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse((isStart ? _start : _end) ?? '') ??
        (isStart ? null : DateTime.tryParse(_start ?? '')) ??
        now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    setState(() {
      isStart ? _start = fmtDate(d) : _end = fmtDate(d);
      // Changing a date makes the old date errors (and the red banner) stale.
      _errors = {..._errors}..removeWhere((k, _) => k == 'startDate' || k == 'endDate');
      _banner = null;
    });
  }

  Future<void> _submit() async {
    final c = context.read<LeaveController>();
    final result = await c.submit(LeaveDraft(
      type: _type,
      startDate: _start,
      endDate: _end,
      reason: _reason.text,
    ));
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errors = result.fieldErrors;
        _banner = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LeaveController>();
    final bal = c.balance;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 16),
          Text('Apply for Leave', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          for (final t in LeaveType.values) ...[
            _TypeOption(
              label: '${t.label} Leave (${bal?.of(t) ?? '-'} days left)',
              selected: _type == t,
              onTap: () => setState(() => _type = t),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 6),
          const Text('Leave Period', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          _DateField(label: 'Start Date', value: _start, error: _errors['startDate'], onTap: () => _pick(true)),
          const SizedBox(height: 10),
          _DateField(label: 'End Date', value: _end, error: _errors['endDate'], onTap: () => _pick(false)),
          if (_start != null && _end != null && _end!.compareTo(_start!) >= 0)
            _DaysSummary(
              days: leaveDayCount(_start!, _end!),
              available: bal?.of(_type),
            ),
          const SizedBox(height: 16),
          const Text('Provide Reason', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            onChanged: (_) {
              if (_errors.containsKey('reason')) setState(() => _errors = {..._errors}..remove('reason'));
            },
            minLines: 3,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Enter reason (at least 10 characters)',
              errorText: _errors['reason'],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          if (_banner != null) ...[
            const SizedBox(height: 12),
            Text(_banner!, style: const TextStyle(color: Color(0xFFD93025), fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 58)),
                onPressed: c.submitting ? null : _clear,
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: GradientButton(
                label: 'Submit Request',
                icon: Icons.send_rounded,
                loading: c.submitting,
                onPressed: _submit,
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// "2 days requested · 8 available" (turns red when over the balance).
class _DaysSummary extends StatelessWidget {
  const _DaysSummary({required this.days, required this.available});
  final int days;
  final int? available;

  @override
  Widget build(BuildContext context) {
    final over = available != null && days > available!;
    final color = over ? const Color(0xFFD93025) : brandBlue;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(over ? Icons.warning_amber_rounded : Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$days day${days == 1 ? '' : 's'} requested'
              '${available == null ? '' : ' · $available available'}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? brandBlue.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? brandBlue : Colors.grey.shade400, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? brandBlue : Colors.grey),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          ]),
        ),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.error});
  final String label;
  final String? value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: error != null ? const Color(0xFFD93025) : Colors.grey.shade400),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_month_outlined),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
              Text(fmtDmy(value),
                  style: TextStyle(color: value == null ? Colors.grey : null, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4),
            child: Text(error!, style: const TextStyle(color: Color(0xFFD93025), fontSize: 12)),
          ),
      ]);
}
