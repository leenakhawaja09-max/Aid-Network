import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mission_status.dart';
import '../services/directions_service.dart';
import '../services/live_location_service.dart';
import '../services/mission_state_service.dart';
import '../utils/app_user.dart';

/// Reactive state for [LiveMissionScreen] / tracking (requester + helper views).
class LiveMissionController extends ChangeNotifier {
  LiveMissionController({
    required this.requestId,
    required this.isRequesterView,
    SupabaseClient? client,
    LiveLocationService? liveLocation,
    MissionStateService? missionState,
  })  : _sb = client ?? Supabase.instance.client,
        _liveLocation = liveLocation ?? LiveLocationService(),
        _missionState = missionState ?? MissionStateService();

  final String requestId;
  final bool isRequesterView;
  final SupabaseClient _sb;
  final LiveLocationService _liveLocation;
  final MissionStateService _missionState;

  bool loading = true;
  String? error;
  MissionStatus? status;
  List<Map<String, dynamic>> timeline = [];
  List<Map<String, dynamic>> incomingPitches = [];

  String helperId = '';
  String requesterId = '';
  String helperName = 'Helper';
  String requesterName = 'Requester';
  double? helperRating;

  LatLng? requesterPos;
  LatLng? helperPos;
  List<LatLng> routePoints = [];
  String distanceText = '—';
  String durationText = '—';

  StreamSubscription<List<Map<String, dynamic>>>? _tripSub;
  StreamSubscription<List<Map<String, dynamic>>>? _pitchSub;
  StreamSubscription<List<Map<String, dynamic>>>? _requestSub;
  Future<void> bootstrap() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadCore();
      await _loadTimeline();
      if (isRequesterView) {
        await _subscribeRequesterStreams();
      } else {
        await _startHelperPublishing();
      }
      await _refreshRoute();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCore() async {
    final pitches = await _sb
        .from('pitches')
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: false) as List;

    incomingPitches = pitches
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) {
          final s = p['status']?.toString() ?? '';
          return s == 'pending' || s == 'awaiting_helper_ack';
        })
        .toList();

    final accepted = pitches.cast<Map>().where((p) => p['status'] == 'accepted').toList();
    if (accepted.isEmpty && isRequesterView == false) {
      final ack = pitches.cast<Map>().where((p) => p['status'] == 'awaiting_helper_ack').toList();
      if (ack.isNotEmpty) {
        // Helper waiting to confirm — still show map to request pin
      }
    }

    Map<String, dynamic>? activePitch;
    for (final p in pitches) {
      final m = Map<String, dynamic>.from(p as Map);
      if (m['status'] == 'accepted') {
        activePitch = m;
        break;
      }
    }

    final reqRows = await _sb.from('requests').select().eq('id', requestId).limit(1);
    if (reqRows.isEmpty) throw Exception('Request not found');
    final req = Map<String, dynamic>.from(reqRows.first as Map);
    status = MissionStatus.fromDb(req['status']?.toString()) ?? MissionStatus.pending;
    requesterId = req['user_id']?.toString() ?? '';

    final pinLat = _coord(req['latitude']);
    final pinLng = _coord(req['longitude']);
    if (pinLat != null && pinLng != null) {
      requesterPos = LatLng(pinLat, pinLng);
    }

    if (activePitch != null) {
      helperId = activePitch['helper_id']?.toString() ?? '';
      final hp = await _profile(helperId);
      helperName = hp?['full_name']?.toString() ?? 'Helper';
      helperRating = _coord(hp?['rating']);
      final hLat = _coord(hp?['latitude']);
      final hLng = _coord(hp?['longitude']);
      if (hLat != null && hLng != null) helperPos = LatLng(hLat, hLng);
    }

    final rp = await _profile(requesterId);
    requesterName = rp?['full_name']?.toString() ?? 'Requester';
    if (requesterPos == null) {
      final rLat = _coord(rp?['latitude']);
      final rLng = _coord(rp?['longitude']);
      if (rLat != null && rLng != null) requesterPos = LatLng(rLat, rLng);
    }
  }

  Future<void> _loadTimeline() async {
    timeline = await _missionState.fetchTimeline(requestId);
    notifyListeners();
  }

  Future<void> _subscribeRequesterStreams() async {
    if (helperId.isEmpty) return;
    await _tripSub?.cancel();
    _tripSub = _liveLocation.streamActiveTrip(requestId).listen((rows) {
      if (rows.isEmpty) return;
      final row = rows.first;
      final lat = _coord(row['helper_lat']);
      final lng = _coord(row['helper_lng']);
      if (lat != null && lng != null) {
        helperPos = LatLng(lat, lng);
        _refreshRoute();
        notifyListeners();
      }
    });
  }

  Future<void> _startHelperPublishing() async {
    if (requesterId.isEmpty) return;
    final uid = currentUserId();
    if (uid == null) return;
    helperId = uid;
    await _liveLocation.startPublishingForMission(
      requestId: requestId,
      requesterId: requesterId,
    );
    _requestSub = _sb
        .from('requests')
        .stream(primaryKey: ['id'])
        .eq('id', requestId)
        .listen((rows) {
      if (rows.isEmpty) return;
      status = MissionStatus.fromDb(rows.first['status']?.toString());
      notifyListeners();
    });
  }

  Future<void> _refreshRoute() async {
    final h = helperPos;
    final r = requesterPos;
    if (h == null || r == null) return;
    final dir = await fetchDrivingDirections(origin: h, destination: r);
    routePoints = dir?.polylinePoints ?? [];
    distanceText = dir?.distanceText ?? '—';
    durationText = dir?.durationText ?? '—';
    notifyListeners();
  }

  Future<void> helperCheckpoint(MissionStatus target) async {
    switch (target) {
      case MissionStatus.inProgress:
        await _missionState.onHelperEnRoute(requestId);
        break;
      case MissionStatus.arriving:
        await _missionState.onHelperArrived(requestId);
        break;
      case MissionStatus.completed:
        await _missionState.onMissionCompleted(requestId);
        break;
      default:
        break;
    }
    status = target;
    await _loadTimeline();
    notifyListeners();
  }

  /// Partner user id for chat/call once mission is live.
  String get partnerUserId => isRequesterView ? helperId : requesterId;

  String get partnerDisplayName => isRequesterView ? helperName : requesterName;

  bool get canContactPartner {
    if (partnerUserId.isEmpty) return false;
    return status == MissionStatus.accepted ||
        status == MissionStatus.inProgress ||
        status == MissionStatus.arriving;
  }

  /// Either side can mark the mission done once the helper has confirmed.
  bool get canMarkDone {
    if (partnerUserId.isEmpty) return false;
    if (status == MissionStatus.completed) return false;
    return status == MissionStatus.accepted ||
        status == MissionStatus.inProgress ||
        status == MissionStatus.arriving;
  }

  /// Marks completed and rewards the accepted helper (+1 help, +10 karma).
  Future<Map<String, dynamic>?> completeMission() async {
    final reward = await _missionState.onMissionCompleted(requestId);
    status = MissionStatus.completed;
    await _loadTimeline();
    notifyListeners();
    return reward;
  }

  Future<Map<String, dynamic>?> _profile(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final row = await _sb.from('profiles').select().eq('id', uid).maybeSingle();
      return row != null ? Map<String, dynamic>.from(row) : null;
    } catch (_) {
      return null;
    }
  }

  double? _coord(dynamic v) {
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString());
    return null;
  }

  @override
  void dispose() {
    _tripSub?.cancel();
    _pitchSub?.cancel();
    _requestSub?.cancel();
    if (!isRequesterView) _liveLocation.stopPublishing();
    super.dispose();
  }
}
