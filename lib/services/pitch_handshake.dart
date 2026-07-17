import 'package:supabase_flutter/supabase_flutter.dart';

import 'mission_state_service.dart';

final _sb = Supabase.instance.client;
final _mission = MissionStateService();

/// Requester chose a helper: other pitches declined; mission not active until helper confirms.
Future<void> requesterSelectHelperPitch({
  required String pitchId,
  required String requestId,
}) async {
  await _sb
      .from('pitches')
      .update({'status': 'declined'})
      .eq('request_id', requestId)
      .eq('status', 'pending')
      .neq('id', pitchId);
  await _sb
      .from('pitches')
      .update({'status': 'declined'})
      .eq('request_id', requestId)
      .eq('status', 'awaiting_helper_ack')
      .neq('id', pitchId);
  await _sb.from('pitches').update({'status': 'awaiting_helper_ack'}).eq('id', pitchId);
  await _mission.onHelperSelected(requestId);
}

/// Helper confirms they will assist: mission goes live; locations may be shared in-app.
Future<void> helperAcknowledgePitch({
  required String pitchId,
  required String requestId,
  required String helperId,
}) async {
  final req = await _sb.from('requests').select('user_id').eq('id', requestId).maybeSingle();
  if (req == null) {
    throw Exception('Request not found');
  }
  final requesterId = req['user_id']?.toString() ?? '';
  if (requesterId.isEmpty) {
    throw Exception('Request has no owner — cannot start live mission');
  }

  await _sb
      .from('pitches')
      .update({'status': 'accepted'})
      .eq('id', pitchId)
      .eq('helper_id', helperId)
      .eq('status', 'awaiting_helper_ack');

  await _sb.from('requests').update({'status': 'accepted'}).eq('id', requestId);
  await _mission.onHelperAccepted(requestId);

  // Seed active_trips so requester realtime map works before first GPS tick.
  final prof = await _sb
      .from('profiles')
      .select('latitude,longitude')
      .eq('id', helperId)
      .maybeSingle();
  await _sb.from('active_trips').upsert({
    'request_id': requestId,
    'helper_id': helperId,
    'requester_id': requesterId,
    'helper_lat': prof?['latitude'],
    'helper_lng': prof?['longitude'],
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<String> helperDisplayName(String helperId) async {
  try {
    final prof = await _sb.from('profiles').select('full_name').eq('id', helperId).limit(1).maybeSingle();
    final n = prof?['full_name']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
  } catch (_) {}
  return 'Helper';
}
