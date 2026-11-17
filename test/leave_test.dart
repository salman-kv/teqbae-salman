import 'package:flutter_test/flutter_test.dart';
import 'package:teqbae_salman/models/models.dart';
import 'package:teqbae_salman/models/rules.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'helpers.dart';

const _today = '2026-11-16';

const _approved = LeaveRequest(
  id: 'LV-1',
  type: LeaveType.casual,
  startDate: '2026-11-20',
  endDate: '2026-11-21',
  reason: 'Family function out of town',
  status: LeaveStatus.approved,
);

LeaveDraft _draft(String start, String end, {String reason = 'Visiting family this week'}) =>
    LeaveDraft(type: LeaveType.casual, startDate: start, endDate: end, reason: reason);

Map<String, String> _validate(LeaveDraft d, {int available = 8, List<LeaveRequest> existing = const [_approved]}) =>
    LeaveRules.validate(draft: d, today: _today, available: available, existing: existing);

void main() {
  group('LeaveRules', () {
    test('dates overlapping an approved request are rejected', () {
      final errors = _validate(_draft('2026-11-21', '2026-11-22'));
      expect(errors['startDate'], contains('Overlaps'));
    });

    test('dates overlapping a pending request are rejected', () {
      const pending = LeaveRequest(
        id: 'LV-2',
        type: LeaveType.sick,
        startDate: '2026-12-01',
        endDate: '2026-12-03',
        reason: 'Scheduled dental surgery',
        status: LeaveStatus.pending,
      );
      final errors = _validate(_draft('2026-12-02', '2026-12-02'), existing: [pending]);
      expect(errors['startDate'], contains('Overlaps'));
    });

    test('a request fully inside an existing one is rejected', () {
      expect(_validate(_draft('2026-11-20', '2026-11-20')).containsKey('startDate'), isTrue);
    });

    test('a rejected request does not block the same dates', () {
      const rejected = LeaveRequest(
        id: 'LV-3',
        type: LeaveType.casual,
        startDate: '2026-11-25',
        endDate: '2026-11-26',
        reason: 'Personal errands at the bank',
        status: LeaveStatus.rejected,
      );
      expect(_validate(_draft('2026-11-25', '2026-11-26'), existing: [rejected]), isEmpty);
    });

    test('non-overlapping dates are valid', () {
      expect(_validate(_draft('2026-11-22', '2026-11-23')), isEmpty);
    });

    test('start date before today is rejected; today is allowed', () {
      expect(_validate(_draft('2026-11-15', '2026-11-16')).containsKey('startDate'), isTrue);
      expect(_validate(_draft('2026-11-16', '2026-11-16')), isEmpty);
    });

    test('end before start is rejected', () {
      expect(_validate(_draft('2026-11-24', '2026-11-23')).containsKey('endDate'), isTrue);
    });

    test('reason needs 10 non-whitespace characters', () {
      expect(_validate(_draft('2026-11-24', '2026-11-24', reason: '   short   ')).containsKey('reason'), isTrue);
      expect(_validate(_draft('2026-11-24', '2026-11-24', reason: 'a b c d e f g h i j')), isEmpty);
    });

    test('days over the balance are rejected (calendar days count)', () {
      final errors = _validate(_draft('2026-12-01', '2026-12-05'), available: 4); // 5 days
      expect(errors['endDate'], contains('only 4'));
    });
  });

  group('LeaveController', () {
    setUpAll(tz_data.initializeTimeZones);

    test('overlapping request is stopped locally and never sent to the server', () async {
      final env = await Env.create();
      await env.attendance.load(); // caches the employee (timezone)
      await env.leave.load();

      final result = await env.leave.submit(_draft('2026-11-21', '2026-11-22'));

      expect(result.success, isFalse);
      expect(result.fieldErrors['startDate'], contains('Overlaps'));
      expect(env.api.leavePosts, 0);
      await env.dispose();
    });

    test('valid request is sent and the list reloads', () async {
      final env = await Env.create();
      await env.attendance.load();
      await env.leave.load();

      final result = await env.leave.submit(_draft('2026-11-24', '2026-11-25'));

      expect(result.success, isTrue);
      expect(env.api.leavePosts, 1);
      await env.dispose();
    });

    const pendingRequest = LeaveRequest(
      id: 'LV-2',
      type: LeaveType.sick,
      startDate: '2026-12-07',
      endDate: '2026-12-07',
      reason: 'Scheduled dental surgery',
      status: LeaveStatus.pending,
    );

    LeaveStatus statusOf(Env env, String id) => env.leave.requests.firstWhere((r) => r.id == id).status;

    test('reviewer can approve a Pending request and the list shows it', () async {
      final env = await Env.create();
      env.api.leave.add(pendingRequest);
      await env.attendance.load();
      await env.leave.load();
      expect(statusOf(env, 'LV-2'), LeaveStatus.pending);

      final error = await env.leave.review(pendingRequest, approve: true);

      expect(error, isNull);
      expect(statusOf(env, 'LV-2'), LeaveStatus.approved);
      await env.dispose();
    });

    test('reviewer can reject a Pending request', () async {
      final env = await Env.create();
      env.api.leave.add(pendingRequest);
      await env.attendance.load();
      await env.leave.load();

      final error = await env.leave.review(pendingRequest, approve: false);

      expect(error, isNull);
      expect(statusOf(env, 'LV-2'), LeaveStatus.rejected);
      await env.dispose();
    });

    test('a request that is already decided cannot be decided again', () async {
      final env = await Env.create();
      env.api.leave.add(pendingRequest);
      await env.attendance.load();
      await env.leave.load();
      await env.leave.review(pendingRequest, approve: true);

      final error = await env.leave.review(pendingRequest, approve: false);

      expect(error, contains('already approved'));
      expect(statusOf(env, 'LV-2'), LeaveStatus.approved); // unchanged
      await env.dispose();
    });

    test('reviewing needs the server: offline gives a message and changes nothing', () async {
      final env = await Env.create();
      env.api.leave.add(pendingRequest);
      await env.attendance.load();
      await env.leave.load();

      env.api.offline = true;
      final error = await env.leave.review(pendingRequest, approve: true);

      expect(error, isNotNull);
      expect(statusOf(env, 'LV-2'), LeaveStatus.pending);
      await env.dispose();
    });

    test('submitting while offline fails with a clear message; saved list stays viewable', () async {
      final env = await Env.create();
      await env.attendance.load();
      await env.leave.load();

      env.api.offline = true;
      final result = await env.leave.submit(_draft('2026-11-24', '2026-11-25'));
      await env.leave.load(silent: true);

      expect(result.success, isFalse);
      expect(result.message, contains('online'));
      expect(env.leave.fromCache, isTrue);
      expect(env.leave.requests, isNotEmpty);
      await env.dispose();
    });
  });
}
