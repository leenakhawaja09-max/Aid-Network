import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/request_expiry.dart';

/// PostGIS RPC `get_requests_in_radius` (meters).
class GeospatialDiscoveryService {
  GeospatialDiscoveryService({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  static double milesToMeters(double miles) => miles * 1609.344;

  Future<List<Map<String, dynamic>>> fetchRequestsInRadius({
    required double userLat,
    required double userLng,
    required double radiusMiles,
  }) async {
    final meters = milesToMeters(radiusMiles.clamp(0.5, 250.0));
    try {
      final rows = await _sb.rpc(
        'get_requests_in_radius',
        params: {
          'user_lat': userLat,
          'user_lng': userLng,
          'radius_meters': meters,
        },
      );
      if (rows is List) {
        return rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where(isRequestVisibleForDiscovery)
            .toList();
      }
    } catch (e) {
      // RPC missing until migration — caller may fall back to client filter
      rethrow;
    }
    return [];
  }
}
