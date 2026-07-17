import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_service.dart';

/// Opens a **shared** Jitsi Meet room in the browser so helper and requester can
/// talk over **Wi‑Fi or mobile data** (no phone number; both must join the same room).
///
/// Room id is derived from the Supabase [conversations] row so both parties land
/// in one place after `ensureConversation` creates the same id for the pair.
Future<bool> startWifiVoiceCallWithPeer(String peerUserId) async {
  final cid = await ensureConversation(peerUserId);
  final room = 'rapidaid_${cid.replaceAll('-', '').toLowerCase()}';
  final uri = Uri.parse('https://meet.jit.si/$room');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) debugPrint('wifi_voice_call: launchUrl returned false');
    return ok;
  } catch (e, st) {
    debugPrint('wifi_voice_call: $e\n$st');
    return false;
  }
}
