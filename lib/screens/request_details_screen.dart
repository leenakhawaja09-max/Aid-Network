import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/pitch_handshake.dart';
import '../utils/app_user.dart';

import '../widgets/incoming_pitches_panel.dart';
import '../widgets/pitch_bottom_sheet.dart';

final _sb = Supabase.instance.client;

class RequestDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? request;
  final String? title;
  final String? category;

  /// When true (e.g. opened from **My Requests**), treat as the requester's own
  /// request so "I Can Help" is never shown even if `user_id` is missing in data.
  final bool openedAsRequestOwner;

  const RequestDetailsScreen({
    super.key,
    this.request,
    this.title,
    this.category,
    this.openedAsRequestOwner = false,
  });

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  Future<void> _declinePitch(String pitchId) async {
    try {
      await _sb.from('pitches').update({'status': 'declined'}).eq('id', pitchId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pitch declined'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _acceptPitch({
    required String pitchId,
    required String requestId,
    required String helperId,
  }) async {
    try {
      await requesterSelectHelperPitch(pitchId: pitchId, requestId: requestId);
      final helperName = await helperDisplayName(helperId);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$helperName will be notified. Live map opens after they confirm they can assist.',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accept failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = currentUserId();
    final req = widget.request;
    final displayTitle = req != null
        ? (req['title']?.toString() ?? widget.title ?? 'Request')
        : (widget.title ?? 'Request');
    final displayDescription = req != null
        ? (req['description']?.toString() ?? '')
        : 'Need help details...';
    final ownerRaw = req?['user_id']?.toString();
    final ownerId = (ownerRaw != null && ownerRaw.isNotEmpty) ? ownerRaw : null;
    final isOwner = widget.openedAsRequestOwner ||
        (currentUid != null && ownerId != null && ownerId == currentUid);
    final requestId = req?['id']?.toString();
    final canPitch = req != null && !isOwner && requestId != null && ownerId != null;

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Request Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOwner ? 'YOUR REQUEST' : 'OPEN REQUEST',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              displayTitle,
              style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              displayDescription,
              style: textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 25),
            Text(
              'Location',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Icon(Icons.map_outlined, color: scheme.onSurfaceVariant, size: 40),
              ),
            ),
            if (isOwner && requestId != null) ...[
              const SizedBox(height: 28),
              const Text(
                'Helpers pitching you',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              IncomingPitchesPanel(
                requestId: requestId,
                requestOwnerId: ownerId ?? currentUid ?? '',
                onAccept: _acceptPitch,
                onDecline: _declinePitch,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: canPitch
          ? Padding(
              padding: const EdgeInsets.all(12.0),
              child: FilledButton(
                onPressed: () => PitchBottomSheet.show(
                  context,
                  requestId: requestId,
                  requestOwnerId: ownerId,
                ),
                child: const Text('I Can Help'),
              ),
            )
          : null,
    );
  }
}
