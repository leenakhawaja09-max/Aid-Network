import 'package:flutter/material.dart';

bool isMissingChatSchemaError(Object error) {
  final s = error.toString();
  if (!s.contains('PGRST205')) return false;
  return s.contains('conversations') || s.contains('chat_messages');
}

Widget buildChatSchemaMissingHint() {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.storage_outlined, size: 48, color: Colors.grey.shade600),
        const SizedBox(height: 16),
        const Text(
          'Chat database not set up',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        Text(
          'In the Supabase dashboard, open SQL Editor and run '
          'rapid_aid/supabase_schema_updates.sql from this project. '
          'That creates the conversations and chat_messages tables, RLS policies, '
          'and adds them to Realtime.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87, height: 1.4),
        ),
      ],
    ),
  );
}
