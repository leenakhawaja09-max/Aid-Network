import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/directions_service.dart';
import '../services/wifi_voice_call.dart';
import '../widgets/app_ui.dart';
import 'live_mission_screen.dart';
import '../utils/app_user.dart';
import 'chat_details_screen.dart';
import 'completion_screen.dart';

final _supabase = Supabase.instance.client;

class TrackingScreen extends StatefulWidget {
  final String missionType;
  final String? requestId;
  final String partnerName;
  final VoidCallback? onMissionComplete;

  const TrackingScreen({
    super.key,
    required this.missionType,
    this.requestId,
    this.partnerName = 'Volunteer',
    this.onMissionComplete,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final MapController _mapController = MapController();
  LatLng? _requesterPos;
  LatLng? _helperPos;
  List<LatLng> _routePoints = [];
  String _requesterName = 'Requester';
  String _helperName = 'Helper';
  String _distanceText = '—';
  String _durationText = '—';
  bool _loading = true;
  String? _error;
  String _helperUserId = '';
  String _requesterUserId = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (widget.requestId != null &&
          (widget.missionType == 'receiving' || widget.missionType == 'assisting')) {
        _loadPositions(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.missionType != widget.missionType) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.requestId == null ||
        (widget.missionType != 'receiving' && widget.missionType != 'assisting')) {
      setState(() {
        _loading = false;
        _requesterPos = null;
        _helperPos = null;
        _routePoints = [];
      });
      return;
    }
    await _loadPositions();
  }

  Future<void> _loadPositions({bool silent = false}) async {
    final rid = widget.requestId;
    if (rid == null) return;
    if (!silent) setState(() => _loading = true);

    try {
      final pitchRows = await _supabase
          .from('pitches')
          .select()
          .eq('request_id', rid)
          .eq('status', 'accepted')
          .limit(1) as List<dynamic>;

      if (pitchRows.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No accepted pitch for this request yet.';
            _loading = false;
          });
        }
        return;
      }

      final pitch = Map<String, dynamic>.from(pitchRows.first as Map);
      final helperId = pitch['helper_id']?.toString();
      if (helperId == null || helperId.isEmpty) throw Exception('Missing helper');

      final reqRows = await _supabase.from('requests').select().eq('id', rid).limit(1) as List<dynamic>;
      if (reqRows.isEmpty) throw Exception('Request not found');
      final req = Map<String, dynamic>.from(reqRows.first as Map);
      final requesterId = req['user_id']?.toString();
      if (requesterId == null) throw Exception('Missing requester');

      final helperProfile = await _profileFor(helperId);
      final requesterProfile = await _profileFor(requesterId);

      var hLat = _readLat(helperProfile);
      var hLng = _readLng(helperProfile);
      double rLat;
      double rLng;
      final pinLat = _readOptionalCoord(req['latitude']);
      final pinLng = _readOptionalCoord(req['longitude']);
      if (pinLat != null && pinLng != null) {
        rLat = pinLat;
        rLng = pinLng;
      } else {
        rLat = _readLat(requesterProfile);
        rLng = _readLng(requesterProfile);
      }

      if ((hLat - rLat).abs() < 1e-6 && (hLng - rLng).abs() < 1e-6) {
        hLat += 0.004;
      }

      final helperLatLng = LatLng(hLat, hLng);
      final requesterLatLng = LatLng(rLat, rLng);

      final dir = await fetchDrivingDirections(
        origin: helperLatLng,
        destination: requesterLatLng,
      );

      if (!mounted) return;
      setState(() {
        _helperUserId = helperId;
        _requesterUserId = requesterId;
        _helperName = helperProfile?['full_name']?.toString().trim().isNotEmpty == true
            ? helperProfile!['full_name'].toString()
            : 'Helper';
        _requesterName = requesterProfile?['full_name']?.toString().trim().isNotEmpty == true
            ? requesterProfile!['full_name'].toString()
            : 'Requester';
        _helperPos = helperLatLng;
        _requesterPos = requesterLatLng;
        _distanceText = dir?.distanceText ?? _haversineLabel(helperLatLng, requesterLatLng);
        _durationText = dir?.durationText ?? 'Straight-line distance; enable Directions API for drive time';
        _routePoints = dir?.polylinePoints ?? [];
        _error = null;
        _loading = false;
      });

      _fitCamera();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _profileFor(String uid) async {
    try {
      final row = await _supabase.from('profiles').select().eq('id', uid).maybeSingle();
      return row != null ? Map<String, dynamic>.from(row) : null;
    } catch (_) {
      return null;
    }
  }

  double _readLat(Map<String, dynamic>? p) {
    final v = p?['latitude'];
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString()) ?? 37.7749;
    return 37.7749;
  }

  double _readLng(Map<String, dynamic>? p) {
    final v = p?['longitude'];
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString()) ?? -122.4194;
    return -122.4194;
  }

  double? _readOptionalCoord(dynamic v) {
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString());
    return null;
  }

  String _haversineLabel(LatLng a, LatLng b) {
    const earth = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final la1 = _rad(a.latitude);
    final la2 = _rad(b.latitude);
    final h = (math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    final m = earth * c;
    final mi = m / 1609.34;
    return '${mi.toStringAsFixed(1)} mi (approx)';
  }

  double _rad(double x) => x * math.pi / 180.0;

  Future<void> _cancelMission({required bool receivingSide}) async {
    final rid = widget.requestId;
    if (rid == null || rid.isEmpty) return;
    try {
      if (receivingSide && widget.missionType == 'receiving') {
        await _supabase.from('pitches').update({'status': 'declined'}).eq('request_id', rid).eq('status', 'pending');
        await _supabase.from('pitches').update({'status': 'declined'}).eq('request_id', rid).eq('status', 'awaiting_helper_ack');
        await _supabase.from('pitches').update({'status': 'declined'}).eq('request_id', rid).eq('status', 'accepted');
        await _supabase.from('requests').update({'status': 'open'}).eq('id', rid);
      } else if (!receivingSide && widget.missionType == 'assisting') {
        final uid = currentUserId();
        if (uid != null) {
          await _supabase
              .from('pitches')
              .update({'status': 'declined'})
              .eq('request_id', rid)
              .eq('helper_id', uid)
              .eq('status', 'accepted');
        }
        await _supabase.from('requests').update({'status': 'open'}).eq('id', rid);
      }
    } catch (e) {
      debugPrint('cancel mission: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mission cancelled — request is open again.')),
      );
    }
  }

  void _fitCamera() {
    final a = _helperPos;
    final b = _requesterPos;
    if (a == null || b == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final south = math.min(a.latitude, b.latitude);
        final north = math.max(a.latitude, b.latitude);
        final west = math.min(a.longitude, b.longitude);
        final east = math.max(a.longitude, b.longitude);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(LatLng(south, west), LatLng(north, east)),
            padding: const EdgeInsets.only(left: 48, right: 48, top: 48, bottom: 220),
          ),
        );
      } catch (_) {}
    });
  }

  String _cardPersonLabel(bool receivingTab) {
    if (widget.missionType == 'receiving' && receivingTab) {
      return _helperName;
    }
    if (widget.missionType == 'assisting' && !receivingTab) {
      return _requesterName;
    }
    return widget.partnerName;
  }

  String _statusLabel(bool receivingTab) {
    if (widget.missionType == 'receiving' && receivingTab) return 'On the way';
    if (widget.missionType == 'assisting' && !receivingTab) return 'Navigating to';
    return 'Live';
  }

  @override
  Widget build(BuildContext context) {
    final initialTab = (widget.missionType == 'receiving') ? 0 : 1;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: Text(
            'Live Tracking',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Requests'),
              Tab(text: "I'm Helping"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            widget.missionType == 'receiving'
                ? _buildLiveMapTab(receivingSide: true)
                : _buildEmptyState(context, 'No one is currently coming to help you.'),
            widget.missionType == 'assisting'
                ? _buildLiveMapTab(receivingSide: false)
                : _buildEmptyState(context, "You aren't currently assisting anyone."),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMapTab({required bool receivingSide}) {
    final rid = widget.requestId;
    if (rid != null && rid.isNotEmpty) {
      return LiveMissionScreen(
        requestId: rid,
        isRequesterView: receivingSide,
        partnerName: widget.partnerName,
        onMissionComplete: widget.onMissionComplete,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (_helperPos == null || _requesterPos == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    if (_helperPos == null || _requesterPos == null) {
      return _buildEmptyState(context, 'Waiting for handshake data…');
    }

    final personName = _cardPersonLabel(receivingSide);
    final statusLabel = _statusLabel(receivingSide);
    final etaLine = '$_distanceText • $_durationText';

    final midLat = (_helperPos!.latitude + _requesterPos!.latitude) / 2;
    final midLng = (_helperPos!.longitude + _requesterPos!.longitude) / 2;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(midLat, midLng),
            initialZoom: 13,
            onMapReady: _fitCamera,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'rapid_aid',
            ),
            if (_routePoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.5,
                    color: scheme.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _requesterPos!,
                  width: 44,
                  height: 44,
                    child: Tooltip(
                    message: _requesterName,
                    child: Icon(Icons.location_pin, color: scheme.primary, size: 40),
                  ),
                ),
                Marker(
                  point: _helperPos!,
                  width: 44,
                  height: 44,
                  child: Tooltip(
                    message: _helperName,
                    child: Icon(Icons.location_pin, color: scheme.secondary, size: 40),
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 10,
          left: 10,
          right: 10,
          child: Material(
            color: scheme.primaryContainer.withValues(alpha: 0.55),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.map_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OpenStreetMap • Primary pin: help location • Secondary pin: helper.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: scheme.surfaceContainerLowest,
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 22,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
                        child: Icon(Icons.person_rounded, color: scheme.primary, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName,
                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$statusLabel • $etaLine',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildCircularButton(context, Icons.call_rounded, scheme.secondary, () async {
                      final peerId = receivingSide ? _helperUserId : _requesterUserId;
                      if (peerId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Call unavailable until profiles load.')),
                        );
                        return;
                      }
                      final go = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Start Wi‑Fi / data call'),
                          content: const Text(
                            'Opens a shared browser room. Ask your partner to tap Call in chat too.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
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
                    }),
                    const SizedBox(width: 10),
                    _buildCircularButton(context, Icons.chat_rounded, scheme.primary, () {
                      final peerId = receivingSide ? _helperUserId : _requesterUserId;
                      if (peerId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chat unavailable until profiles load.')),
                        );
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatDetailsScreen(
                            peerName: personName,
                            peerUserId: peerId,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statusInfo(context, 'Distance', _distanceText),
                    _statusInfo(context, 'ETA (driving)', _durationText),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CompletionScreen(
                            personName: personName,
                            wasHelper: widget.missionType == 'assisting',
                            requestId: widget.requestId,
                            revieweeUserId: receivingSide ? _helperUserId : _requesterUserId,
                            onComplete: () {
                              widget.onMissionComplete?.call();
                              if (Navigator.canPop(context)) Navigator.pop(context);
                            },
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'Complete mission',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () async {
                      await _cancelMission(receivingSide: receivingSide);
                      widget.onMissionComplete?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: 0.55)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      statusLabel == 'On the way' ? 'Cancel request' : 'Cancel assistance',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircularButton(BuildContext context, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: CircleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    return AppUi.emptyState(
      context: context,
      icon: Icons.explore_off_rounded,
      title: 'No active mission',
      message: message,
    );
  }

  Widget _statusInfo(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
