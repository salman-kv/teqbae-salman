import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'config.dart';
import 'controllers/attendance_controller.dart';
import 'controllers/leave_controller.dart';
import 'controllers/settings_controller.dart';
import 'services/api_service.dart';
import 'services/connectivity_service.dart';
import 'services/local_db.dart';
import 'services/location_service.dart';
import 'services/sync_service.dart';
import 'views/app_shell.dart';
import 'views/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // Services (talk to the outside world).
  final db = await LocalDb.open(p.join(await getDatabasesPath(), 'rebs_hrms.db'));
  final RebsApi api = DioRebsApi(baseUrl: apiBaseUrl);
  final sync = SyncService(api, db)..attachConnectivity(ConnectivityService().onlineChanges);

  // Controllers (app logic + state).
  final settings = SettingsController(db, api);
  await settings.load();
  final attendance = AttendanceController(
    api: api,
    db: db,
    location: GeolocatorLocationService(),
    sync: sync,
    settings: settings,
  );
  final leave = LeaveController(api, db);

  runApp(RebsApp(attendance: attendance, leave: leave, settings: settings));

  // Load after the first frame so the loading state is visible.
  unawaited(attendance.load().then((_) {
    sync.syncNow(); // flush events left pending by the previous session
    return leave.load();
  }));
}

class RebsApp extends StatelessWidget {
  const RebsApp({super.key, required this.attendance, required this.leave, required this.settings});
  final AttendanceController attendance;
  final LeaveController leave;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: attendance),
        ChangeNotifierProvider.value(value: leave),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) => MaterialApp(
          title: 'Teqbae HRMS',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: s.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
