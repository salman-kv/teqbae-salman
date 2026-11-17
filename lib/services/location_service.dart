import 'dart:async';

import 'package:geolocator/geolocator.dart';

sealed class LocationResult {
  const LocationResult();
}

class LocationOk extends LocationResult {
  const LocationOk(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class LocationDenied extends LocationResult {
  const LocationDenied();
}

class LocationDeniedForever extends LocationResult {
  const LocationDeniedForever();
}

class LocationServiceOff extends LocationResult {
  const LocationServiceOff();
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

abstract class LocationService {
  Future<LocationResult> current();
  Future<void> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceOff();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return const LocationDeniedForever();
      if (perm == LocationPermission.denied) return const LocationDenied();

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationOk(p.latitude, p.longitude);
    } on TimeoutException {
      return const LocationUnavailable();
    } on LocationServiceDisabledException {
      return const LocationServiceOff();
    } catch (_) {
      return const LocationUnavailable();
    }
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}
