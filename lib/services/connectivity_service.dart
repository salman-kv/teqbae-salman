import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper so the rest of the app doesn't depend on the plugin.
/// NOTE: this only says a network interface is up, not that the API is
/// reachable. API failures are still the source of truth.
class ConnectivityService {
  final _c = Connectivity();

  Stream<bool> get onlineChanges =>
      _c.onConnectivityChanged.map((r) => !r.contains(ConnectivityResult.none));

  Future<bool> isOnline() async =>
      !(await _c.checkConnectivity()).contains(ConnectivityResult.none);
}
