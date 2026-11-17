import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teqbae_salman/services/location_service.dart';
import 'package:teqbae_salman/views/profile_view.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'helpers.dart';

Widget _app(Env env) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: env.attendance),
        ChangeNotifierProvider.value(value: env.leave),
        ChangeNotifierProvider.value(value: env.settings),
      ],
      child: MaterialApp(home: ProfileView(onOpenQueue: () {})),
    );

Future<Env> _loadedEnv(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2600); // tall: the whole list is built
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final env = (await tester.runAsync(Env.create))!;
  await tester.runAsync(env.attendance.load);
  await tester.runAsync(env.leave.load);
  await tester.pumpWidget(_app(env));
  return env;
}

Future<void> _close(WidgetTester tester, Env env) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(env.dispose);
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('shows the tools grouped, each with its live status', (tester) async {
    final env = await _loadedEnv(tester);

    expect(find.text('Test User'), findsOneWidget); // header
    for (final t in [
      'Office Geofence',
      'Location Simulator',
      'Mock API Scenario',
      'Offline Sync Queue',
      'Leave Approvals',
      'Appearance',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Within 200 m'), findsOneWidget);
    expect(find.text('Real GPS'), findsOneWidget);
    expect(find.text('200 OK'), findsOneWidget);
    expect(find.text('All synced'), findsOneWidget);
    expect(find.text('LOCATION AND SERVER'), findsOneWidget);
    expect(find.text('Mock server'), findsOneWidget);
    await _close(tester, env);
  });

  testWidgets('Appearance opens a sheet with Light, Dark and System', (tester) async {
    final env = await _loadedEnv(tester);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    expect(find.text('Choose how the app looks. System follows your phone.'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    await _close(tester, env);
  });

  testWidgets('Office sheet shows the server office and rejects a bad latitude', (tester) async {
    final env = await _loadedEnv(tester);

    await tester.tap(find.text('Office Geofence'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Server office: 12.9716, 77.5946'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '95');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Latitude must be a number between -90 and 90.'), findsOneWidget);
    expect(env.settings.hasOfficeOverride, isFalse); // nothing was saved
    await _close(tester, env);
  });

  testWidgets('Location sheet: off by default, "~1 km away" is flagged as outside', (tester) async {
    final env = await _loadedEnv(tester);

    await tester.tap(find.text('Location Simulator'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mock GPS is off'), findsOneWidget);

    await tester.tap(find.text('Use mock GPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('~1 km away'));
    await tester.pumpAndSettle();

    expect(find.textContaining('outside the 200 m radius'), findsOneWidget);
    expect(find.textContaining('will be blocked'), findsOneWidget);

    await tester.tap(find.text('At office'));
    await tester.pumpAndSettle();
    expect(find.textContaining('inside the 200 m radius'), findsOneWidget);
    await _close(tester, env);
  });

  testWidgets('Location sheet shows the real GPS coordinates and the distance to the office', (tester) async {
    final env = await _loadedEnv(tester);
    env.location.result = const LocationOk(officeLat + 0.01, officeLng); // ~1.1 km north

    await tester.tap(find.text('Location Simulator'));
    await tester.pumpAndSettle();

    expect(find.text('Current location (real GPS)'), findsOneWidget);
    expect(find.text('12.981600, 77.594600'), findsOneWidget);
    expect(find.textContaining('1112 m from the office (outside the allowed area)'), findsOneWidget);
    await _close(tester, env);
  });

  testWidgets('"Use as mock position" copies the real position and switches the simulator on', (tester) async {
    final env = await _loadedEnv(tester);
    env.location.result = const LocationOk(officeLat + 0.01, officeLng);

    await tester.tap(find.text('Location Simulator'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mock GPS is off'), findsOneWidget);

    await tester.tap(find.text('Use as mock position'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mock GPS is off'), findsNothing);
    expect(find.textContaining('will be blocked'), findsOneWidget); // 1112 m > 200 m
    expect(find.textContaining('Mock GPS is on: punches use the mock position below'), findsOneWidget);
    await _close(tester, env);
  });

  testWidgets('Location sheet explains a permission or GPS problem and offers a way out', (tester) async {
    final env = await _loadedEnv(tester);
    env.location.result = const LocationDeniedForever();

    await tester.tap(find.text('Location Simulator'));
    await tester.pumpAndSettle();

    expect(find.text('Location permission is permanently denied.'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.textContaining(', 77.5'), findsNothing); // no coordinates shown
    await _close(tester, env);
  });

  testWidgets('Scenario sheet lists every scenario with a hint', (tester) async {
    final env = await _loadedEnv(tester);

    await tester.tap(find.text('Mock API Scenario'));
    await tester.pumpAndSettle();

    expect(find.text('Only for the next request'), findsOneWidget);
    for (final t in [
      'Normal (200 OK)',
      'Slow responses (3 s)',
      'Timeout (no answer, nothing saved)',
      'Timeout after server saved the event',
      'Server error (500)',
      'Duplicate attendance (409)',
      'Leave validation rejection (422)',
    ]) {
      await tester.scrollUntilVisible(find.text(t), 120, scrollable: find.byType(Scrollable).last);
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await _close(tester, env);
  });
}
