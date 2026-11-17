import 'package:dio/dio.dart';

import '../models/models.dart';

/// Failures the rest of the app understands (no Dio types leak out).
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// No connection, or timed out. The request MAY have reached the server.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'No connection to the server.']);
}

/// 5xx or unexpected response.
class ServerException extends ApiException {
  const ServerException([super.message = 'Server error. Please try again.']);
}

/// 409 - e.g. attendance already exists.
class ConflictException extends ApiException {
  const ConflictException(super.message, {this.code});
  final String? code;
}

/// 400 / 422 - server validation failed.
class ValidationException extends ApiException {
  const ValidationException(super.message, {this.fieldErrors = const {}});
  final Map<String, String> fieldErrors;
}

/// Contract with the backend. The app only talks to this interface so tests
/// can swap in a fake.
abstract class RebsApi {
  Future<Employee> getEmployee();
  Future<List<AttendanceRecord>> getAttendance(String month);
  Future<void> postAttendanceEvent(AttendanceEvent event);
  Future<LeaveBalance> getLeaveBalance();
  Future<List<LeaveRequest>> getLeaveRequests();
  Future<LeaveRequest> postLeaveRequest(LeaveDraft draft);

  /// Dev only: switch the mock server scenario (see mock_server/README).
  Future<void> setMockScenario(String name, {bool once = false});

  /// Dev only (reviewer tool): approve or reject a Pending leave request on the
  /// mock server. A real system does this on a manager's side.
  Future<LeaveRequest> reviewLeave(String id, {required bool approve});
}

class DioRebsApi implements RebsApi {
  DioRebsApi({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;

  @override
  Future<Employee> getEmployee() async {
    final j = await _call(() => _dio.get<Map<String, dynamic>>('/employee/me'));
    return Employee.fromJson(j);
  }

  @override
  Future<List<AttendanceRecord>> getAttendance(String month) async {
    final j = await _call(() =>
        _dio.get<Map<String, dynamic>>('/attendance', queryParameters: {'month': month}));
    return (j['records'] as List)
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> postAttendanceEvent(AttendanceEvent event) async {
    await _call(() =>
        _dio.post<Map<String, dynamic>>('/attendance/events', data: event.toApiJson()));
  }

  @override
  Future<LeaveBalance> getLeaveBalance() async {
    final j = await _call(() => _dio.get<Map<String, dynamic>>('/leave/balance'));
    return LeaveBalance.fromJson(j);
  }

  @override
  Future<void> setMockScenario(String name, {bool once = false}) async {
    await _call(() => _dio.get<Map<String, dynamic>>('/__scenario/$name',
        queryParameters: once ? {'count': 1} : null));
  }

  @override
  Future<LeaveRequest> reviewLeave(String id, {required bool approve}) async {
    final j = await _call(() =>
        _dio.get<Map<String, dynamic>>('/__leave/$id/${approve ? 'approve' : 'reject'}'));
    return LeaveRequest.fromJson(j);
  }

  @override
  Future<List<LeaveRequest>> getLeaveRequests() async {
    final j = await _call(() => _dio.get<Map<String, dynamic>>('/leave/requests'));
    return (j['requests'] as List)
        .map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<LeaveRequest> postLeaveRequest(LeaveDraft draft) async {
    final j = await _call(() =>
        _dio.post<Map<String, dynamic>>('/leave/requests', data: draft.toApiJson()));
    return LeaveRequest.fromJson(j);
  }

  Future<Map<String, dynamic>> _call(
      Future<Response<Map<String, dynamic>>> Function() fn) async {
    try {
      final res = await fn();
      return res.data ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw _map(e);
    } on FormatException {
      throw const ServerException('Unexpected response from server.');
    }
  }

  ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkException();
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final data = e.response?.data;
        final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};
        final message = (body['message'] as String?) ?? 'Request failed ($status).';
        if (status == 409) {
          return ConflictException(message, code: body['code'] as String?);
        }
        if (status == 400 || status == 422) {
          final errs = body['errors'];
          return ValidationException(message, fieldErrors: {
            if (errs is Map) for (final en in errs.entries) '${en.key}': '${en.value}',
          });
        }
        return ServerException(status >= 500 ? 'Server error ($status). Please try again.' : message);
      default: // cancel, badCertificate, unknown, ...
        return const NetworkException();
    }
  }
}
