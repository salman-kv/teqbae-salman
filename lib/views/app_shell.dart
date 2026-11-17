import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/attendance_controller.dart';
import '../controllers/leave_controller.dart';
import 'attendance_view.dart';
import 'home_view.dart';
import 'leave_view.dart';
import 'profile_view.dart';
import 'widgets.dart';

/// Bottom navigation: Home, Attendance, Leaves, Profile.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  late final AttendanceController _attendance;
  int _lastMessageId = 0;

  @override
  void initState() {
    super.initState();
    _attendance = context.read<AttendanceController>();
    _lastMessageId = _attendance.messageId;
    _attendance.addListener(_showNewMessage);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attendance.removeListener(_showNewMessage);
    super.dispose();
  }

  /// Coming back to the app: sync pending events and refresh the screens
  /// (also fixes a stale "today" after midnight).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _attendance.refresh();
    context.read<LeaveController>().load(silent: true);
  }

  /// Controller posts a message -> show it once as a SnackBar.
  void _showNewMessage() {
    if (_attendance.messageId == _lastMessageId) return;
    _lastMessageId = _attendance.messageId;
    showMessage(
      context,
      _attendance.message ?? '',
      action: _attendance.messageOpensSettings
          ? SnackBarAction(label: 'Settings', onPressed: _attendance.openAppSettings)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        HomeView(onViewAll: () => setState(() => _index = 1)),
        const AttendanceView(),
        const LeaveView(),
        ProfileView(onOpenQueue: () => setState(() => _index = 1)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.access_time),
              selectedIcon: Icon(Icons.access_time_filled),
              label: 'Attendance'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Leaves'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
