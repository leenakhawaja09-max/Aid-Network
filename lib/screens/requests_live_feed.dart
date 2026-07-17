import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mission_status.dart';
import '../services/geospatial_discovery_service.dart';
import '../services/location_service.dart';
import '../utils/app_user.dart';
import '../utils/geo_utils.dart';
import '../utils/request_expiry.dart';
import 'request_details_screen.dart';

class RequestsLiveFeedScreen extends StatelessWidget {
  const RequestsLiveFeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live requests',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: const RequestsLiveFeedWidget(expandVertically: true),
    );
  }
}

/// Live open requests list. Set [expandVertically] false when placed inside a parent [ScrollView].
class RequestsLiveFeedWidget extends StatefulWidget {
  /// `true` for [Scaffold] body; `false` inside [SingleChildScrollView] / map panel.
  final bool expandVertically;

  const RequestsLiveFeedWidget({
    super.key,
    this.expandVertically = false,
  });

  @override
  State<RequestsLiveFeedWidget> createState() => _RequestsLiveFeedWidgetState();
}

class _RequestsLiveFeedWidgetState extends State<RequestsLiveFeedWidget> {
  final ScrollController _scrollController = ScrollController();
  final _discovery = GeospatialDiscoveryService();
  final _location = const LocationService();
  String? _lastFirstId;
  double? _viewerLat;
  double? _viewerLng;
  double _radiusMiles = 10.0;
  List<Map<String, dynamic>> _rpcRows = [];
  List<Map<String, dynamic>>? _restFallbackRows;
  Timer? _restPollTimer;
  String? _lastStreamError;

  @override
  void initState() {
    super.initState();
    _loadViewer();
    _pollRequestsRest();
    _restPollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollRequestsRest());
  }

  @override
  void dispose() {
    _restPollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pollRequestsRest() async {
    try {
      final rows = await Supabase.instance.client
          .from('requests')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _restFallbackRows = List<Map<String, dynamic>>.from(rows);
        _lastStreamError = null;
      });
    } catch (e) {
      debugPrint('requests REST poll: $e');
    }
  }

  Future<void> _loadViewer() async {
    final uid = currentUserId();
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('latitude,longitude')
          .eq('id', uid)
          .maybeSingle();
      var lat = readCoord(row?['latitude']);
      var lng = readCoord(row?['longitude']);
      if (lat == null || lng == null) {
        try {
          final pos = await _location.getCurrentPosition();
          lat = pos.latitude;
          lng = pos.longitude;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _viewerLat = lat;
        _viewerLng = lng;
      });
      await _refreshRpc();
    } catch (_) {}
  }

  Future<void> _refreshRpc() async {
    if (_viewerLat == null || _viewerLng == null) return;
    try {
      final rows = await _discovery.fetchRequestsInRadius(
        userLat: _viewerLat!,
        userLng: _viewerLng!,
        radiusMiles: _radiusMiles,
      );
      if (mounted) setState(() => _rpcRows = rows);
    } catch (_) {}
  }

  bool _isOpenLike(Map<String, dynamic> r) {
    if (!isRequestVisibleForDiscovery(r)) return false;
    final ms = MissionStatus.fromDb(r['status']?.toString());
    if (ms != null) return ms.isDiscoverable;
    final s = r['status']?.toString().toLowerCase() ?? '';
    return s == 'open' || s == 'urgent' || s == 'active' || s == 'created' || s == 'pending' || s == 'pitched';
  }

  List<Map<String, dynamic>> _applyRadius(List<Map<String, dynamic>> raw, String? currentUid) {
    if (_rpcRows.isNotEmpty) {
      return _rpcRows.where((r) => r['user_id']?.toString() != currentUid).toList();
    }
    var list = raw.where((r) => _isOpenLike(r)).where((r) => r['user_id']?.toString() != currentUid).toList();

    if (_viewerLat != null && _viewerLng != null) {
      list = list.where((r) {
        final rLat = readCoord(r['latitude']);
        final rLng = readCoord(r['longitude']);
        if (rLat == null || rLng == null) return false;
        return withinRadiusMiles(
          viewerLat: _viewerLat!,
          viewerLng: _viewerLng!,
          requestLat: rLat,
          requestLng: rLng,
          radiusMiles: _radiusMiles,
        );
      }).toList();
    }
    return list;
  }

  Widget _radiusSlider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Text(
            'Radius ${_radiusMiles.toStringAsFixed(0)} mi',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Slider(
              value: _radiusMiles.clamp(1, 50),
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) {
                setState(() => _radiusMiles = v);
                _refreshRpc();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedBody(
    BuildContext context,
    AsyncSnapshot<List<Map<String, dynamic>>?> snapshot,
    String? currentUid,
  ) {
    if (snapshot.hasError) {
      _lastStreamError ??= snapshot.error.toString();
      final fallback = _restFallbackRows;
      if (fallback != null) {
        return _buildFeedBody(
          context,
          AsyncSnapshot.withData(ConnectionState.done, fallback),
          currentUid,
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Live connection unavailable — retrying every few seconds.\n'
              'If this persists, run supabase_connection_fix.sql in Supabase.\n'
              '$_lastStreamError',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _pollRequestsRest,
              child: const Text('Retry now'),
            ),
          ],
        ),
      );
    }

    if (!snapshot.hasData) {
      final fallback = _restFallbackRows;
      if (fallback != null) {
        return _buildFeedBody(
          context,
          AsyncSnapshot.withData(ConnectionState.done, fallback),
          currentUid,
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final raw = snapshot.data ?? <Map<String, dynamic>>[];
    final requests = _applyRadius(List<Map<String, dynamic>>.from(raw), currentUid);

    if (requests.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar_rounded, size: 52, color: scheme.outlineVariant),
            const SizedBox(height: 14),
            Text(
              _viewerLat == null ? 'No open requests right now' : 'Nothing in range',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _viewerLat == null
                  ? 'Set your location in Profile to filter by distance.'
                  : 'No requests near your location. Try increasing radius.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final firstId = requests.first['id']?.toString();
    if (firstId != null && firstId != _lastFirstId) {
      _lastFirstId = firstId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      });
    }

    final shrink = !widget.expandVertically;
    return ListView.builder(
      controller: shrink ? null : _scrollController,
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      itemCount: requests.length,
      itemBuilder: (context, index) => _requestTile(context, requests[index], currentUid),
    );
  }

  Widget _requestTile(BuildContext context, Map<String, dynamic> req, String? currentUid) {
    final scheme = Theme.of(context).colorScheme;
    final title = req['title']?.toString() ?? 'No title';
    final category = req['category']?.toString() ?? 'General';
    final description = req['description']?.toString() ?? '';
    final currentRadius = req['current_radius']?.toString() ?? '—';
    final distance = req['distance']?.toString() ?? '';
    final userId = req['user_id']?.toString();
    final createdAtRaw = req['created_at']?.toString();

    final isMine = (userId != null && userId == currentUid);

    var isNew = false;
    if (createdAtRaw != null) {
      final parsed = DateTime.tryParse(createdAtRaw);
      if (parsed != null) {
        final diff = DateTime.now().difference(parsed).inSeconds;
        isNew = diff.abs() <= 10;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isMine ? scheme.primary.withValues(alpha: 0.45) : scheme.outlineVariant.withValues(alpha: 0.45),
            width: isMine ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RequestDetailsScreen(request: req),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (isNew)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'NEW',
                          style: TextStyle(
                            color: scheme.onError,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (isMine)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Yours',
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  category,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                          height: 1.4,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Radius: $currentRadius mi',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (distance.isNotEmpty)
                      Text(
                        distance,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = currentUserId();

    final stream = Supabase.instance.client
        .from('requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    final feed = StreamBuilder<List<Map<String, dynamic>>?>(
      stream: stream,
      builder: (context, snapshot) => _buildFeedBody(context, snapshot, currentUid),
    );

    if (widget.expandVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _radiusSlider(context),
          Expanded(child: feed),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _radiusSlider(context),
        feed,
      ],
    );
  }
}
