import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae_salman/controllers/attendance_controller.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/services/location_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'helpers.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  late Env env;

  setUp(() async {
    env = await Env.create();
    await env.attendance.load(); // online first load caches the employee
  });

  tearDown(() => env.dispose());

  group('check-out rules', () {
    test('check-out without check-in is rejected and nothing is saved', () async {
      final r = await env.attendance.perform(AttendanceType.checkOut);

      expect(r.outcome, ActionOutcome.blocked);
      expect(r.message, contains('punch in'));
      expect(await env.db.allEvents(), isEmpty);
      expect(env.api.postedIds, isEmpty);
    });

    test('cannot punch in twice in a row', () async {
      await env.attendance.perform(AttendanceType.checkIn);
      final second = await env.attendance.perform(AttendanceType.checkIn);

      expect(second.outcome, ActionOutcome.blocked);
      expect(second.message, contains('already punched in'));
      expect((await env.db.allEvents()).length, 1);
    });
  });

  group('multiple punches and Done', () {
    // Moves the clock; every perform() uses it for the event timestamp.
    Future<Env> clockEnv(DateTime Function() clock) async {
      final e = await Env.create(clock: clock);
      await e.attendance.load();
      return e;
    }

    test('several punch in/out pairs are all recorded and the total adds them up', () async {
      var t = DateTime.utc(2026, 11, 16, 3, 30); // 09:00 IST
      final e = await clockEnv(() => t);

      Future<void> at(int h, int m, AttendanceType type) async {
        t = DateTime.utc(2026, 11, 16, h, m);
        final r = await e.attendance.perform(type);
        expect(r.outcome, isNot(ActionOutcome.blocked), reason: r.message);
      }

      await at(3, 30, AttendanceType.checkIn); // 09:00
      await at(7, 30, AttendanceType.checkOut); // 13:00  -> 4h
      await at(8, 30, AttendanceType.checkIn); // 14:00
      await at(11, 30, AttendanceType.checkOut); // 17:00 -> 3h
      await e.attendance.load(silent: true);

      final s = e.attendance.todaySummary;
      expect(s.sessions.length, 2);
      expect(s.total, const Duration(hours: 7));
      expect(s.state, DayState.onBreak);
      expect((await e.db.allEvents()).length, 4);
      await e.dispose();
    });

    test('Done while punched in punches out first, closes the day and blocks more punches', () async {
      var t = DateTime.utc(2026, 11, 16, 3, 30);
      final e = await clockEnv(() => t);
      await e.attendance.perform(AttendanceType.checkIn);
      t = DateTime.utc(2026, 11, 16, 12, 0); // 17:30 IST, 8h later

      final r = await e.attendance.perform(AttendanceType.done);
      expect(r.outcome, ActionOutcome.synced, reason: r.message);
      expect(e.api.postedTypes,
          [AttendanceType.checkIn, AttendanceType.checkOut, AttendanceType.done]);

      await e.attendance.load(silent: true);
      final s = e.attendance.todaySummary;
      expect(s.state, DayState.done);
      expect(s.closedBy, 'manual');
      expect(s.result, DayResult.present); // 8h 30m
      expect((await e.attendance.perform(AttendanceType.checkIn)).outcome, ActionOutcome.blocked);
      expect((await e.attendance.perform(AttendanceType.done)).outcome, ActionOutcome.blocked);
      await e.dispose();
    });

    test('Done before any punch is refused', () async {
      final r = await env.attendance.perform(AttendanceType.done);
      expect(r.outcome, ActionOutcome.blocked);
      expect(await env.db.allEvents(), isEmpty);
    });

    test('Done while offline stays pending (both events) and syncs in order', () async {
      await env.attendance.perform(AttendanceType.checkIn);
      env.api.offline = true;
      final r = await env.attendance.perform(AttendanceType.done);
      expect(r.outcome, ActionOutcome.savedPending);
      expect((await env.db.pendingEvents()).map((e) => e.type),
          [AttendanceType.checkOut, AttendanceType.done]);

      env.api.offline = false;
      final report = await env.sync.syncNow();
      expect(report.synced, 2);
      expect(env.api.postedTypes.last, AttendanceType.done);
    });

    test('a short day (under 8h) is "short hours", treated as leave', () async {
      var t = DateTime.utc(2026, 11, 16, 3, 30);
      final e = await clockEnv(() => t);
      await e.attendance.perform(AttendanceType.checkIn);
      t = DateTime.utc(2026, 11, 16, 6, 30); // only 3h later
      await e.attendance.perform(AttendanceType.done);
      await e.attendance.load(silent: true);

      expect(e.attendance.todaySummary.result, DayResult.shortHours);
      expect(e.attendance.monthStats.shortDays, 1);
      expect(e.attendance.monthStats.present, 0);
      await e.dispose();
    });
  });

  group('duplicates and retries', () {
    test('rapid double tap creates only one event', () async {
      final results = await Future.wait([
        env.attendance.perform(AttendanceType.checkIn),
        env.attendance.perform(AttendanceType.checkIn),
      ]);

      expect(results.map((r) => r.outcome), contains(ActionOutcome.ignored));
      expect((await env.db.allEvents()).length, 1);
      expect(env.api.accepted.length, 1);
    });

    test('timeout after the server saved the event: retry reuses the same eventId, no duplicate',
        () async {
      env.api.dropResponseOnce = true; // server stores it, client sees a timeout

      final r = await env.attendance.perform(AttendanceType.checkIn);
      expect(r.outcome, ActionOutcome.savedPending);
      expect(env.api.accepted.length, 1); // server already has it
      expect((await env.db.pendingEvents()).length, 1); // client does not know

      final report = await env.sync.syncNow(); // retry

      expect(report.synced, 1);
      expect(env.api.postedIds, ['evt-1', 'evt-1']); // same id both times
      expect(env.api.accepted.length, 1); // still one server record
      expect((await env.db.pendingEvents()), isEmpty);
    });
  });

  group('offline queue', () {
    test('pending events survive a restart and sync in order', () async {
      env.api.offline = true;
      final a = await env.attendance.perform(AttendanceType.checkIn);
      final b = await env.attendance.perform(AttendanceType.checkOut);
      expect(a.outcome, ActionOutcome.savedPending);
      expect(b.outcome, ActionOutcome.savedPending);

      // "Close and reopen the app": new DB connection on the same file.
      final path = env.path;
      await env.dispose();
      final reopened = await Env.create(path: path, api: env.api);

      final pending = await reopened.db.pendingEvents();
      expect(pending.map((e) => e.type), [AttendanceType.checkIn, AttendanceType.checkOut]);
      expect(pending.every((e) => e.status == SyncStatus.pending), isTrue);

      env.api.offline = false; // connectivity is back
      final report = await reopened.sync.syncNow();

      expect(report.synced, 2);
      expect(env.api.postedTypes, [AttendanceType.checkIn, AttendanceType.checkOut]);
      expect((await reopened.db.pendingEvents()), isEmpty);
      expect((await reopened.db.allEvents()).every((e) => e.status == SyncStatus.synced), isTrue);
      env = reopened; // tearDown disposes it
    });

    test('a server outage keeps events pending and stops the queue (order preserved)', () async {
      env.api.offline = true;
      await env.attendance.perform(AttendanceType.checkIn);
      await env.attendance.perform(AttendanceType.checkOut);

      env.api.offline = false;
      env.api.serverError = true;
      final report = await env.sync.syncNow();

      expect(report.synced, 0);
      expect(report.remaining, 2);
      expect(report.stoppedBy, 'server');
      expect(env.api.postedTypes, [AttendanceType.checkIn]); // check-out never overtakes
    });

    test('server 409 "already exists" marks the event Rejected, with its check-out', () async {
      env.api.offline = true;
      await env.attendance.perform(AttendanceType.checkIn);
      await env.attendance.perform(AttendanceType.checkOut);

      env.api.offline = false;
      env.api.conflict = true;
      final report = await env.sync.syncNow();

      final events = await env.db.allEvents();
      expect(report.rejected, 1);
      expect(events.every((e) => e.status == SyncStatus.rejected), isTrue);
      expect(events.first.rejectReason, contains('already exists'));
    });
  });

  group('company date', () {
    test('work date rolls over at company midnight, so yesterday\'s check-in is not today', () async {
      var t = fixedNow; // 09:30 IST on 16 Nov
      final clockEnv = await Env.create(clock: () => t);
      await clockEnv.attendance.load();

      await clockEnv.attendance.perform(AttendanceType.checkIn);
      await clockEnv.attendance.load(silent: true);
      expect(clockEnv.attendance.workDate, '2026-11-16');
      expect(clockEnv.attendance.todaySummary.state, DayState.working);

      // 20:00 UTC on 16 Nov = 01:30 IST on 17 Nov -> a new company day.
      t = DateTime.utc(2026, 11, 16, 20, 0);
      expect(clockEnv.attendance.workDate, '2026-11-17');
      expect(clockEnv.attendance.todaySummary.state, DayState.notStarted);

      final r = await clockEnv.attendance.perform(AttendanceType.checkIn); // allowed again
      expect(r.outcome, isNot(ActionOutcome.blocked), reason: r.message);
      await clockEnv.dispose();
    });
  });

  group('location', () {
    test('outside the office radius is blocked with a distance message', () async {
      env.location.result = const LocationOk(officeLat + 0.01, officeLng); // ~1.1 km
      final r = await env.attendance.perform(AttendanceType.checkIn);

      expect(r.outcome, ActionOutcome.blocked);
      expect(r.message, contains('from the office'));
      expect(await env.db.allEvents(), isEmpty);
    });

    test('permanently denied permission offers the settings shortcut', () async {
      env.location.result = const LocationDeniedForever();
      final r = await env.attendance.perform(AttendanceType.checkIn);

      expect(r.outcome, ActionOutcome.blocked);
      expect(r.openSettings, isTrue);
    });

    test('location unavailable is reported, nothing saved', () async {
      env.location.result = const LocationUnavailable();
      final r = await env.attendance.perform(AttendanceType.checkIn);

      expect(r.outcome, ActionOutcome.blocked);
      expect(await env.db.allEvents(), isEmpty);
    });
  });
}
