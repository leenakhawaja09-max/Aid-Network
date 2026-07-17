import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/live_mission_controller.dart';
import '../models/mission_status.dart';
import '../services/location_service.dart';
import '../services/pitch_handshake.dart';
import '../services/wifi_voice_call.dart';
import '../theme/app_colors.dart';
import '../widgets/app_ui.dart';
import '../widgets/incoming_pitches_panel.dart';
import '../widgets/mission_timeline_stepper.dart';
import 'chat_details_screen.dart';
import 'completion_screen.dart';

/// Dual-perspective live mission map (requester vs helper).
class LiveMissionScreen extends StatefulWidget {
  final String requestId;
  final bool isRequesterView;
  final String partnerName;
  final VoidCallback? onMissionComplete;

  const LiveMissionScreen({
    super.key,
    required this.requestId,
    required this.isRequesterView,
    this.partnerName = 'Partner',
    this.onMissionComplete,
  });

  @override
  State<LiveMissionScreen> createState() => _LiveMissionScreenState();
}

class _LiveMissionScreenState extends State<LiveMissionScreen> {
  late final LiveMissionController _ctrl;
  final MapController _mapController = MapController();
  final _location = const LocationService();
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = LiveMissionController(
      requestId: widget.requestId,
      isRequesterView: widget.isRequesterView,
    )..addListener(_onCtrl);
    _ctrl.bootstrap().then((_) => _fitMap());
  }

  void _onCtrl() {
    if (mounted) setState(() {});
    _fitMap();
  }

  void _fitMap() {
    final pts = <LatLng>[];
    if (_ctrl.requesterPos != null) pts.add(_ctrl.requesterPos!);
    if (_ctrl.helperPos != null) pts.add(_ctrl.helperPos!);
    if (pts.isEmpty) return;
    _location.fitBounds(_mapController, points: pts);
  }

  Future<void> _openNavigation() async {
    final dest = _ctrl.requesterPos;
    if (dest == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onHelperCheckpoint(MissionStatus target) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _ctrl.helperCheckpoint(target);
      if (!mounted) return;
      final label = switch (target) {
        MissionStatus.inProgress => 'Marked en route',
        MissionStatus.arriving => 'Marked arrived',
        MissionStatus.completed => 'Mission completed',
        _ => 'Status updated',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label), backgroundColor: Theme.of(context).colorScheme.primary),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update mission: $e\n'
            'Run supabase_connection_fix.sql if this is a permissions error.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _openChat() async {
    final peerId = _ctrl.partnerUserId;
    if (peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat opens after the mission is live with a partner.')),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailsScreen(
          peerName: _ctrl.partnerDisplayName,
          peerUserId: peerId,
        ),
      ),
    );
  }

  Future<void> _openCall() async {
    final peerId = _ctrl.partnerUserId;
    if (peerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call unavailable until partner is linked.')),
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wi‑Fi / data call'),
        content: const Text(
          'Opens a shared browser room. Ask your partner to tap Call at the same time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open call')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final ok = await startWifiVoiceCallWithPeer(peerId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open call link.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _markDone(bool receiving) async {
    if (!_ctrl.canMarkDone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Done is available after your helper confirms the mission.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final reward = await _ctrl.completeMission();
      if (!mounted) return;
      if (!receiving) {
        final scheme = Theme.of(context).colorScheme;
        if (reward?['ok'] == true && reward?['already_rewarded'] != true) {
          final karma = reward?['karma_points'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Nice work! +1 help${karma != null ? ', $karma karma total' : ''}.',
              ),
              backgroundColor: scheme.secondary,
            ),
          );
        } else if (reward?['ok'] != true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reward?['reason'] == 'run_supabase_helper_rewards_sql'
                    ? 'Run supabase_helper_rewards.sql in Supabase, then tap Done again.'
                    : 'Help/karma not updated (${reward?['reason'] ?? 'unknown'}).',
              ),
              backgroundColor: scheme.error,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CompletionScreen(
            personName: receiving ? _ctrl.helperName : _ctrl.requesterName,
            wasHelper: !receiving,
            requestId: widget.requestId,
            revieweeUserId: receiving ? _ctrl.helperId : _ctrl.requesterId,
            onComplete: widget.onMissionComplete,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not complete mission: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrl);
    _ctrl.dispose();
    super.dispose();
  }

  String _roleLabel(bool receiving) => receiving ? 'Your helper' : 'Person you are helping';

  String _statusChipLabel() {
    final s = _ctrl.status;
    return switch (s) {
      MissionStatus.accepted => 'Confirmed — head to them when ready',
      MissionStatus.inProgress => 'En route',
      MissionStatus.arriving => 'Arrived at location',
      MissionStatus.completed => 'Completed',
      _ => 'Live mission',
    };
  }

  Widget _etaChip(ColorScheme scheme, TextTheme textTheme) {
    final d = _ctrl.distanceText;
    final t = _ctrl.durationText;
    final hasRoute = d != '—' && t != '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            hasRoute ? Icons.directions_car_filled_rounded : Icons.hourglass_top_rounded,
            size: 20,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasRoute ? '$d drive • $t' : 'Calculating driving distance…',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactButtons(ColorScheme scheme) {
    final enabled = _ctrl.canContactPartner;
    const actionHeight = 48.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: actionHeight,
                child: FilledButton.icon(
                  onPressed: enabled ? _openChat : null,
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: const Text('Chat'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: actionHeight,
              width: actionHeight,
              child: FilledButton.tonal(
                onPressed: enabled ? _openCall : null,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Icon(Icons.call_rounded, size: 22),
              ),
            ),
          ],
        ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          Text(
            'Chat and call unlock after you both confirm the mission.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.3),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ctrl.error != null && _ctrl.requesterPos == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live mission')),
        body: Center(child: Text(_ctrl.error!)),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final receiving = widget.isRequesterView;
    // Main shell uses extendBody + bottom NavigationBar — keep Done above the nav.
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 88;
    final canEnRoute = _ctrl.status == MissionStatus.accepted ||
        _ctrl.status == MissionStatus.helperSelected ||
        _ctrl.status == MissionStatus.pitched;
    final canArrive = _ctrl.status == MissionStatus.inProgress;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surfaceContainer,
              child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _ctrl.requesterPos ?? const LatLng(24.8607, 67.0011),
                initialZoom: 13,
                onMapReady: _fitMap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'rapid_aid',
                ),
                if (_ctrl.routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: _ctrl.routePoints, strokeWidth: 5, color: scheme.primary),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_ctrl.requesterPos != null)
                      Marker(
                        point: _ctrl.requesterPos!,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_pin, color: scheme.primary, size: 38),
                      ),
                    if (_ctrl.helperPos != null)
                      Marker(
                        point: _ctrl.helperPos!,
                        width: 40,
                        height: 40,
                        child: Icon(Icons.volunteer_activism, color: scheme.secondary, size: 32),
                      ),
                  ],
                ),
              ],
            ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                elevation: 3,
                shadowColor: scheme.shadow.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: scheme.surfaceContainerLowest.withValues(alpha: 0.97),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: MissionTimelineStepper(
                    current: _ctrl.status,
                    events: _ctrl.timeline,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomClearance),
              child: PointerInterceptor(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                    boxShadow: AppUi.panelShadow(scheme),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppUi.sheetDragHandle(scheme),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              AppUi.partnerAvatar(
                                scheme: scheme,
                                name: receiving ? _ctrl.helperName : _ctrl.requesterName,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      receiving ? _ctrl.helperName : _ctrl.requesterName,
                                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _roleLabel(receiving),
                                      style: textTheme.labelMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (_ctrl.helperRating != null && receiving)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            Icon(Icons.star_rounded, size: 16, color: scheme.star),
                                            const SizedBox(width: 4),
                                            Text(
                                              _ctrl.helperRating!.toStringAsFixed(1),
                                              style: textTheme.labelLarge,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _statusChipLabel(),
                              style: textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _etaChip(scheme, textTheme),
                          const SizedBox(height: 14),
                          _contactButtons(scheme),
                          if (receiving && _ctrl.incomingPitches.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 140,
                              child: IncomingPitchesPanel(
                                requestId: widget.requestId,
                                requestOwnerId: _ctrl.requesterId,
                                onAccept: ({
                                  required String pitchId,
                                  required String requestId,
                                  required String helperId,
                                }) async {
                                  await requesterSelectHelperPitch(
                                    pitchId: pitchId,
                                    requestId: requestId,
                                  );
                                  await _ctrl.bootstrap();
                                },
                                onDecline: (pitchId) async {
                                  await Supabase.instance.client
                                      .from('pitches')
                                      .update({'status': 'declined'})
                                      .eq('id', pitchId);
                                  await _ctrl.bootstrap();
                                },
                              ),
                            ),
                          ],
                          if (!receiving) ...[
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: (_actionBusy || !canEnRoute)
                                  ? null
                                  : () => _onHelperCheckpoint(MissionStatus.inProgress),
                              child: _actionBusy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text("I'm en route"),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: (_actionBusy || !canArrive)
                                  ? null
                                  : () => _onHelperCheckpoint(MissionStatus.arriving),
                              child: const Text('I have arrived'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _openNavigation,
                              icon: const Icon(Icons.navigation_outlined),
                              label: const Text('Open navigation'),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                          const SizedBox(height: 14),
                          if (!_ctrl.canMarkDone)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                'Done unlocks after the mission is confirmed (status: accepted).',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(height: 1.3),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: (_actionBusy || !_ctrl.canMarkDone)
                                ? null
                                : () => _markDone(receiving),
                            icon: const Icon(Icons.check_circle_rounded),
                            label: const Text('Done'),
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
