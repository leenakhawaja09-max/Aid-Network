import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/helper_availability.dart';
import '../theme/app_colors.dart';

/// Live list of pitches for a request (requester only). Locations stay private until both parties confirm.
class IncomingPitchesPanel extends StatefulWidget {
  final String requestId;
  final String requestOwnerId;
  final Future<void> Function({
    required String pitchId,
    required String requestId,
    required String helperId,
  }) onAccept;
  final Future<void> Function(String pitchId) onDecline;

  const IncomingPitchesPanel({
    super.key,
    required this.requestId,
    required this.requestOwnerId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingPitchesPanel> createState() => _IncomingPitchesPanelState();
}

class _IncomingPitchesPanelState extends State<IncomingPitchesPanel> {
  final Map<String, Map<String, dynamic>> _profileCache = {};
  final Map<String, bool> _busyCache = {};
  List<Map<String, dynamic>>? _restRows;
  Timer? _pollTimer;
  String? _streamError;

  @override
  void initState() {
    super.initState();
    _pollPitches();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _pollPitches());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollPitches() async {
    try {
      final rows = await Supabase.instance.client
          .from('pitches')
          .select()
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _restRows = List<Map<String, dynamic>>.from(rows);
          _streamError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _streamError = e.toString());
    }
  }

  Future<void> _warmCaches(Set<String> helperIds) async {
    final sb = Supabase.instance.client;
    for (final id in helperIds) {
      if (id.isEmpty) continue;
      if (!_profileCache.containsKey(id)) {
        try {
          final row = await sb.from('profiles').select('id, full_name, skills, rating').eq('id', id).maybeSingle();
          if (row != null && mounted) {
            setState(() => _profileCache[id] = Map<String, dynamic>.from(row));
          }
        } catch (_) {}
      }
      if (!_busyCache.containsKey(id)) {
        final b = await isHelperBusy(id);
        if (mounted) setState(() => _busyCache[id] = b);
      }
    }
  }

  String _skillsLine(Map<String, dynamic>? prof) {
    if (prof == null) return '';
    final raw = prof['skills'];
    if (raw is! List) return '';
    final list = raw.map((e) => e.toString()).where((s) => s.isNotEmpty).take(4).toList();
    if (list.isEmpty) return '';
    return list.join(' · ');
  }

  List<Map<String, dynamic>> _filterRows(List<Map<String, dynamic>> raw) {
    return raw
        .where((p) {
          final st = p['status']?.toString() ?? '';
          return (st == 'pending' || st == 'awaiting_helper_ack') &&
              p['helper_id']?.toString() != widget.requestOwnerId;
        })
        .toList()
      ..sort((a, b) {
        final ta = a['created_at']?.toString() ?? '';
        final tb = b['created_at']?.toString() ?? '';
        return tb.compareTo(ta);
      });
  }

  Widget _buildPitchList(BuildContext context, List<Map<String, dynamic>> rows) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ids = rows.map((p) => p['helper_id']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _warmCaches(ids);
    });

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No incoming pitches yet — helpers can tap I Can Help on the map.',
          style: textTheme.bodySmall?.copyWith(height: 1.35),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Helper pitches (${rows.length})',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a helper below. Locations stay private until they confirm.',
          style: textTheme.labelSmall?.copyWith(height: 1.25),
        ),
        const SizedBox(height: 10),
        ...rows.map((p) {
          final pid = p['id']?.toString() ?? '';
          final hid = p['helper_id']?.toString() ?? '';
          final msg = p['pitch_message']?.toString() ?? '';
          final st = p['status']?.toString() ?? '';
          final awaiting = st == 'awaiting_helper_ack';
          final prof = _profileCache[hid];
          final name = prof?['full_name']?.toString().trim().isNotEmpty == true
              ? prof!['full_name'].toString()
              : 'Helper';
          final skills = _skillsLine(prof);
          final rating = prof?['rating'];
          final ratingLabel = rating is num ? '${rating.toStringAsFixed(1)} ★' : null;
          final busy = _busyCache[hid] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.pitchCardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.pitchCardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (busy)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.busyChipFill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Busy',
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.busyChipText,
                          ),
                        ),
                      ),
                  ],
                ),
                if (ratingLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(ratingLabel, style: textTheme.labelSmall),
                ],
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(skills, style: textTheme.labelSmall?.copyWith(height: 1.3)),
                ],
                const SizedBox(height: 8),
                Text(msg, style: textTheme.bodyMedium?.copyWith(height: 1.35)),
                if (awaiting) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.waitingBannerFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.hourglass_top_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You chose this helper — waiting for them to confirm before sharing locations.',
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.waitingBannerText,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!awaiting) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pid.isEmpty ? null : () => widget.onDecline(pid),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: pid.isEmpty || hid.isEmpty || busy
                              ? null
                              : () => widget.onAccept(pitchId: pid, requestId: widget.requestId, helperId: hid),
                          child: const Text('Choose helper'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.from('pitches').stream(primaryKey: ['id']).eq('request_id', widget.requestId),
      builder: (context, snap) {
        if (snap.hasError) {
          _streamError ??= snap.error.toString();
          final fallback = _restRows;
          if (fallback != null) {
            return _buildPitchList(context, _filterRows(fallback));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not load pitches live. Retrying…\n$_streamError',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
              ),
              TextButton(onPressed: _pollPitches, child: const Text('Retry')),
            ],
          );
        }
        if (!snap.hasData) {
          final fallback = _restRows;
          if (fallback != null) {
            return _buildPitchList(context, _filterRows(fallback));
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        return _buildPitchList(context, _filterRows(List<Map<String, dynamic>>.from(snap.data!)));
      },
    );
  }
}
