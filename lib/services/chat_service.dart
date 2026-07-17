import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_user.dart';

final _sb = Supabase.instance.client;

/// Ordered pair key for [conversations] (participant_a < participant_b).
(String, String) orderedParticipants(String userA, String userB) {
  return userA.compareTo(userB) < 0 ? (userA, userB) : (userB, userA);
}

Future<String> ensureConversation(String peerId) async {
  final me = currentUserId();
  if (me == null) throw StateError('Not signed in');
  final (a, b) = orderedParticipants(me, peerId);

  final existing = await _sb
      .from('conversations')
      .select('id')
      .eq('participant_a', a)
      .eq('participant_b', b)
      .maybeSingle();
  if (existing != null && existing['id'] != null) {
    return existing['id'].toString();
  }

  try {
    final inserted = await _sb.from('conversations').insert({
      'participant_a': a,
      'participant_b': b,
    }).select('id').single();
    return inserted['id'].toString();
  } catch (_) {
    final again = await _sb
        .from('conversations')
        .select('id')
        .eq('participant_a', a)
        .eq('participant_b', b)
        .single();
    return again['id'].toString();
  }
}

Future<void> touchConversationLastMessage({
  required String conversationId,
  required String preview,
}) async {
  await _sb.from('conversations').update({
    'last_message': preview,
    'last_message_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', conversationId);
}

/// Human-readable label from [profiles.full_name], never the raw user id.
Future<String> displayNameForUser(String userId) async {
  final id = userId.trim();
  if (id.isEmpty) return 'Chat';
  final names = await displayNamesForUsers([id]);
  return names[id] ?? 'Community member';
}

/// Batch-resolve display names for chat list / headers.
Future<Map<String, String>> displayNamesForUsers(Iterable<String> userIds) async {
  final ids = userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  if (ids.isEmpty) return {};

  final out = <String, String>{};
  try {
    final rows = await _sb.from('profiles').select('id, full_name').inFilter('id', ids.toList());
    for (final raw in rows as List) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id']?.toString() ?? '';
      final name = m['full_name']?.toString().trim();
      if (id.isNotEmpty && name != null && name.isNotEmpty) {
        out[id] = name;
      }
    }
  } catch (_) {}

  for (final id in ids) {
    out.putIfAbsent(id, () => 'Community member');
  }
  return out;
}

/// True when [label] is probably a UUID / id, not a real name from the caller.
bool labelLooksLikeUserId(String label) {
  final t = label.trim();
  if (t.isEmpty) return true;
  if (t.contains(' ')) return false;
  if (t.length >= 32) return true;
  return RegExp(r'^[0-9a-f-]{8,}$', caseSensitive: false).hasMatch(t);
}
