import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';

/// Profile / "Reviewer Simulator" settings, saved on the device:
///  * theme
///  * office coordinates override (geofence)
///  * mock GPS (pretend to be at a given location)
///  * mock API scenario (talks to the mock server)
class SettingsController extends ChangeNotifier {
  SettingsController(this._db, this._api);

  final LocalDb _db;
  final RebsApi _api;
  static const _key = 'settings';

  ThemeMode themeMode = ThemeMode.system;

  double? officeLat, officeLng, officeRadius; // null = use the server's office
  bool gpsEnabled = false;
  double gpsLat = 0, gpsLng = 0;
  String scenario = 'normal';

  bool get hasOfficeOverride => officeLat != null;

  /// Server office config, with the local override applied on top.
  OfficeConfig effectiveOffice(OfficeConfig server) => hasOfficeOverride
      ? server.copyWith(latitude: officeLat, longitude: officeLng, radiusMeters: officeRadius)
      : server;

  Future<void> load() async {
    final j = await _db.getCache(_key);
    if (j is Map<String, dynamic>) {
      themeMode = ThemeMode.values.byName(j['theme'] as String? ?? 'system');
      officeLat = (j['officeLat'] as num?)?.toDouble();
      officeLng = (j['officeLng'] as num?)?.toDouble();
      officeRadius = (j['officeRadius'] as num?)?.toDouble();
      gpsEnabled = j['gpsEnabled'] as bool? ?? false;
      gpsLat = (j['gpsLat'] as num?)?.toDouble() ?? 0;
      gpsLng = (j['gpsLng'] as num?)?.toDouble() ?? 0;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _db.putCache(_key, {
      'theme': themeMode.name,
      'officeLat': officeLat,
      'officeLng': officeLng,
      'officeRadius': officeRadius,
      'gpsEnabled': gpsEnabled,
      'gpsLat': gpsLat,
      'gpsLng': gpsLng,
    });
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) {
    themeMode = m;
    return _save();
  }

  Future<void> setOffice(double lat, double lng, double radius) {
    officeLat = lat;
    officeLng = lng;
    officeRadius = radius;
    return _save();
  }

  Future<void> resetOffice() {
    officeLat = officeLng = officeRadius = null;
    return _save();
  }

  Future<void> setMockGps({required bool enabled, required double lat, required double lng}) {
    gpsEnabled = enabled;
    gpsLat = lat;
    gpsLng = lng;
    return _save();
  }

  /// Returns an error message, or null on success.
  Future<String?> setScenario(String name, {bool once = false}) async {
    try {
      await _api.setMockScenario(name, once: once);
      scenario = once ? '$name (next request)' : name;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return 'Could not reach the mock server: ${e.message}';
    }
  }
}
