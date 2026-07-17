import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/nominatim_geocode.dart';
import '../services/pitch_handshake.dart';
import '../utils/app_user.dart';
import '../utils/request_expiry.dart';
import '../utils/geo_utils.dart';

import 'completion_screen.dart';
import 'create_request_screen.dart';
import 'request_details_screen.dart';
import 'requests_live_feed.dart';
import '../widgets/app_ui.dart';
import '../widgets/incoming_pitches_panel.dart';

final _sb = Supabase.instance.client;

class RequestsScreen extends StatefulWidget {
  /// (missionType, arg2, arg3) — for new requests: category, description, distance.
  /// For receiving: helperName, requestId. For assisting: requesterName, requestId.
  final Function(String, String, String) onActionAccepted;
  final List<Map<String, dynamic>> userRequests;

  const RequestsScreen({
    super.key,
    required this.onActionAccepted,
    required this.userRequests,
  });

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool isMyRequests = true;
  StreamSubscription<List<Map<String, dynamic>>>? _myPitchSub;
  final Set<String> _notifiedAcceptedPitch = {};
  final Set<String> _notifiedPendingPitch = {};

  @override
  void initState() {
    super.initState();
    _subscribePitchNotifications();
  }

  @override
  void dispose() {
    _myPitchSub?.cancel();
    super.dispose();
  }

  void _subscribePitchNotifications() {
    final uid = currentUserId();
    if (uid == null) return;
    _myPitchSub = _sb.from('pitches').stream(primaryKey: ['id']).listen((rows) async {
      final mine = <String>{};
      for (final r in widget.userRequests) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) mine.add(id);
      }
      for (final p in rows) {
        final st = p['status']?.toString() ?? '';
        if (st == 'pending') {
          final pid = p['id']?.toString();
          final rid = p['request_id']?.toString();
          if (pid != null &&
              rid != null &&
              mine.contains(rid) &&
              !_notifiedPendingPitch.contains(pid) &&
              mounted) {
            _notifiedPendingPitch.add(pid);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('New helper pitch — see it under your active request below.'),
                backgroundColor: Theme.of(context).colorScheme.primary,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
        if (st != 'accepted') continue;
        final pid = p['id']?.toString();
        final rid = p['request_id']?.toString();
        if (pid == null || rid == null) continue;
        if (!mine.contains(rid)) continue;
        if (_notifiedAcceptedPitch.contains(pid)) continue;
        try {
          final req = await _sb.from('requests').select('user_id,status').eq('id', rid).maybeSingle();
          if (req?['user_id']?.toString() != uid) continue;
          final st = req?['status']?.toString().toLowerCase() ?? '';
          if (st != 'in-progress' &&
              st != 'in_progress' &&
              st != 'accepted' &&
              st != 'helper_selected' &&
              st != 'arriving') {
            continue;
          }
        } catch (_) {
          continue;
        }
        _notifiedAcceptedPitch.add(pid);
        final hid = p['helper_id']?.toString() ?? '';
        final hname = await helperDisplayName(hid);
        if (!mounted) return;
        widget.onActionAccepted('receiving', hname, rid);
      }
    });
  }

  /// Open missions for the requester (includes created/pending/pitched so pitches show).
  bool _isActiveRequest(Map<String, dynamic> r) {
    if (_isCompletedRequest(r)) return false;
    if (isRequestExpired(r)) return false;
    final s = r['status']?.toString().toLowerCase() ?? '';
    return s == 'open' ||
        s == 'urgent' ||
        s == 'active' ||
        s == 'created' ||
        s == 'pending' ||
        s == 'pitched' ||
        s == 'helper_selected' ||
        s == 'accepted' ||
        s == 'in-progress' ||
        s == 'in_progress' ||
        s == 'arriving';
  }

  bool _isCompletedRequest(Map<String, dynamic> r) {
    final s = r['status']?.toString().toLowerCase() ?? '';
    return s == 'completed' ||
        s == 'closed' ||
        s == 'cancelled' ||
        s == 'canceled' ||
        s == 'fulfilled' ||
        s == 'resolved';
  }

  Future<Map<String, Map<String, dynamic>>> _fetchRequestsByIds(List<String> ids) async {
    final unique = ids.toSet().where((e) => e.isNotEmpty).toList();
    if (unique.isEmpty) return {};
    final entries = await Future.wait(
      unique.map((id) async {
        try {
          final row = await _sb
              .from('requests')
              .select('id,title,category,status,distance,description,created_at,latitude,longitude')
              .eq('id', id)
              .maybeSingle();
          if (row == null) return null;
          return MapEntry(id, Map<String, dynamic>.from(row));
        } catch (_) {
          return null;
        }
      }),
    );
    return Map.fromEntries(entries.whereType<MapEntry<String, Map<String, dynamic>>>());
  }

  Future<Map<String, String?>> _helperInfoForCompletedRequest(String requestId) async {
    try {
      final pitch = await _sb
          .from('pitches')
          .select('helper_id')
          .eq('request_id', requestId)
          .eq('status', 'accepted')
          .limit(1)
          .maybeSingle();
      if (pitch == null) return {};
      final hid = pitch['helper_id']?.toString();
      if (hid == null || hid.isEmpty) return {};
      final prof = await _sb.from('profiles').select('full_name').eq('id', hid).maybeSingle();
      final n = prof?['full_name']?.toString().trim();
      return {
        'id': hid,
        'name': (n != null && n.isNotEmpty) ? n : 'Helper',
      };
    } catch (_) {
      return {};
    }
  }

  Future<String?> _helperNameForCompletedRequest(String requestId) async {
    final m = await _helperInfoForCompletedRequest(requestId);
    return m['name'];
  }

  String _formatCreatedLabel(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final now = DateTime.now();
    if (now.difference(d).inDays == 0) return 'Today';
    if (now.difference(d).inDays == 1) return 'Yesterday';
    return '${d.month}/${d.day}/${d.year}';
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You chose $helperName. You’ll get a notification when they confirm — then open Live Tracking.',
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

  Future<void> _helperConfirmAssist({
    required String pitchId,
    required String requestId,
  }) async {
    final uid = currentUserId();
    if (uid == null) return;
    try {
      await helperAcknowledgePitch(pitchId: pitchId, requestId: requestId, helperId: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You confirmed — opening live tracking when the feed updates.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          'My Requests',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      floatingActionButton: isMyRequests
          ? FloatingActionButton.large(
              heroTag: 'requests_create_fab',
              tooltip: 'Create new request',
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              elevation: 8,
              highlightElevation: 12,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: scheme.surfaceContainerLowest, width: 3),
              ),
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => CreateRequestSheet(
                    onActionAccepted: (_, __, ___) {},
                  ),
                );
              },
              child: const Icon(Icons.add_rounded, size: 36),
            )
          : null,
      floatingActionButtonLocation: const FabAboveBottomNavLocation(),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, isMyRequests ? 128 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  _buildTabButton(context, 'My Requests', isMyRequests, () {
                    setState(() => isMyRequests = true);
                  }),
                  _buildTabButton(context, "I'm Helping", !isMyRequests, () {
                    setState(() => isMyRequests = false);
                  }),
                ],
              ),
            ),
            const SizedBox(height: 25),
            if (isMyRequests) _buildMyRequestsContent() else _buildImHelpingContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(BuildContext context, String label, bool isActive, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? scheme.surfaceContainerLowest : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? scheme.primary.withValues(alpha: 0.35) : Colors.transparent,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.2,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyRequestsContent() {
    final active = widget.userRequests.where(_isActiveRequest).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.access_time_rounded, 'Active requests'),
        const SizedBox(height: 12),
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: RequestsLiveFeedWidget(),
          )
        else
          ...active.map((req) {
            final title = req['title']?.toString() ?? 'Request';
            final category = req['category']?.toString() ?? 'General';
            final dist = req['distance']?.toString() ?? '—';
            final rid = req['id']?.toString();
            final statusLower = req['status']?.toString().toLowerCase() ?? '';
            final isUrgent =
                statusLower == 'urgent' || category == 'Medical' || category == 'Safety';
            final lat = readCoord(req['latitude']);
            final lng = readCoord(req['longitude']);
            final desc = req['description']?.toString().trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRequestCard(
                    context,
                    title: title,
                    category: category,
                    dist: dist,
                    statusLabel: req['status']?.toString() ?? '—',
                    timeLabel: 'Details',
                    isUrgent: isUrgent,
                    locationLat: lat,
                    locationLng: lng,
                    descriptionSnippet: (desc != null && desc.isNotEmpty) ? desc : null,
                    onView: () async {
                      final result = await Navigator.push<dynamic>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestDetailsScreen(
                            request: req,
                            title: title,
                            category: category,
                            openedAsRequestOwner: true,
                          ),
                        ),
                      );
                      if (!mounted) return;
                      if (result is Map) {
                        final m = Map<String, dynamic>.from(result);
                        if (m['type']?.toString() == 'receiving') {
                          widget.onActionAccepted(
                            'receiving',
                            m['helperName']?.toString() ?? 'Helper',
                            m['requestId']?.toString() ?? '',
                          );
                        }
                      } else if (result is String) {
                        widget.onActionAccepted(result, '', '');
                      }
                    },
                  ),
                  if (rid != null)
                    IncomingPitchesPanel(
                      requestId: rid,
                      requestOwnerId: req['user_id']?.toString().isNotEmpty == true
                          ? req['user_id'].toString()
                          : (currentUserId() ?? ''),
                      onAccept: _acceptPitch,
                      onDecline: _declinePitch,
                    ),
                ],
              ),
            );
          }),
        const SizedBox(height: 28),
        _buildSectionHeader(context, Icons.check_circle_outline_rounded, 'Recently completed'),
        const SizedBox(height: 12),
        ..._buildCompletedRequestsSection(context),
      ],
    );
  }

  List<Widget> _buildCompletedRequestsSection(BuildContext context) {
    final completed = widget.userRequests.where(_isCompletedRequest).toList()
      ..sort((a, b) {
        final ta = a['created_at']?.toString() ?? '';
        final tb = b['created_at']?.toString() ?? '';
        return tb.compareTo(ta);
      });

    if (completed.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Completed missions appear here after you tap COMPLETE MISSION in Live Tracking.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ];
    }

    return completed
        .take(15)
        .map((req) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCompletedRequestCard(context, req),
            ))
        .toList();
  }

  Widget _buildCompletedRequestCard(BuildContext context, Map<String, dynamic> req) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rid = req['id']?.toString() ?? '';
    final title = req['title']?.toString() ?? 'Request';
    final category = req['category']?.toString() ?? 'General';
    final dateLabel = _formatCreatedLabel(req['created_at']?.toString());
    final status = req['status']?.toString() ?? '—';

    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.secondary.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  category,
                  style: textTheme.labelLarge?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  dateLabel.isEmpty ? status : dateLabel,
                  style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(status, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (rid.isNotEmpty)
              FutureBuilder<String?>(
                future: _helperNameForCompletedRequest(rid),
                builder: (context, snap) {
                  final h = snap.data;
                  if (h == null || h.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.volunteer_activism_outlined, color: scheme.secondary, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Helper: $h',
                            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: rid.isEmpty
                      ? null
                      : () async {
                          final info = await _helperInfoForCompletedRequest(rid);
                          final name = info['name'] ?? 'Helper';
                          final hid = info['id'];
                          if (!context.mounted) return;
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => CompletionScreen(
                                personName: name,
                                wasHelper: false,
                                requestId: rid,
                                revieweeUserId: hid,
                                onComplete: () {},
                              ),
                            ),
                          );
                        },
                  child: Text('Rate experience', style: TextStyle(color: scheme.secondary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImHelpingContent() {
    final uid = currentUserId();
    if (uid == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sign in to see help you are giving.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.volunteer_activism_rounded, "You're fulfilling"),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _sb.from('pitches').stream(primaryKey: ['id']).eq('helper_id', uid),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load your pitches. ${snap.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final allPitches = List<Map<String, dynamic>>.from(snap.data!);
            final allRids = allPitches
                .map((p) => p['request_id']?.toString())
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              key: ValueKey(allRids.join(',')),
              future: _fetchRequestsByIds(allRids),
              builder: (context, reqSnap) {
                if (reqSnap.connectionState == ConnectionState.waiting && !reqSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final reqMap = reqSnap.data ?? {};

                final accepted = allPitches.where((p) => p['status']?.toString() == 'accepted').toList();
                final awaitingAck = allPitches.where((p) => p['status']?.toString() == 'awaiting_helper_ack').toList();
                final activeMissions = accepted.where((p) {
                  final id = p['request_id']?.toString() ?? '';
                  final rs = reqMap[id]?['status']?.toString().toLowerCase() ?? '';
                  return rs == 'in-progress' ||
                      rs == 'in_progress' ||
                      rs == 'accepted' ||
                      rs == 'helper_selected' ||
                      rs == 'arriving';
                }).toList();

                final history = allPitches.where((p) {
                  final ps = p['status']?.toString() ?? '';
                  if (ps == 'declined') return true;
                  if (ps == 'accepted') {
                    final id = p['request_id']?.toString() ?? '';
                    final rs = reqMap[id]?['status']?.toString().toLowerCase() ?? '';
                    return rs == 'completed' ||
                        rs == 'closed' ||
                        rs == 'cancelled' ||
                        rs == 'canceled' ||
                        rs == 'fulfilled';
                  }
                  return false;
                }).toList()
                  ..sort((a, b) {
                    final ta = a['created_at']?.toString() ?? '';
                    final tb = b['created_at']?.toString() ?? '';
                    return tb.compareTo(ta);
                  });

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (awaitingAck.isNotEmpty) ...[
                      _buildSectionHeader(
                        context,
                        Icons.verified_user_outlined,
                        'Confirm to share your location',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A requester chose you. Confirm only if you can assist — then both sides can see live locations in Tracking.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...awaitingAck.map((p) {
                        final pid = p['id']?.toString() ?? '';
                        final rid = p['request_id']?.toString() ?? '';
                        final req = rid.isNotEmpty ? reqMap[rid] : null;
                        final title = req?['title']?.toString() ?? 'Help request';
                        final category = req?['category']?.toString() ?? 'General';
                        final dist = req?['distance']?.toString() ?? '—';
                        final desc = req?['description']?.toString().trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildRequestCard(
                            context,
                            title: title,
                            category: category,
                            dist: dist,
                            statusLabel: 'Awaiting your confirmation',
                            timeLabel: 'Action needed',
                            isHelper: true,
                            isUrgent: false,
                            locationLat: null,
                            locationLng: null,
                            descriptionSnippet: (desc != null && desc.isNotEmpty) ? desc : null,
                            onView: () {},
                            customActions: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.straighten_rounded,
                                      size: 16,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        dist,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                FilledButton(
                                  onPressed: () => _helperConfirmAssist(pitchId: pid, requestId: rid),
                                  child: const Text('Confirm I will assist'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                    ],
                    if (activeMissions.isEmpty && awaitingAck.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Center(
                          child: Text(
                            'No confirmations needed and no active missions. When a requester chooses you, confirm here before tracking goes live.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      )
                    else if (activeMissions.isNotEmpty)
                      ...activeMissions.map((p) {
                        final rid = p['request_id']?.toString() ?? '';
                        final req = reqMap[rid];
                        final title = req?['title']?.toString() ?? 'Help request';
                        final category = req?['category']?.toString() ?? 'General';
                        final dist = req?['distance']?.toString() ?? '—';
                        final lat = readCoord(req?['latitude']);
                        final lng = readCoord(req?['longitude']);
                        final desc = req?['description']?.toString().trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildRequestCard(
                            context,
                            title: title,
                            category: category,
                            dist: dist,
                            statusLabel: req?['status']?.toString() ?? 'In progress',
                            timeLabel: 'Live',
                            isHelper: true,
                            isUrgent: false,
                            locationLat: lat,
                            locationLng: lng,
                            descriptionSnippet: (desc != null && desc.isNotEmpty) ? desc : null,
                            onView: () => widget.onActionAccepted('assisting', 'Requester', rid),
                          ),
                        );
                      }),
                    const SizedBox(height: 28),
                    _buildSectionHeader(context, Icons.history_rounded, 'History'),
                    const SizedBox(height: 12),
                    if (history.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: Text(
                            'No declined or completed pitches yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      ...history.take(20).map((p) => _buildPitchHistoryTile(context, p, reqMap)),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildPitchHistoryTile(
    BuildContext context,
    Map<String, dynamic> pitch,
    Map<String, Map<String, dynamic>> reqMap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rid = pitch['request_id']?.toString() ?? '';
    final req = rid.isNotEmpty ? reqMap[rid] : null;
    final title = req?['title']?.toString() ?? (rid.isNotEmpty ? 'Request' : 'Pitch');
    final ps = pitch['status']?.toString() ?? '';
    final rs = req?['status']?.toString().toLowerCase() ?? '';
    String line;
    if (ps == 'declined') {
      line = 'Pitch declined';
    } else if (rs == 'completed' || rs == 'fulfilled') {
      line = 'Mission completed';
    } else {
      line = 'Closed';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            line,
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          trailing: req != null ? const Icon(Icons.chevron_right_rounded) : null,
          onTap: req != null
              ? () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RequestDetailsScreen(request: req),
                    ),
                  );
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(
    BuildContext context, {
    required String title,
    required String category,
    required String dist,
    required String statusLabel,
    required String timeLabel,
    required VoidCallback onView,
    bool isHelper = false,
    bool isUrgent = false,
    double? locationLat,
    double? locationLng,
    String? descriptionSnippet,
    Widget? customActions,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chipBg = isUrgent
        ? scheme.errorContainer.withValues(alpha: 0.55)
        : scheme.primaryContainer.withValues(alpha: 0.45);
    final chipFg = isUrgent ? scheme.error : scheme.primary;

    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isUrgent ? scheme.error.withValues(alpha: 0.35) : scheme.outlineVariant.withValues(alpha: 0.45),
          width: isUrgent ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: customActions == null ? onView : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: chipFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  timeLabel,
                  style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (descriptionSnippet != null && descriptionSnippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                descriptionSnippet.length > 100 ? '${descriptionSnippet.substring(0, 100)}…' : descriptionSnippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
              ),
            ],
            if (locationLat != null && locationLng != null) ...[
              const SizedBox(height: 8),
              _ReverseAddressRow(latitude: locationLat, longitude: locationLng),
            ],
            const SizedBox(height: 12),
            customActions ??
                Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.straighten_rounded, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  dist,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                isHelper
                    ? FilledButton.tonal(
                        onPressed: onView,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: scheme.secondaryContainer,
                          foregroundColor: scheme.onSecondaryContainer,
                        ),
                        child: const Text('Track'),
                      )
                    : FilledButton(
                        onPressed: onView,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('View'),
                      ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// One-line resolved address for a request pin (uses [NominatimGeocode] cache).
class _ReverseAddressRow extends StatefulWidget {
  final double latitude;
  final double longitude;

  const _ReverseAddressRow({required this.latitude, required this.longitude});

  @override
  State<_ReverseAddressRow> createState() => _ReverseAddressRowState();
}

class _ReverseAddressRowState extends State<_ReverseAddressRow> {
  String? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await NominatimGeocode.reverse(widget.latitude, widget.longitude);
    if (!mounted) return;
    setState(() {
      _address = a;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_loading) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading address…',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }
    if (_address == null || _address!.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.place_outlined, size: 17, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _address!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
