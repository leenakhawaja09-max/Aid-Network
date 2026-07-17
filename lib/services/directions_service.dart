import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/maps_config.dart';

class DirectionsLegSummary {
  final String distanceText;
  final String durationText;
  final List<LatLng> polylinePoints;

  const DirectionsLegSummary({
    required this.distanceText,
    required this.durationText,
    required this.polylinePoints,
  });
}

/// Calls Google Directions API (same key as Maps; enable "Directions API" in Cloud Console).
Future<DirectionsLegSummary?> fetchDrivingDirections({
  required LatLng origin,
  required LatLng destination,
}) async {
  if (googleMapsApiKey.isEmpty) return null;
  final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
    'origin': '${origin.latitude},${origin.longitude}',
    'destination': '${destination.latitude},${destination.longitude}',
    'mode': 'driving',
    'key': googleMapsApiKey,
  });
  try {
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['status'] != 'OK') return null;
    final routes = map['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;
    final legs = (routes.first as Map<String, dynamic>)['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) return null;
    final leg = legs.first as Map<String, dynamic>;
    final dist = (leg['distance'] as Map<String, dynamic>)['text'] as String? ?? '—';
    final dur = (leg['duration'] as Map<String, dynamic>)['text'] as String? ?? '—';
    final overview = (routes.first as Map<String, dynamic>)['overview_polyline']
        as Map<String, dynamic>?;
    final encoded = overview?['points'] as String? ?? '';
    return DirectionsLegSummary(
      distanceText: dist,
      durationText: dur,
      polylinePoints: _decodePolyline(encoded),
    );
  } catch (_) {
    return null;
  }
}

List<LatLng> _decodePolyline(String encoded) {
  if (encoded.isEmpty) return [];
  final List<LatLng> points = [];
  int index = 0;
  int lat = 0;
  int lng = 0;
  while (index < encoded.length) {
    int b;
    int shift = 0;
    int result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
