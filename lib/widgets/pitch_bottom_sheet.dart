import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/helper_availability.dart';
import '../services/mission_state_service.dart';
import '../utils/app_user.dart';

/// Bottom sheet for helpers to submit a pitch for a community request.
class PitchBottomSheet extends StatefulWidget {
  final String requestId;
  final String requestOwnerId;

  const PitchBottomSheet({
    super.key,
    required this.requestId,
    required this.requestOwnerId,
  });

  static Future<void> show(
    BuildContext context, {
    required String requestId,
    required String requestOwnerId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PitchBottomSheet(
        requestId: requestId,
        requestOwnerId: requestOwnerId,
      ),
    );
  }

  @override
  State<PitchBottomSheet> createState() => _PitchBottomSheetState();
}

class _PitchBottomSheetState extends State<PitchBottomSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a short pitch.')),
      );
      return;
    }
    final uid = currentUserId();
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to help.')),
      );
      return;
    }
    if (widget.requestOwnerId.isNotEmpty && uid == widget.requestOwnerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot pitch your own request.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (await isHelperBusy(uid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You already have an active assistance in progress. Finish or cancel it before pitching again.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await Supabase.instance.client.from('pitches').insert({
        'request_id': widget.requestId,
        'helper_id': uid,
        'pitch_message': text,
        'status': 'pending',
      });
      await MissionStateService().onFirstPitch(widget.requestId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your pitch was sent. Your exact location stays private until you confirm you will assist.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send pitch: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Text(
              'I Can Help',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Describe how you can help (skills, tools, ETA). Your map location is only shared after you and the requester both agree to cooperate.',
              style: textTheme.bodySmall?.copyWith(height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. I have a car and can reach you in 5 minutes.',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Text('Send pitch'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
