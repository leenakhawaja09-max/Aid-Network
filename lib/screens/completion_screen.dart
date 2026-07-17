import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/mission_state_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_user.dart';

class CompletionScreen extends StatefulWidget {
  final String personName;
  final bool wasHelper;
  final VoidCallback? onComplete;
  /// When set (e.g. from live tracking), marks the request completed in Supabase.
  final String? requestId;
  /// User id of the person being rated (partner).
  final String? revieweeUserId;

  const CompletionScreen({
    super.key,
    required this.personName,
    required this.wasHelper,
    this.onComplete,
    this.requestId,
    this.revieweeUserId,
  });

  @override
  State<CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends State<CompletionScreen> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _finishing = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _persistFeedbackIfNeeded(String requestId) async {
    final me = currentUserId();
    final peer = widget.revieweeUserId?.trim();
    if (me == null || peer == null || peer.isEmpty || _rating <= 0) return;
    final client = Supabase.instance.client;
    try {
      await client.from('mission_feedback').insert({
        'request_id': requestId,
        'reviewer_id': me,
        'reviewee_id': peer,
        'stars': _rating,
        'comment': _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      });
    } catch (_) {
      // Table may not exist yet, or duplicate review — ignore for UX continuity.
    }
    try {
      final rows =
          await client.from('mission_feedback').select('stars').eq('reviewee_id', peer) as List<dynamic>;
      if (rows.isEmpty) return;
      var sum = 0.0;
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r as Map);
        final s = m['stars'];
        if (s is num) sum += s.toDouble();
      }
      final avg = sum / rows.length;
      await client.from('profiles').update({'rating': avg}).eq('id', peer);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('Mission complete')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded, color: scheme.secondary, size: 88),
              ),
              const SizedBox(height: 24),
              Text(
                widget.wasHelper ? 'Mission accomplished' : 'Help received',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Experience with ${widget.personName}',
                style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 36),
              Text(
                'Rate the experience',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final filled = index < _rating;
                  return IconButton(
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? scheme.star : scheme.outlineVariant,
                      size: 42,
                    ),
                    onPressed: () => setState(() => _rating = index + 1),
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add a comment (optional)',
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _finishing
                      ? null
                      : () async {
                          final rid = widget.requestId?.trim();
                          if (rid != null && rid.isNotEmpty) {
                            setState(() => _finishing = true);
                            try {
                              await _persistFeedbackIfNeeded(rid);
                              final reward = await MissionStateService().onMissionCompleted(rid);
                              if (!context.mounted) return;
                              if (widget.wasHelper) {
                                if (reward?['ok'] == true && reward?['already_rewarded'] != true) {
                                  final karma = reward?['karma_points'];
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Nice work! +1 help'
                                        '${karma != null ? ', $karma karma total' : ''}.',
                                      ),
                                      backgroundColor: scheme.secondary,
                                    ),
                                  );
                                } else if (reward?['ok'] != true) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        reward?['reason'] == 'run_supabase_helper_rewards_sql'
                                            ? 'Rewards need the Supabase helper rewards script. Ask your admin to run supabase_helper_rewards.sql, then finish again.'
                                            : 'Could not update help/karma (${reward?['reason'] ?? 'unknown'}).',
                                      ),
                                      backgroundColor: scheme.error,
                                      duration: const Duration(seconds: 6),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not mark request completed: $e'),
                                  backgroundColor: scheme.error,
                                ),
                              );
                              setState(() => _finishing = false);
                              return;
                            }
                          }

                          widget.onComplete?.call();

                          if (!context.mounted) return;
                          final hasRequest = widget.requestId != null && widget.requestId!.trim().isNotEmpty;
                          if (hasRequest) {
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  child: _finishing
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: scheme.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Finish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
