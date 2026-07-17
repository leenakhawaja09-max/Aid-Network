import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mission_status.dart';
import '../utils/app_user.dart';

/// Writes `requests.status` + `mission_events` for the live mission state machine.
class MissionStateService {
  MissionStateService({SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;

  /// Karma added to the accepted helper when a mission is completed.
  static const int karmaPerCompletedMission = 10;

  Future<void> _logEvent({
    required String requestId,
    required String eventKey,
    String? note,
  }) async {
    final uid = currentUserId();
    if (uid == null) return;
    try {
      await _sb.from('mission_events').insert({
        'request_id': requestId,
        'event_key': eventKey,
        'actor_id': uid,
        if (note != null) 'note': note,
      });
    } catch (_) {}
  }

  Future<void> setRequestStatus({
    required String requestId,
    required MissionStatus status,
    String? eventKey,
    String? note,
  }) async {
    await _sb.from('requests').update({'status': status.dbValue}).eq('id', requestId);
    try {
      await _logEvent(
        requestId: requestId,
        eventKey: eventKey ?? status.dbValue,
        note: note,
      );
    } catch (e) {
      // Status update succeeded; timeline is optional.
      debugPrint('mission_events insert: $e');
    }
  }

  Future<void> onFirstPitch(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.pitched,
      eventKey: 'pitched',
    );
  }

  Future<void> onHelperSelected(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.helperSelected,
      eventKey: 'helper_selected',
    );
  }

  Future<void> onHelperAccepted(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.accepted,
      eventKey: 'accepted',
    );
  }

  Future<void> onHelperEnRoute(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.inProgress,
      eventKey: 'en_route',
      note: 'Helper en route',
    );
  }

  Future<void> onHelperArrived(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.arriving,
      eventKey: 'arrived',
      note: 'Helper arrived',
    );
  }

  /// Marks mission completed and rewards the accepted helper (+1 help, +10 karma).
  Future<Map<String, dynamic>?> onMissionCompleted(String requestId) async {
    await setRequestStatus(
      requestId: requestId,
      status: MissionStatus.completed,
      eventKey: 'completed',
    );
    return rewardHelperForCompletedRequest(requestId);
  }

  /// Increments [profiles.helps_count] (+1) and [profiles.karma_points] for the accepted helper.
  Future<Map<String, dynamic>?> rewardHelperForCompletedRequest(String requestId) async {
    Map<String, dynamic>? rpcResult;
    try {
      final result = await _sb.rpc(
        'reward_helper_for_completed_request',
        params: {'p_request_id': requestId},
      );
      if (result is Map) {
        rpcResult = Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('reward_helper_for_completed_request: $e');
    }

    if (rpcResult != null && rpcResult['ok'] == true) {
      return rpcResult;
    }

    final reason = rpcResult?['reason'] ?? 'rpc_failed';
    debugPrint('reward_helper: using client fallback ($reason)');
    return _rewardHelperClientFallback(requestId);
  }

  Future<Map<String, dynamic>?> _rewardHelperClientFallback(String requestId) async {
    try {
      final helperId = await _acceptedHelperId(requestId);
      if (helperId == null || helperId.isEmpty) {
        return {'ok': false, 'reason': 'no_accepted_helper'};
      }

      final prof = await _sb
          .from('profiles')
          .select('helps_count, karma_points')
          .eq('id', helperId)
          .maybeSingle();
      if (prof == null) {
        return {'ok': false, 'reason': 'profile_not_found'};
      }
      final helps = (prof['helps_count'] as num?)?.toInt() ?? 0;
      final karma = (prof['karma_points'] as num?)?.toInt() ?? 0;
      final uid = currentUserId();
      if (uid != helperId) {
        // RLS only allows updating your own profile from the client.
        return {
          'ok': false,
          'reason': 'run_supabase_helper_rewards_sql',
          'helper_id': helperId,
        };
      }
      await _sb.from('profiles').update({
        'helps_count': helps + 1,
        'karma_points': karma + karmaPerCompletedMission,
      }).eq('id', helperId);
      return {
        'ok': true,
        'helper_id': helperId,
        'helps_count': helps + 1,
        'karma_points': karma + karmaPerCompletedMission,
      };
    } catch (e) {
      debugPrint('reward_helper fallback: $e');
      return {'ok': false, 'reason': e.toString()};
    }
  }

  Future<String?> _acceptedHelperId(String requestId) async {
    final accepted = await _sb
        .from('pitches')
        .select('helper_id')
        .eq('request_id', requestId)
        .eq('status', 'accepted')
        .limit(1);
    if (accepted.isNotEmpty) {
      return accepted.first['helper_id']?.toString();
    }
    final uid = currentUserId();
    if (uid == null) return null;
    final mine = await _sb
        .from('pitches')
        .select('helper_id')
        .eq('request_id', requestId)
        .eq('helper_id', uid)
        .inFilter('status', ['accepted', 'awaiting_helper_ack'])
        .limit(1);
    if (mine.isNotEmpty) return uid;
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchTimeline(String requestId) async {
    try {
      final rows = await _sb
          .from('mission_events')
          .select()
          .eq('request_id', requestId)
          .order('created_at', ascending: true);
      return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
