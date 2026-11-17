import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../controllers/attendance_controller.dart';
import '../controllers/leave_controller.dart';
import '../controllers/settings_controller.dart';
import '../models/models.dart';
import 'format.dart';
import 'leave_approvals_sheet.dart';
import 'profile_sheets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Profile & Reviewer Simulator tab: tools reviewers use to test the app.
class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.onOpenQueue});

  /// Switches to the Attendance tab filtered on Pending Sync.
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AttendanceController>();
    final s = context.watch<SettingsController>();
    final l = context.watch<LeaveController>();
    final emp = a.employee;
    final office = a.office;
    final pendingLeave = l.requests.where((r) => r.status == LeaveStatus.pending).length;

    return Scaffold(
      body: Column(children: [
        PageHeader(
          title: emp?.name ?? 'Profile',
          subtitle: emp == null ? 'Not loaded' : '${emp.id}  •  ${emp.department}',
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            child: Text(
              initialsOf(emp?.name ?? ''),
              style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        Expanded(
          child: ResponsiveBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const _Group('Location and server'),
                _ToolTile(
                  icon: Icons.location_on_outlined,
                  color: brandBlue,
                  title: 'Office Geofence',
                  status: office == null ? 'Not loaded' : 'Within ${office.radiusMeters.round()} m',
                  badge: s.hasOfficeOverride ? const Pill('Custom', warnAmber) : null,
                  onTap: office == null ? null : () => showOfficeSheet(context),
                ),
                _ToolTile(
                  icon: Icons.satellite_alt_outlined,
                  color: const Color(0xFF0E9AA7),
                  title: 'Location Simulator',
                  status: s.gpsEnabled
                      ? 'Mock GPS on · ${s.gpsLat.toStringAsFixed(4)}, ${s.gpsLng.toStringAsFixed(4)}'
                      : 'Real GPS',
                  badge: s.gpsEnabled ? const Pill('Mock', Color(0xFF0E9AA7)) : null,
                  onTap: () => showLocationSheet(context),
                ),
                _ToolTile(
                  icon: Icons.api_rounded,
                  color: const Color(0xFF7A4DE8),
                  title: 'Mock API Scenario',
                  status: _scenarioName(s.scenario),
                  badge: s.scenario == 'normal'
                      ? const Pill('Normal', successGreen)
                      : Pill(s.scenario.endsWith(_once) ? 'Once' : 'Active', warnAmber),
                  onTap: () => showScenarioSheet(context),
                ),
                const _Group('Sync and leave'),
                _ToolTile(
                  icon: Icons.sync_alt_rounded,
                  color: warnAmber,
                  title: 'Offline Sync Queue',
                  status: '${a.pendingCount} Pending',
                  badge: a.pendingCount > 0
                      ? const Pill('Waiting', warnAmber)
                      : const Pill('All synced', successGreen),
                  onTap: () {
                    a.setFilter(HistoryFilter.pending);
                    onOpenQueue();
                  },
                ),
                _ToolTile(
                  icon: Icons.fact_check_outlined,
                  color: successGreen,
                  title: 'Leave Approvals',
                  status: '$pendingLeave Pending',
                  badge: pendingLeave > 0 ? const Pill('Review', warnAmber) : null,
                  onTap: () => showLeaveApprovals(context),
                ),
                const _Group('Preferences'),
                _ToolTile(
                  icon: Icons.palette_outlined,
                  color: const Color(0xFF5B6B8C),
                  title: 'Appearance',
                  status: switch (s.themeMode) {
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                    ThemeMode.system => 'Follows the phone',
                  },
                  onTap: () => showThemeSheet(context),
                ),
                const SizedBox(height: 8),
                const _ServerCard(),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

const _once = ' (next request)';

/// duplicate_conflict (next request) -> duplicate conflict.
String _scenarioName(String scenario) =>
    scenario == 'normal' ? '200 OK' : scenario.replaceAll(_once, '').replaceAll('_', ' ');

/// Small caption above a group of tiles.
class _Group extends StatelessWidget {
  const _Group(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 0, 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: Theme.of(context).hintColor,
            )),
      );
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.status,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String status;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                IconTile(icon, color, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                  ]),
                ),
                if (badge != null) ...[const SizedBox(width: 8), badge!],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ]),
            ),
          ),
        ),
      );
}

/// Shows which server the app talks to (handy when a phone cannot connect).
class _ServerCard extends StatelessWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: brandBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.dns_outlined, color: brandBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mock server', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              SelectableText(apiBaseUrl, style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
            ]),
          ),
        ]),
      );
}
