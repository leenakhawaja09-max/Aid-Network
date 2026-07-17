import 'dart:math' as math;

/// Great-circle distance in **miles** between two WGS84 points.
double haversineMiles(double lat1, double lon1, double lat2, double lon2) {
  const earthMi = 3958.7613;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthMi * c;
}

/// Great-circle distance in kilometres (same model as [haversineMiles]).
double haversineKm(double lat1, double lon1, double lat2, double lon2) =>
    haversineMiles(lat1, lon1, lat2, lon2) * 1.609344;

double _rad(double deg) => deg * math.pi / 180.0;

double? readCoord(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Request is visible to viewer if viewer is within [radiusMiles] of the request point.
bool withinRadiusMiles({
  required double viewerLat,
  required double viewerLng,
  required double requestLat,
  required double requestLng,
  required double radiusMiles,
}) {
  return haversineMiles(viewerLat, viewerLng, requestLat, requestLng) <= radiusMiles;
}
