import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_user.dart';
import 'location_service.dart';

/// Helper: streams GPS → `profiles` + `active_trips`. Requester: realtime on `active_trips`.
class LiveLocationService {
  LiveLocationService({
    SupabaseClient? client,
    LocationService? location,
  })  : _sb = client ?? Supabase.instance.client,
        _location = location ?? const LocationService();

  final SupabaseClient _sb;
  final LocationService _location;
  StreamSubscription<DevicePosition>? _sub;

  Future<void> startPublishingForMission({
    required String requestId,
    required String requesterId,
    int distanceFilterMeters = 15,
  }) async {
    await stopPublishing();
    final helperId = currentUserId();
    if (helperId == null) return;

    await _location.ensurePermission();

    _sub = _location.positionStream(distanceFilterMeters: distanceFilterMeters).listen(
      (pos) async {
        try {
          await _sb.from('profiles').update({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
          }).eq('id', helperId);

          await _sb.from('active_trips').upsert({
            'request_id': requestId,
            'helper_id': helperId,
            'requester_id': requesterId,
            'helper_lat': pos.latitude,
            'helper_lng': pos.longitude,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (_) {}
      },
    );
  }

  Future<void> stopPublishing() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Requester listens to helper position for [requestId].
  Stream<List<Map<String, dynamic>>> streamActiveTrip(String requestId) {
    return _sb
        .from('active_trips')
        .stream(primaryKey: ['request_id'])
        .eq('request_id', requestId);
  }

  /// Fallback: realtime on helper profile when `active_trips` not migrated yet.
  Stream<List<Map<String, dynamic>>> streamHelperProfile(String helperId) {
    return _sb.from('profiles').stream(primaryKey: ['id']).eq('id', helperId);
  }
}
