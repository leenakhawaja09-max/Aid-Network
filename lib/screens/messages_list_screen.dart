import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';
import '../widgets/app_ui.dart';
import '../utils/app_user.dart';
import '../utils/chat_schema_missing_hint.dart';
import 'chat_details_screen.dart';

final _sb = Supabase.instance.client;

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  Map<String, String> _peerNames = {};
  Set<String> _namesLoadedFor = {};

  Stream<List<Map<String, dynamic>>> _conversationsStream() {
    final uid = currentUserId();
    if (uid == null) return const Stream.empty();

    return _sb.from('conversations').stream(primaryKey: ['id']).map((rows) {
      return rows
          .where((r) =>
              r['participant_a']?.toString() == uid ||
              r['participant_b']?.toString() == uid)
          .toList()
        ..sort((a, b) {
          final ta = a['last_message_at']?.toString() ?? '';
          final tb = b['last_message_at']?.toString() ?? '';
          return tb.compareTo(ta);
        });
    });
  }

  String _peerId(Map<String, dynamic> row, String myId) {
    final a = row['participant_a']?.toString();
    final b = row['participant_b']?.toString();
    return a == myId ? (b ?? '') : (a ?? '');
  }

  void _loadPeerNames(List<Map<String, dynamic>> chats, String myId) {
    final peerIds = chats.map((c) => _peerId(c, myId)).where((id) => id.isNotEmpty).toSet();
    if (peerIds.isEmpty || peerIds.difference(_namesLoadedFor).isEmpty) return;

    final toFetch = peerIds.difference(_namesLoadedFor);
    _namesLoadedFor = {..._namesLoadedFor, ...toFetch};

    displayNamesForUsers(toFetch).then((names) {
      if (!mounted) return;
      setState(() => _peerNames = {..._peerNames, ...names});
    });
  }

  String _displayNameForPeer(String peerId) {
    if (peerId.isEmpty) return 'Chat';
    return _peerNames[peerId] ?? '…';
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (now.difference(date).inDays == 1) return 'Yesterday';
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = currentUserId();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          'Messages',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        automaticallyImplyLeading: false,
      ),
      body: uid == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sign in to view messages.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: _conversationsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final err = snapshot.error!;
                  if (isMissingChatSchemaError(err)) {
                    return Center(
                      child: SingleChildScrollView(
                        child: buildChatSchemaMissingHint(),
                      ),
                    );
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error: $err',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: scheme.primary));
                }
                final chats = snapshot.data ?? [];
                _loadPeerNames(chats, uid);

                if (chats.isEmpty) {
                  return AppUi.emptyState(
                    context: context,
                    icon: Icons.forum_outlined,
                    title: 'No conversations yet',
                    message:
                        'Open chat from Live Tracking after you connect with a helper or requester.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: chats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final peerId = _peerId(chat, uid);
                    final name = _displayNameForPeer(peerId);
                    final preview = chat['last_message']?.toString() ?? 'No messages yet';
                    final time = _formatTime(chat['last_message_at']?.toString());
                    final initial = name.isNotEmpty && name != '…' ? name[0].toUpperCase() : '?';

                    return Material(
                      color: scheme.surfaceContainerLowest,
                      elevation: 1,
                      shadowColor: scheme.shadow.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatDetailsScreen(
                                peerName: name == '…' ? '' : name,
                                peerUserId: peerId,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: scheme.primaryContainer.withValues(alpha: 0.7),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (time.isNotEmpty)
                                Text(
                                  time,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
