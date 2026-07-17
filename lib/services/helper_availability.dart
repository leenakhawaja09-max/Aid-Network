import 'package:supabase_flutter/supabase_flutter.dart';

/// True if this helper already has an accepted mission that is still in progress.
Future<bool> isHelperBusy(String helperId) async {
  if (helperId.isEmpty) return false;
  final client = Supabase.instance.client;
  try {
    final rows = await client
        .from('pitches')
        .select('request_id')
        .eq('helper_id', helperId)
        .eq('status', 'accepted') as List<dynamic>;
    for (final row in rows) {
      final m = Map<String, dynamic>.from(row as Map);
      final rid = m['request_id']?.toString();
      if (rid == null || rid.isEmpty) continue;
      final req = await client.from('requests').select('status').eq('id', rid).maybeSingle();
      final s = req?['status']?.toString().toLowerCase() ?? '';
      if (s == 'in-progress' ||
          s == 'in_progress' ||
          s == 'accepted' ||
          s == 'arriving') {
        return true;
      }
    }
  } catch (_) {
    return false;
  }
  return false;
}
