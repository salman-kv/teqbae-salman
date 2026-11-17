import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../models/rules.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import 'attendance_controller.dart' show LoadStatus;

class LeaveSubmitResult {
  const LeaveSubmitResult({
    required this.success,
    this.message,
    this.fieldErrors = const {},
  });
  final bool success;
  final String? message;
  final Map<String, String> fieldErrors; // startDate / endDate / reason
}

/// Controller for the Leaves tab and the Apply sheet.
class LeaveController extends ChangeNotifier {
  LeaveController(this._api, this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final RebsApi _api;
  final LocalDb _db;
  final DateTime Function() _now;

  LoadStatus status = LoadStatus.loading;
  String? error;
  List<LeaveRequest> requests = [];
  LeaveBalance? balance;
  bool fromCache = false;
  bool submitting = false;

  /// Network first; saved copy when offline (viewing works offline).
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      status = LoadStatus.loading;
      notifyListeners();
    }
    fromCache = false;
    ApiException? failure;
    try {
      final reqs = await _api.getLeaveRequests();
      await _db.putCache('leave_requests', reqs.map((r) => r.toJson()).toList());
      final bal = await _api.getLeaveBalance();
      await _db.putCache('balance', bal.toJson());
    } on ApiException catch (e) {
      failure = e;
      fromCache = true;
    }

    final rawReqs = await _db.getCache('leave_requests');
    final rawBal = await _db.getCache('balance');
    if (rawReqs == null || rawBal == null) {
      status = LoadStatus.error;
      error = failure?.message ?? 'No leave data available.';
    } else {
      requests = (rawReqs as List)
          .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
          .toList();
      balance = LeaveBalance.fromJson(rawBal as Map<String, dynamic>);
      status = LoadStatus.ready;
    }
    notifyListeners();
  }

  /// Reviewer tool (mock server only): approve or reject a Pending request, then
  /// reload the list. Returns an error message, or null on success.
  Future<String?> review(LeaveRequest r, {required bool approve}) async {
    try {
      await _api.reviewLeave(r.id, approve: approve);
      await load(silent: true);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Validates locally, then on the server (the server has the final say).
  Future<LeaveSubmitResult> submit(LeaveDraft draft) async {
    if (submitting) return const LeaveSubmitResult(success: false, message: 'Already submitting…');
    final emp = await _db.getCache('employee');
    final bal = balance;
    if (emp == null || bal == null) {
      return const LeaveSubmitResult(
          success: false, message: 'Load leave data once while online before applying.');
    }

    final tzName = Employee.fromJson(emp as Map<String, dynamic>).office.timezone;
    final errors = LeaveRules.validate(
      draft: draft,
      today: companyDate(_now(), tzName),
      available: bal.of(draft.type),
      existing: requests,
    );
    if (errors.isNotEmpty) return LeaveSubmitResult(success: false, fieldErrors: errors);

    submitting = true;
    notifyListeners();
    try {
      await _api.postLeaveRequest(draft);
      await load(silent: true);
      return const LeaveSubmitResult(success: true, message: 'Leave request submitted.');
    } on ValidationException catch (e) {
      return LeaveSubmitResult(success: false, message: e.message, fieldErrors: e.fieldErrors);
    } on ConflictException catch (e) {
      return LeaveSubmitResult(success: false, message: e.message);
    } on NetworkException {
      return const LeaveSubmitResult(
          success: false,
          message: 'Leave can only be submitted online. Check your connection and try again.');
    } on ServerException catch (e) {
      return LeaveSubmitResult(success: false, message: e.message);
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
