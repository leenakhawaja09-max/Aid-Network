import 'package:flutter/material.dart' show EdgeInsets;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Result of a location read — snapped WGS84 coordinates.
class DevicePosition {
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  const DevicePosition({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Geolocator wrapper: service check, permissions, high-accuracy fix, map camera.
class LocationService {
  const LocationService();

  Future<bool> ensureServiceEnabled() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on device location (GPS) in settings.');
    }
    return true;
  }

  Future<LocationPermission> ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw const LocationException('Location permission denied.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permanently denied. Enable it in app settings.',
      );
    }
    return perm;
  }

  Future<DevicePosition> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    await ensureServiceEnabled();
    await ensurePermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy),
    );
    return DevicePosition(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy,
    );
  }

  Stream<DevicePosition> positionStream({
    int distanceFilterMeters = 15,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMeters,
      ),
    ).map(
      (p) => DevicePosition(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
      ),
    );
  }

  /// Centers [mapController] on [target] (OpenStreetMap / flutter_map — no paid map SDK).
  void animateCameraTo(
    MapController mapController, {
    required LatLng target,
    double zoom = 15,
  }) {
    mapController.move(target, zoom);
  }

  void fitBounds(
    MapController mapController, {
    required List<LatLng> points,
    EdgeInsets padding = const EdgeInsets.all(48),
  }) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      animateCameraTo(mapController, target: points.first);
      return;
    }
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final p in points) {
      south = south < p.latitude ? south : p.latitude;
      north = north > p.latitude ? north : p.latitude;
      west = west < p.longitude ? west : p.longitude;
      east = east > p.longitude ? east : p.longitude;
    }
    final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));
    mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: padding));
  }
}

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => message;
}
