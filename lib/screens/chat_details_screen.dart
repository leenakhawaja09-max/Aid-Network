import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';
import '../services/wifi_voice_call.dart';
import '../utils/app_user.dart';
import '../utils/chat_schema_missing_hint.dart';

final _sb = Supabase.instance.client;

class ChatDetailsScreen extends StatefulWidget {
  final String peerName;
  final String peerUserId;

  const ChatDetailsScreen({
    super.key,
    required this.peerName,
    required this.peerUserId,
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _conversationId;
  bool _loading = true;
  String? _error;
  int _lastMessageCount = 0;
  bool _callOpening = false;
  String _headerName = 'Chat';

  @override
  void initState() {
    super.initState();
    final passed = widget.peerName.trim();
    if (passed.isNotEmpty && !labelLooksLikeUserId(passed)) {
      _headerName = passed;
    }
    _init();
  }

  Future<void> _init() async {
    try {
      if (widget.peerUserId.isNotEmpty) {
        final resolved = await displayNameForUser(widget.peerUserId);
        if (mounted) setState(() => _headerName = resolved);
      }
      final id = await ensureConversation(widget.peerUserId);
      if (mounted) {
        setState(() {
          _conversationId = id;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>>? _messagesStream() {
    final cid = _conversationId;
    if (cid == null) return null;
    return _sb.from('chat_messages').stream(primaryKey: ['id']).eq('conversation_id', cid).map((list) {
      final sorted = List<Map<String, dynamic>>.from(list);
      sorted.sort(
        (a, b) => (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? ''),
      );
      return sorted;
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !mounted) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final cid = _conversationId;
    final me = currentUserId();
    if (text.isEmpty || cid == null || me == null) return;

    try {
      await _sb.from('chat_messages').insert({
        'conversation_id': cid,
        'sender_id': me,
        'body': text,
      });
      await touchConversationLastMessage(conversationId: cid, preview: text);
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _onWifiCall() async {
    if (_callOpening) return;
    if (widget.peerUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Peer not available for call yet.')),
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wi‑Fi / data call'),
        content: const Text(
          'Opens a browser room (Jitsi Meet) that you and your partner both join — '
          'works on Wi‑Fi or mobile data. Ask them to tap Call in chat at the same time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open call')),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _callOpening = true);
    final ok = await startWifiVoiceCallWithPeer(widget.peerUserId);
    if (!mounted) return;
    setState(() => _callOpening = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the call link. Check browser permissions or try again on Wi‑Fi.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String _bubbleTime(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_headerName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_headerName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(_headerName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        actions: [
          if (_callOpening)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Voice / video (Wi‑Fi or data)',
              icon: const Icon(Icons.call_rounded),
              onPressed: _onWifiCall,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.18)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    Icon(Icons.wifi_rounded, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Messages update live. Use the call button for a browser voice/video room.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream(),
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
                  return Center(child: Text('Error: $err'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data ?? [];
                final me = currentUserId();

                if (messages.length != _lastMessageCount) {
                  final grew = messages.length > _lastMessageCount;
                  _lastMessageCount = messages.length;
                  if (grew) _scrollToBottom();
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet — say hi.',
                      style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message['sender_id']?.toString() == me;
                    return _buildBubble(
                      scheme: scheme,
                      textTheme: textTheme,
                      text: message['body']?.toString() ?? '',
                      isMe: isMe,
                      createdAt: message['created_at']?.toString(),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Material(
              elevation: 3,
              shadowColor: scheme.shadow.withValues(alpha: 0.12),
              color: scheme.surfaceContainerLowest,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Message…',
                        ).applyDefaults(Theme.of(context).inputDecorationTheme),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sendMessage,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Icon(Icons.send_rounded, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble({
    required ColorScheme scheme,
    required TextTheme textTheme,
    required String text,
    required bool isMe,
    String? createdAt,
  }) {
    final time = _bubbleTime(createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 4, top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: isMe ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 6),
                  bottomRight: Radius.circular(isMe ? 6 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                text,
                style: textTheme.bodyMedium?.copyWith(
                  color: isMe ? scheme.onPrimary : scheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
            if (time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: Text(
                  time,
                  style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
