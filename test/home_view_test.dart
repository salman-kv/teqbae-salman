import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/views/home_view.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'helpers.dart';

Widget _app(Env env) => ChangeNotifierProvider.value(
      value: env.attendance,
      child: const MaterialApp(home: HomeView()),
    );

void main() {
  setUpAll(tz_data.initializeTimeZones);

  testWidgets('shows a spinner while loading', (tester) async {
    final env = (await tester.runAsync(Env.create))!;
    await tester.pumpWidget(_app(env)); // load() not called yet -> loading

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.runAsync(env.dispose);
  });

  testWidgets('shows an error with Retry when offline and nothing is cached', (tester) async {
    final env = (await tester.runAsync(Env.create))!;
    env.api.offline = true;
    await tester.runAsync(env.attendance.load);
    await tester.pumpWidget(_app(env));

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No connection to the server.'), findsOneWidget);
    await tester.runAsync(env.dispose);
  });

  testWidgets('dashboard shows employee, balances, status and the Punch In button', (tester) async {
    tester.view.physicalSize = const Size(800, 2600); // tall, so the whole list is built
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final env = (await tester.runAsync(Env.create))!;
    await tester.runAsync(env.attendance.load);
    await tester.pumpWidget(_app(env));

    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('EMP-1'), findsOneWidget);
    expect(find.text('QA'), findsOneWidget);
    expect(find.text('Not Punched In'), findsOneWidget);
    expect(find.text('Punch In'), findsOneWidget);
    expect(find.text('Online · everything is synced'), findsOneWidget);
    expect(find.textContaining('Casual leave'), findsOneWidget);
    expect(find.textContaining('No attendance records yet'), findsOneWidget); // empty state

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(env.dispose);
  });

  testWidgets('offline check-in shows Pending Sync on the dashboard', (tester) async {
    final env = (await tester.runAsync(Env.create))!;
    await tester.runAsync(env.attendance.load); // online: caches profile
    env.api.offline = true;
    await tester.runAsync(() => env.attendance.perform(AttendanceType.checkIn));
    await tester.runAsync(() => env.attendance.load(silent: true));
    await tester.pumpWidget(_app(env));

    expect(find.text('Pending Sync'), findsWidgets);
    expect(find.text('Working'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose the view (stops the clock timer)
    await tester.runAsync(env.dispose);
  });
}
