import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../controllers/attendance_controller.dart';
import '../models/models.dart';
import '../models/rules.dart';
import 'attendance_detail.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Home / dashboard tab. Only shows what the controller holds.
class HomeView extends StatelessWidget {
  const HomeView({super.key, this.onViewAll});

  /// Switches to the Attendance tab ("View all").
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AttendanceController>();
    return Scaffold(
      body: switch (c.status) {
        LoadStatus.loading => const SafeArea(child: Center(child: CircularProgressIndicator())),
        LoadStatus.error => SafeArea(
            child: ErrorView(
              message: c.error ?? 'Something went wrong.',
              offline: c.errorOffline,
              onRetry: c.load,
            ),
          ),
        LoadStatus.ready => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: _HomeBody(c: c, onViewAll: onViewAll),
          ),
      },
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.c, this.onViewAll});
  final AttendanceController c;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final tzName = c.employee!.office.timezone;
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _Hero(c: c, timezone: tzName),
          ResponsiveBody(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _TodayPunches(c: c, timezone: tzName),
                const SectionTitle('Leave balance'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _LeaveTile(
                      label: 'Casual leave',
                      days: c.balance?.casual,
                      icon: Icons.beach_access,
                      color: successGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LeaveTile(
                      label: 'Sick leave',
                      days: c.balance?.sick,
                      icon: Icons.medical_services_outlined,
                      color: dangerRed,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SectionTitle('Recent attendance',
                    actionLabel: onViewAll == null ? null : 'View all', onAction: onViewAll),
                const SizedBox(height: 4),
                if (c.recent.isEmpty)
                  const EmptyView('No attendance records yet.\nPunch in to create your first one.')
                else
                  for (final item in c.recent) ...[
                    AttendanceCard(item: item, summary: c.summaryOfItem(item), timezone: tzName),
                    const SizedBox(height: 10),
                  ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ hero ----

/// Gradient top section: greeting, employee, connection state, worked-time ring
/// and the Check In / Check Out button.
class _Hero extends StatelessWidget {
  const _Hero({required this.c, required this.timezone});
  final AttendanceController c;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final emp = c.employee!;
    final now = tz.TZDateTime.now(tz.getLocation(timezone));
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final today = c.today;
    final summary = c.todaySummary;
    // Short screens (small phones): keep the Check In button above the fold.
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 26),
      child: ResponsiveBody(
        child: Column(children: [
          // Row 1: avatar, greeting + name, refresh/sync button
          Row(children: [
            _Avatar(emp.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greeting, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                Text(emp.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ]),
            ),
            _SyncButton(c: c),
          ]),
          const SizedBox(height: 14),
          // Row 2: ID, department, date
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _Chip(Icons.badge_outlined, emp.id),
              _Chip(Icons.apartment_rounded, emp.department),
              if (!compact) _Chip(Icons.calendar_today_rounded, DateFormat('EEE, d MMM').format(now)),
            ]),
          ),
          const SizedBox(height: 10),
          _ConnectionBadge(c: c, timezone: timezone),
          const SizedBox(height: 16),
          // Today's status
          _StatusPill(summary),
          const SizedBox(height: 14),
          LiveClock(summary: () => c.todaySummary, size: compact ? 112 : 150),
          const SizedBox(height: 8),
          _DayHint(summary),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _TimeTile(
                  icon: Icons.login_rounded,
                  label: 'First punch-in',
                  value: fmtTime(summary.firstIn, timezone)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeTile(
                  icon: Icons.logout_rounded,
                  label: 'Last punch-out',
                  value: fmtTime(summary.sessions.isEmpty ? null : summary.sessions.last.outAt, timezone)),
            ),
          ]),
          if (today?.hasPending ?? false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9B8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule, size: 16, color: Color(0xFF8A5A00)),
                SizedBox(width: 6),
                Text('Pending Sync',
                    style: TextStyle(
                        color: Color(0xFF8A5A00), fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          _Actions(c: c, summary: summary),
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(name);
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Text(initials,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Refresh + sync in one button. A badge shows how many events are pending.
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.c});
  final AttendanceController c;

  @override
  Widget build(BuildContext context) {
    final busy = c.syncing;
    return Badge(
      isLabelVisible: c.pendingCount > 0,
      label: Text('${c.pendingCount}'),
      backgroundColor: const Color(0xFFFFB020),
      textColor: Colors.black87,
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'Refresh and sync',
          onPressed: busy ? null : c.syncNow,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Icon(Icons.sync_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

/// Online / offline state, always visible in the hero.
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.c, required this.timezone});
  final AttendanceController c;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final offline = c.fromCache;
    final String text;
    if (offline) {
      final at = c.lastUpdated == null ? '' : ' from ${fmtTime(c.lastUpdated, timezone)}';
      text = 'Offline or server unavailable. Showing saved data$at.';
    } else if (c.pendingCount > 0) {
      text = 'Online · ${c.pendingCount} event${c.pendingCount == 1 ? '' : 's'} waiting to sync';
    } else {
      text = 'Online · everything is synced';
    }
    final color = offline
        ? const Color(0xFFFFE9B8)
        : c.pendingCount > 0
            ? const Color(0xFFFFE9B8)
            : Colors.white.withValues(alpha: 0.16);
    final fg = offline || c.pendingCount > 0 ? const Color(0xFF8A5A00) : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(
          offline
              ? Icons.cloud_off_rounded
              : c.pendingCount > 0
                  ? Icons.cloud_sync_rounded
                  : Icons.cloud_done_rounded,
          size: 18,
          color: fg,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.summary);
  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final (label, dot) = switch (summary.state) {
      DayState.notStarted => ('Not Punched In', const Color(0xFFC9D4EA)),
      DayState.working => ('Working', const Color(0xFF5CE08A)),
      DayState.onBreak => ('Punched Out', const Color(0xFFFFD166)),
      DayState.done => (
          summary.closedBy == 'auto' ? 'Day Closed (10 PM)' : 'Day Done',
          const Color(0xFF9CC2FF)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

/// One line under the ring: time left to 8 h, or how the finished day counts.
class _DayHint extends StatelessWidget {
  const _DayHint(this.summary);
  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final String text;
    switch (summary.state) {
      case DayState.notStarted:
        text = 'Punch in to start your day';
      case DayState.working || DayState.onBreak:
        text = summary.total >= AttendanceRules.target
            ? 'Target reached. Mark done when you finish.'
            : '${fmtDuration(summary.remaining)} to go for a full day';
      case DayState.done:
        text = summary.result == DayResult.present
            ? 'Full day completed'
            : 'Short hours today · counts as leave';
    }
    return Text(text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600));
  }
}
class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      );
}

/// Main button (Punch In / Punch Out) plus "Done for today".
class _Actions extends StatelessWidget {
  const _Actions({required this.c, required this.summary});
  final AttendanceController c;
  final DaySummary summary;

  Future<void> _confirmDone(BuildContext context) async {
    final working = summary.state == DayState.working;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark today as done?'),
        content: Text(
          '${working ? 'You will be punched out now. ' : ''}'
          'Total so far: ${fmtDuration(summary.total)}. '
          'You will not be able to punch in again today.'
          '${summary.total < AttendanceRules.target ? '\n\nLess than 8h counts as leave.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );
    if (ok == true) await c.markDone();
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap;
    final String text;
    final IconData icon;
    switch (summary.state) {
      case DayState.notStarted || DayState.onBreak:
        text = 'Punch In';
        icon = Icons.login_rounded;
        onTap = c.busy ? null : c.checkIn;
      case DayState.working:
        text = 'Punch Out';
        icon = Icons.logout_rounded;
        onTap = c.busy ? null : c.checkOut;
      case DayState.done:
        text = 'Day completed';
        icon = Icons.check_circle_rounded;
        onTap = null;
    }
    final canFinish = summary.state == DayState.working || summary.state == DayState.onBreak;
    return Column(children: [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: brandBlue,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
        ),
        onPressed: onTap,
        child: c.busy
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: brandBlue))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon),
                const SizedBox(width: 10),
                Text(text),
              ]),
      ),
      if (canFinish) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: c.busy ? null : () => _confirmDone(context),
          icon: const Icon(Icons.task_alt_rounded, size: 20),
          label: const Text('Done for today'),
        ),
      ],
    ]);
  }
}

/// Today's punches as sessions (only when there is something to show).
class _TodayPunches extends StatelessWidget {
  const _TodayPunches({required this.c, required this.timezone});
  final AttendanceController c;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final s = c.todaySummary;
    if (s.sessions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle("Today's punches"),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(children: [
              for (var i = 0; i < s.sessions.length; i++)
                SessionRow(index: i + 1, session: s.sessions[i], timezone: timezone, now: DateTime.now()),
              const Divider(height: 18),
              Row(children: [
                const Expanded(
                    child: Text('Total today', style: TextStyle(fontWeight: FontWeight.w600))),
                Text(fmtDuration(s.total),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// HH:MM:SS of total time worked today (all sessions) inside a progress ring
/// (target: 8 h). Ticks every second while punched in.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key, required this.summary, this.size = 150});

  /// Recomputed on every tick, so the running session and the 10 PM auto-done
  /// are always up to date.
  final DaySummary Function() summary;
  final double size;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _timer;
  late DayState _lastState = widget.summary().state;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = widget.summary();
      if (s.state != _lastState) {
        // e.g. the 10 PM auto-done just happened: let the whole screen update.
        _lastState = s.state;
        context.read<AttendanceController>().refreshClock();
      } else if (s.isOpen) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.summary().total;
    final progress = (total.inSeconds / AttendanceRules.target.inSeconds).clamp(0.0, 1.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            strokeCap: StrokeCap.round,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('WORKED TODAY',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(fmtClock(total),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size < 130 ? 21 : 27,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (widget.size >= 130)
            Text('of 8h target',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ]),
      ]),
    );
  }
}
class _LeaveTile extends StatelessWidget {
  const _LeaveTile({required this.label, required this.days, required this.icon, required this.color});
  final String label;
  final int? days;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(icon, color, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: days == null ? '--' : '$days',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                  const TextSpan(text: ' days', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ])),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              ]),
            ),
          ]),
        ),
      );
}
