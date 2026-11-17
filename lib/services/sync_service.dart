import 'dart:async';

import '../models/models.dart';
import 'api_service.dart';
import 'local_db.dart';

class SyncReport {
  const SyncReport({this.synced = 0, this.rejected = 0, this.remaining = 0, this.stoppedBy});
  final int synced;
  final int rejected;
  final int remaining;

  /// Why the run stopped early: 'network' | 'server' | null (queue drained).
  final String? stoppedBy;
}

/// Sends pending attendance events to the server.
///
/// Rules:
///  * Strict creation order (seq). We never skip ahead of an event that
///    could not be delivered, so a check-out can't overtake its check-in.
///  * Network error / timeout / 5xx: event stays `pending` and is retried with
///    the SAME eventId. The server dedupes on eventId, so a timeout after the
///    server already saved the event cannot create a second record.
///  * 409 / 400 / 422: the server definitively refused -> `rejected`.
///  * Only one sync run at a time; concurrent callers share the same run.
class SyncService {
  SyncService(this._api, this._db);

  final RebsApi _api;
  final LocalDb _db;

  Future<SyncReport>? _running;
  final _changes = StreamController<SyncReport>.broadcast();
  StreamSubscription<bool>? _connSub;

  /// Fires after every sync run (UI refreshes from it).
  Stream<SyncReport> get changes => _changes.stream;

  /// Try to sync whenever connectivity comes back.
  void attachConnectivity(Stream<bool> onlineChanges) {
    _connSub?.cancel();
    _connSub = onlineChanges.where((online) => online).listen((_) => syncNow());
  }

  Future<SyncReport> syncNow() {
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<SyncReport> _run() async {
    var synced = 0;
    var rejected = 0;
    String? stoppedBy;

    for (final queued in await _db.pendingEvents()) {
      // Re-read: an earlier rejection may have cascaded onto this event.
      final event = await _db.getEvent(queued.eventId);
      if (event == null || event.status != SyncStatus.pending) continue;

      try {
        await _api.postAttendanceEvent(event);
        await _db.setStatus(event.eventId, SyncStatus.synced);
        synced++;
      } on ConflictException catch (e) {
        await _reject(event, e.message);
        rejected++;
      } on ValidationException catch (e) {
        await _reject(event, e.message);
        rejected++;
      } on NetworkException {
        stoppedBy = 'network';
        break;
      } on ServerException {
        stoppedBy = 'server';
        break;
      }
    }

    final report = SyncReport(
      synced: synced,
      rejected: rejected,
      remaining: (await _db.pendingEvents()).length,
      stoppedBy: stoppedBy,
    );
    if (!_changes.isClosed) _changes.add(report);
    return report;
  }

  Future<void> _reject(AttendanceEvent event, String reason) async {
    await _db.setStatus(event.eventId, SyncStatus.rejected, reason: reason);
    // Punches of one day depend on each other (in -> out -> in -> done), so
    // everything still queued after a refused punch of that day is refused too.
    for (final p in await _db.pendingEvents()) {
      if (p.workDate == event.workDate) {
        await _db.setStatus(p.eventId, SyncStatus.rejected,
            reason: 'An earlier punch for this day was rejected.');
      }
    }
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    await _changes.close();
  }
}
