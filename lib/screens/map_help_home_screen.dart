import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/mission_status.dart';
import '../services/geospatial_discovery_service.dart';
import '../services/location_service.dart';
import '../services/nominatim_geocode.dart';
import '../utils/app_user.dart';
import '../utils/geo_utils.dart';
import '../utils/request_expiry.dart';
import '../widgets/app_ui.dart';
import 'create_request_screen.dart';
import 'profile_screen.dart';
import 'request_details_screen.dart';

/// Full-screen map + left panel for **community help** (single request pin + search radius).
class MapHelpHomeScreen extends StatefulWidget {
  final List<Map<String, dynamic>> globalRequests;
  final void Function(Map<String, dynamic> request) onOfferHelp;

  /// Called after [CreateRequestSheet] successfully posts (sheet performs the insert).
  final VoidCallback onAfterRequestPosted;
  final VoidCallback onViewTracking;
  final String activeMissionType;

  /// When set with [activeMissionType] receiving/assisting, map line uses live helper → request pin.
  final String? activeRequestId;

  const MapHelpHomeScreen({
    super.key,
    required this.globalRequests,
    required this.onOfferHelp,
    required this.onAfterRequestPosted,
    required this.onViewTracking,
    required this.activeMissionType,
    this.activeRequestId,
  });

  @override
  State<MapHelpHomeScreen> createState() => _MapHelpHomeScreenState();
}

class _MapHelpHomeScreenState extends State<MapHelpHomeScreen> {
  final MapController _mapController = MapController();

  static const LatLng _defaultCenter = LatLng(24.8607, 67.0011);

  LatLng? _requestPos;
  double _radiusMiles = 8.0;
  List<Map<String, dynamic>> _radiusRpcRequests = [];
  Timer? _radiusDebounce;
  final _discovery = GeospatialDiscoveryService();
  final _location = const LocationService();
  String _selectedCategory = 'General Help';
  bool _locating = false;
  String? _geoHint;

  final TextEditingController _locationSearchController =
      TextEditingController();
  Timer? _locReverseTimer;
  int _locGen = 0;
  bool _locLoading = false;

  final FocusNode _locationFocusNode = FocusNode();

  Timer? _locSuggestTimer;
  int _locSuggestSeq = 0;
  List<NominatimPlace> _locSuggestions = [];
  bool _locationTextUserEdited = false;
  bool _requestPosTrusted = false;
  bool _radiusSliderDragging = false;
  bool _locSuggestLoading = false;

  /// Red route on map: only after mutual agreement (live helper → request pin).
  static const Color _routeLineColor = Color(0xFFE53935);
  Timer? _missionPosTimer;
  LatLng? _liveHelperPos;
  LatLng? _requestPinPos;

  bool _isOpenLike(Map<String, dynamic> r) {
    if (!isRequestVisibleForDiscovery(
      r,
      exceptRequestId: widget.activeRequestId,
    )) {
      return false;
    }
    final ms = MissionStatus.fromDb(r['status']?.toString());
    if (ms != null) return ms.isDiscoverable;
    final s = r['status']?.toString().toLowerCase() ?? '';
    return s == 'open' ||
        s == 'urgent' ||
        s == 'active' ||
        s == 'in-progress' ||
        s == 'in_progress' ||
        s == 'created' ||
        s == 'pending' ||
        s == 'pitched';
  }

  LatLng _anchor() => _requestPos ?? _defaultCenter;

  @override
  void initState() {
    super.initState();
    _locationFocusNode.addListener(_onLocationFocusChanged);
    _syncMissionLineTimer();
    _scheduleRadiusRpc();
    _locationSearchController.addListener(_onLocationSearchTextChanged);
  }

  void _scheduleRadiusRpc() {
    _radiusDebounce?.cancel();
    _radiusDebounce = Timer(const Duration(milliseconds: 350), _fetchRadiusRpc);
  }

  Future<void> _fetchRadiusRpc() async {
    final anchor = _requestPos;
    if (anchor == null) return;
    try {
      final rows = await _discovery.fetchRequestsInRadius(
        userLat: anchor.latitude,
        userLng: anchor.longitude,
        radiusMiles: _radiusMiles,
      );
      if (!mounted) return;
      setState(() => _radiusRpcRequests = rows);
    } catch (_) {
      // PostGIS RPC not deployed — client-side filter in _requestsOnMap still works
    }
  }

  @override
  void didUpdateWidget(covariant MapHelpHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRequestId != widget.activeRequestId ||
        oldWidget.activeMissionType != widget.activeMissionType) {
      _syncMissionLineTimer();
    }
  }

  void _syncMissionLineTimer() {
    _missionPosTimer?.cancel();
    _missionPosTimer = null;
    final rid = widget.activeRequestId?.trim();
    final mission = widget.activeMissionType == 'receiving' ||
        widget.activeMissionType == 'assisting';
    if (rid == null || rid.isEmpty || !mission) {
      if (_liveHelperPos != null || _requestPinPos != null) {
        setState(() {
          _liveHelperPos = null;
          _requestPinPos = null;
        });
      }
      {
        return;
      }
    }
    _pollMissionLinePositions();
    _missionPosTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _pollMissionLinePositions());
  }

  Future<void> _pollMissionLinePositions() async {
    final rid = widget.activeRequestId?.trim();
    if (rid == null || rid.isEmpty) {
      return;
    }
    if (widget.activeMissionType != 'receiving' &&
        widget.activeMissionType != 'assisting') {
      return;
    }

    final supa = Supabase.instance.client;
    try {
      final pitch = await supa
          .from('pitches')
          .select('helper_id')
          .eq('request_id', rid)
          .eq('status', 'accepted')
          .limit(1)
          .maybeSingle();
      if (pitch == null || !mounted) return;
      final helperId = pitch['helper_id']?.toString();
      if (helperId == null || helperId.isEmpty) return;

      final req = await supa
          .from('requests')
          .select('user_id,latitude,longitude')
          .eq('id', rid)
          .maybeSingle();
      if (!mounted) return;

      final hProf = await supa
          .from('profiles')
          .select('latitude,longitude')
          .eq('id', helperId)
          .maybeSingle();
      if (!mounted) return;

      var hLat = readCoord(hProf?['latitude']);
      var hLng = readCoord(hProf?['longitude']);
      if (hLat == null || hLng == null) return;

      LatLng? end;
      final pinLat = readCoord(req?['latitude']);
      final pinLng = readCoord(req?['longitude']);
      if (pinLat != null && pinLng != null) {
        end = LatLng(pinLat, pinLng);
      } else {
        final requesterId = req?['user_id']?.toString();
        if (requesterId != null && requesterId.isNotEmpty) {
          final rp = await supa
              .from('profiles')
              .select('latitude,longitude')
              .eq('id', requesterId)
              .maybeSingle();
          if (!mounted) return;
          final rLat = readCoord(rp?['latitude']);
          final rLng = readCoord(rp?['longitude']);
          if (rLat != null && rLng != null) end = LatLng(rLat, rLng);
        }
      }
      if (end == null || !mounted) return;

      var helperLat = hLat;
      var helperLng = hLng;
      if ((helperLat - end.latitude).abs() < 1e-5 &&
          (helperLng - end.longitude).abs() < 1e-5) {
        helperLng += 0.0004;
      }

      final pinPos = end;
      setState(() {
        _liveHelperPos = LatLng(helperLat, helperLng);
        _requestPinPos = pinPos;
      });
      _fitToPins();
    } catch (_) {
      // keep previous line if any
    }
  }

  List<LatLng> _routeLinePoints() {
    final rid = widget.activeRequestId?.trim();
    final mission = widget.activeMissionType == 'receiving' ||
        widget.activeMissionType == 'assisting';
    if (mission && rid != null && rid.isNotEmpty) {
      if (_liveHelperPos != null && _requestPinPos != null) {
        return [_liveHelperPos!, _requestPinPos!];
      }
    }
    return const [];
  }

  void _onLocationFocusChanged() {
    setState(() {});
  }

  void _onLocationSearchTextChanged() {
    _locationTextUserEdited = true;
    _requestPosTrusted = false;
    _locReverseTimer?.cancel();
    _locSuggestTimer?.cancel();
    if (_locationSearchController.text.trim().length < 3) {
      if (_locSuggestions.isNotEmpty || _locSuggestLoading) {
        setState(() {
          _locSuggestions = [];
          _locSuggestLoading = false;
        });
      }
      return;
    }
    final seq = ++_locSuggestSeq;
    _locSuggestTimer = Timer(const Duration(milliseconds: 450),
        () => _fetchLocationSuggestions(seq));
  }

  Future<void> _fetchLocationSuggestions(int seq) async {
    final q = _locationSearchController.text.trim();
    if (q.length < 3 || seq != _locSuggestSeq) return;
    if (mounted) setState(() => _locSuggestLoading = true);
    final hits = await NominatimGeocode.search(q, limit: 10);
    if (!mounted || seq != _locSuggestSeq) return;
    setState(() {
      _locSuggestLoading = false;
      _locSuggestions = hits;
    });
  }

  bool get _canSubmitHelpRequest => _requestPos != null;

  void _pickLocationPlace(NominatimPlace p) {
    final at = LatLng(p.latitude, p.longitude);
    _locReverseTimer?.cancel();
    _locGen++;
    _locSuggestSeq++;
    setState(() {
      _requestPos = at;
      _locationSearchController.text = p.shortLabel;
      _locSuggestions = [];
      _locationTextUserEdited = false;
      _requestPosTrusted = true;
    });
    _locationFocusNode.unfocus();
    _fitMapToRadiusCircle();
  }

  Future<void> _runLocationSearchOrSubmit() async {
    final q = _locationSearchController.text.trim();
    if (q.length < 2) {
      setState(() => _geoHint =
          'Type at least 2 characters, then search or pick a suggestion.');
      return;
    }
    _locSuggestTimer?.cancel();
    _locSuggestSeq++;
    setState(() {
      _locSuggestLoading = true;
      _geoHint = null;
    });
    final hits = await NominatimGeocode.search(q, limit: 10);
    if (!mounted) return;
    setState(() {
      _locSuggestLoading = false;
      _locSuggestions = hits;
    });
    if (_locSuggestions.length == 1) {
      _pickLocationPlace(_locSuggestions.first);
      return;
    }
    if (_locSuggestions.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No matching places — try adding city or area.')),
      );
    }
  }

  Future<LatLng?> _resolveRequestPositionForPost() async {
    if (_requestPosTrusted && !_locationTextUserEdited && _requestPos != null) {
      return _requestPos;
    }
    final q = _locationSearchController.text.trim();
    if (q.length < 2) return _requestPos;
    setState(() => _locLoading = true);
    final hits = await NominatimGeocode.search(q, limit: 5);
    if (!mounted) return null;
    setState(() => _locLoading = false);
    if (hits.isEmpty) return null;
    final at = LatLng(hits.first.latitude, hits.first.longitude);
    setState(() {
      _requestPos = at;
      _requestPosTrusted = true;
      _locationTextUserEdited = false;
    });
    try {
      _mapController.move(at, 15);
    } catch (_) {}
    _scheduleRadiusRpc();
    return at;
  }

  void _scheduleLocationReverse({bool updateSearchField = true}) {
    _locReverseTimer?.cancel();
    final p = _requestPos;
    if (p == null) return;
    final gen = ++_locGen;
    _locReverseTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted || gen != _locGen) return;
      setState(() => _locLoading = true);
      final addr = await NominatimGeocode.reverse(p.latitude, p.longitude);
      if (!mounted || gen != _locGen) return;
      setState(() {
        _locLoading = false;
        if (updateSearchField && addr != null && addr.isNotEmpty) {
          _locationSearchController.value = TextEditingValue(
            text: addr,
            selection: TextSelection.collapsed(offset: addr.length),
          );
          _locationTextUserEdited = false;
        }
        _locSuggestions = [];
      });
    });
  }

  @override
  void dispose() {
    _missionPosTimer?.cancel();
    _radiusDebounce?.cancel();
    _locSuggestTimer?.cancel();
    _locReverseTimer?.cancel();
    _locationSearchController.removeListener(_onLocationSearchTextChanged);
    _locationFocusNode.removeListener(_onLocationFocusChanged);
    _locationSearchController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _requestsOnMap() {
    final uid = currentUserId();
    final anchor = _anchor();
    var list = _radiusRpcRequests.isNotEmpty
        ? List<Map<String, dynamic>>.from(_radiusRpcRequests)
        : widget.globalRequests.where(_isOpenLike).toList();
    if (uid != null) {
      list = list.where((r) => r['user_id']?.toString() != uid).toList();
    }
    if (_radiusRpcRequests.isNotEmpty) return list;
    return list.where((r) {
      final lat = readCoord(r['latitude']);
      final lng = readCoord(r['longitude']);
      if (lat == null || lng == null) return false;
      return withinRadiusMiles(
        viewerLat: anchor.latitude,
        viewerLng: anchor.longitude,
        requestLat: lat,
        requestLng: lng,
        radiusMiles: _radiusMiles,
      );
    }).toList();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _geoHint = null;
    });
    try {
      final pos = await _location.getCurrentPosition();
      if (!mounted) return;
      final here = pos.latLng;
      setState(() {
        _requestPos = here;
        _locating = false;
        _geoHint = null;
        _locationTextUserEdited = false;
        _requestPosTrusted = true;
      });
      _scheduleLocationReverse(updateSearchField: true);
      _scheduleRadiusRpc();
      _fitMapToRadiusCircle();
    } on LocationException catch (e) {
      if (mounted) {
        setState(() {
          _locating = false;
          _geoHint = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locating = false;
          _geoHint = 'Could not read GPS: $e';
        });
      }
    }
  }

  /// Zoom map so the search-radius circle around the request pin is visible (not all markers).
  void _fitMapToRadiusCircle({double panelLeftPad = 320}) {
    final center = _requestPos;
    if (center == null) return;
    final miles = _radiusMiles.clamp(1, 50);
    final latRad = center.latitude * math.pi / 180;
    final cosLat = math.cos(latRad).abs().clamp(0.25, 1.0);
    final deltaLat = miles / 69.0;
    final deltaLng = miles / (69.0 * cosLat);
    final bounds = LatLngBounds(
      LatLng(center.latitude - deltaLat, center.longitude - deltaLng),
      LatLng(center.latitude + deltaLat, center.longitude + deltaLng),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: EdgeInsets.only(
              left: panelLeftPad + 28,
              right: 40,
              top: 100,
              bottom: 100,
            ),
          ),
        );
      } catch (_) {}
    });
  }

  void _fitToPins() {
    final pts = <LatLng>[];
    if (_requestPos != null) pts.add(_requestPos!);
    for (final r in _requestsOnMap()) {
      final la = readCoord(r['latitude']);
      final lo = readCoord(r['longitude']);
      if (la != null && lo != null) pts.add(LatLng(la, lo));
    }
    if (pts.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (pts.length == 1) {
          _mapController.move(pts.first, 14);
          return;
        }
        double south = pts.first.latitude, north = pts.first.latitude;
        double west = pts.first.longitude, east = pts.first.longitude;
        for (final p in pts.skip(1)) {
          south = south < p.latitude ? south : p.latitude;
          north = north > p.latitude ? north : p.latitude;
          west = west < p.longitude ? west : p.longitude;
          east = east > p.longitude ? east : p.longitude;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(LatLng(south, west), LatLng(north, east)),
            padding: const EdgeInsets.only(
                left: 80, right: 36, top: 120, bottom: 120),
          ),
        );
      } catch (_) {}
    });
  }

  void _zoomBy(double delta) {
    try {
      final cam = _mapController.camera;
      _mapController.move(cam.center, (cam.zoom + delta).clamp(3.0, 19.0));
    } catch (_) {}
  }

  IconData _categoryIcon(String? cat) {
    switch (cat) {
      case 'Medical':
        return Icons.medical_services_outlined;
      case 'Safety':
        return Icons.shield_outlined;
      case 'Food & Supplies':
        return Icons.local_grocery_store_outlined;
      case 'Elder Support':
        return Icons.elderly_outlined;
      default:
        return Icons.volunteer_activism;
    }
  }

  Color _categoryColor(String? cat) {
    switch (cat) {
      case 'Medical':
        return Colors.red.shade600;
      case 'Safety':
        return Colors.deepPurple;
      case 'Food & Supplies':
        return Colors.orange.shade700;
      case 'Elder Support':
        return Colors.teal;
      default:
        return AppBranding.primary;
    }
  }

  Future<void> _openPostSheet() async {
    final h = await _resolveRequestPositionForPost();
    if (h == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set your request location: pick a place from search, tap the map, or use your location.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateRequestSheet(
        onActionAccepted: (_, __, ___) => widget.onAfterRequestPosted(),
        initialCategory: _selectedCategory,
        initialLatitude: h.latitude,
        initialLongitude: h.longitude,
        initialRadiusMiles: _radiusMiles,
        initialPlaceDescription:
            _locationSearchController.text.trim().isNotEmpty
                ? _locationSearchController.text.trim()
                : null,
      ),
    );
  }

  /// Groups nearby pins so overlapping markers stay tappable (one tap → picker).
  List<List<Map<String, dynamic>>> _clusterMapRequests(
    List<Map<String, dynamic>> requests, {
    double maxMeters = 55,
  }) {
    const dist = Distance();
    final points = <({Map<String, dynamic> r, LatLng p})>[];
    for (final r in requests) {
      final la = readCoord(r['latitude']);
      final lo = readCoord(r['longitude']);
      if (la == null || lo == null) continue;
      points.add((r: r, p: LatLng(la, lo)));
    }
    final used = List<bool>.filled(points.length, false);
    final clusters = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < points.length; i++) {
      if (used[i]) continue;
      final cluster = <Map<String, dynamic>>[];
      final queue = <int>[i];
      used[i] = true;
      while (queue.isNotEmpty) {
        final j = queue.removeLast();
        cluster.add(points[j].r);
        for (var k = 0; k < points.length; k++) {
          if (used[k]) continue;
          if (dist.as(LengthUnit.Meter, points[j].p, points[k].p) <=
              maxMeters) {
            used[k] = true;
            queue.add(k);
          }
        }
      }
      clusters.add(cluster);
    }
    return clusters;
  }

  LatLng _clusterAnchor(List<Map<String, dynamic>> cluster) {
    var sumLat = 0.0;
    var sumLng = 0.0;
    var n = 0;
    for (final r in cluster) {
      final la = readCoord(r['latitude']);
      final lo = readCoord(r['longitude']);
      if (la == null || lo == null) continue;
      sumLat += la;
      sumLng += lo;
      n++;
    }
    if (n == 0) return _anchor();
    return LatLng(sumLat / n, sumLng / n);
  }

  void _onMapRequestsTapped(List<Map<String, dynamic>> cluster) {
    if (cluster.isEmpty) return;
    if (cluster.length == 1) {
      _showRequestDetailSheet(cluster.first);
      return;
    }
    _showRequestPickerSheet(cluster);
  }

  void _showRequestPickerSheet(List<Map<String, dynamic>> cluster) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppUi.sheetDragHandle(cs),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '${cluster.length} help requests here',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                      12, 0, 12, 12 + MediaQuery.paddingOf(ctx).bottom),
                  itemCount: cluster.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = cluster[i];
                    final title = r['title']?.toString() ?? 'Request';
                    final cat = r['category']?.toString();
                    final urgent =
                        (r['status']?.toString().toLowerCase() == 'urgent');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _categoryColor(cat).withValues(alpha: 0.15),
                        child: Icon(_categoryIcon(cat),
                            color: _categoryColor(cat)),
                      ),
                      title: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (cat != null && cat.isNotEmpty) cat,
                          if (urgent) 'Urgent'
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRequestDetailSheet(r);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRequestDetailSheet(Map<String, dynamic> req) {
    final title = req['title']?.toString() ?? 'Request';
    final desc = req['description']?.toString() ?? '';
    final cs = Theme.of(context).colorScheme;
    final cat = req['category']?.toString();
    final urgent = (req['status']?.toString().toLowerCase() == 'urgent');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppUi.sheetDragHandle(cs),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        _categoryColor(cat).withValues(alpha: 0.15),
                    child: Icon(_categoryIcon(cat),
                        color: _categoryColor(cat), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (cat != null && cat.isNotEmpty)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(cat,
                                    style: const TextStyle(fontSize: 12)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (urgent)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(Icons.priority_high_rounded,
                                    size: 16, color: cs.error),
                                label: const Text('Urgent',
                                    style: TextStyle(fontSize: 12)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                desc.isEmpty ? 'No description provided.' : desc,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RequestDetailsScreen(
                              request: req,
                              title: title,
                              category: cat,
                              openedAsRequestOwner: false,
                            ),
                          ),
                        );
                      },
                      child: const Text('Details'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onOfferHelp(req);
                      },
                      child: const Text('I can help'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor();
    final onMap = _requestsOnMap();
    final markers = <Marker>[];

    if (_requestPos != null) {
      markers.add(
        Marker(
          point: _requestPos!,
          width: 48,
          height: 48,
          child: Tooltip(
            message: 'Your request location (matching radius)',
            child:
                Icon(Icons.location_pin, color: AppBranding.mapPin, size: 44),
          ),
        ),
      );
    }

    for (final cluster in _clusterMapRequests(onMap)) {
      final anchor = _clusterAnchor(cluster);
      final lead = cluster.first;
      final cat = lead['category']?.toString();
      final col = _categoryColor(cat);
      final count = cluster.length;
      markers.add(
        Marker(
          point: anchor,
          width: count > 1 ? 48 : 40,
          height: count > 1 ? 48 : 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onMapRequestsTapped(cluster),
            child: count > 1
                ? Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(_categoryIcon(cat), color: col, size: 34),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Icon(_categoryIcon(cat), color: col, size: 32),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBody: true,
      backgroundColor: scheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelW = (constraints.maxWidth - 24).clamp(280.0, 380.0);
          final topPad = MediaQuery.paddingOf(context).top;
          const headerBarHeight = 52.0;
          const gapAfterHeader = 10.0;
          final panelTop = topPad + 8 + headerBarHeight + gapAfterHeader;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: FlutterMap(
                  key: const ValueKey('map_help_home_map'),
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: anchor,
                    initialZoom: 13,
                    interactionOptions: InteractionOptions(
                      flags: _radiusSliderDragging
                          ? InteractiveFlag.pinchZoom |
                              InteractiveFlag.scrollWheelZoom |
                              InteractiveFlag.doubleTapZoom |
                              InteractiveFlag.rotate
                          : InteractiveFlag.all,
                    ),
                    onTap: (_, latLng) {
                      setState(() {
                        _requestPos = latLng;
                        _geoHint = null;
                        _locationTextUserEdited = false;
                        _requestPosTrusted = true;
                      });
                      _scheduleLocationReverse(updateSearchField: true);
                      _scheduleRadiusRpc();
                      _fitMapToRadiusCircle(panelLeftPad: panelW);
                    },
                    onMapReady: () {
                      if (_requestPos != null) {
                        _fitMapToRadiusCircle(panelLeftPad: panelW);
                      } else {
                        _fitToPins();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'rapid_aid',
                    ),
                    CircleLayer(
                      key: ValueKey<double>(_radiusMiles),
                      circles: [
                        CircleMarker(
                          point: anchor,
                          radius: _radiusMiles * 1609.344,
                          useRadiusInMeter: true,
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderColor: scheme.primary.withValues(alpha: 0.55),
                          borderStrokeWidth: 2.5,
                        ),
                      ],
                    ),
                    if (_routeLinePoints().length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routeLinePoints(),
                            strokeWidth: 4.5,
                            color: _routeLineColor,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Material(
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.12),
                      color: scheme.surfaceContainerLowest,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.35)),
                      ),
                      child: SizedBox(
                        height: headerBarHeight,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'CAN',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: scheme.primary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Community help',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.activeMissionType == 'receiving' ||
                                widget.activeMissionType == 'assisting')
                              FilledButton.tonal(
                                onPressed: widget.onViewTracking,
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Live'),
                              ),
                            IconButton(
                              onPressed: () =>
                                  Supabase.instance.client.auth.signOut(),
                              style: IconButton.styleFrom(
                                  foregroundColor: scheme.onSurfaceVariant),
                              icon: const Icon(Icons.logout_rounded),
                              tooltip: 'Log out',
                            ),
                            IconButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ProfileScreen(
                                        isCurrentUser: true)),
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.12),
                                foregroundColor: scheme.primary,
                              ),
                              icon: const Icon(Icons.person_rounded, size: 22),
                              tooltip: 'Profile',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: panelTop,
                width: panelW,
                bottom: MediaQuery.paddingOf(context).bottom + 68,
                child: SafeArea(
                  bottom: false,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.only(
                          bottom: 16 + MediaQuery.paddingOf(context).bottom),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _yangoSheetCard(
                            scheme: scheme,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _yangoLocationCard(scheme),
                                  const SizedBox(height: 8),
                                  if (_locationFocusNode.hasFocus &&
                                      (_locSuggestLoading ||
                                          _locSuggestions.isNotEmpty))
                                    _addressSuggestionsList(
                                      loading: _locSuggestLoading,
                                      places: _locSuggestions,
                                      onPick: _pickLocationPlace,
                                    ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed:
                                          _locating ? null : _useMyLocation,
                                      icon: _locating
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: scheme.primary,
                                              ),
                                            )
                                          : Icon(Icons.near_me_rounded,
                                              size: 20, color: scheme.primary),
                                      label: Text(_locating
                                          ? 'Locating…'
                                          : 'Use my location'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 14),
                                        alignment: Alignment.center,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ),
                                  if (_geoHint != null) ...[
                                    const SizedBox(height: 6),
                                    Text(_geoHint!,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange.shade800)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _yangoSheetCard(
                            scheme: scheme,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Help type',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurface,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Volunteer support — no payment',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose what you need; helpers respond for free.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant
                                              .withValues(alpha: 0.9),
                                          fontSize: 11.5,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 118,
                                    child: ListView(
                                      scrollDirection: Axis.horizontal,
                                      children: [
                                        _categoryCard(
                                            'Medical',
                                            Icons.medical_services_outlined,
                                            'Urgent care'),
                                        _categoryCard('Safety',
                                            Icons.shield_outlined, 'Stay safe'),
                                        _categoryCard(
                                            'Food & Supplies',
                                            Icons.local_grocery_store_outlined,
                                            'Essentials'),
                                        _categoryCard(
                                            'Elder Support',
                                            Icons.elderly_outlined,
                                            'Check-ins'),
                                        _categoryCard(
                                            'General Help',
                                            Icons.help_center_outlined,
                                            'Anything else'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: scheme.outlineVariant
                                              .withValues(alpha: 0.35)),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Radius',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: scheme.onSurface,
                                              ),
                                        ),
                                        Text(
                                          ' ${_radiusMiles.toStringAsFixed(0)} mi',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: scheme.primary,
                                              ),
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: _radiusMiles.clamp(1, 50),
                                            min: 1,
                                            max: 50,
                                            divisions: 49,
                                            activeColor: scheme.primary,
                                            onChangeStart: (_) {
                                              setState(() =>
                                                  _radiusSliderDragging = true);
                                            },
                                            onChangeEnd: (v) {
                                              setState(() {
                                                _radiusMiles = v;
                                                _radiusSliderDragging = false;
                                              });
                                              _scheduleRadiusRpc();
                                              _fitMapToRadiusCircle(
                                                  panelLeftPad: panelW);
                                            },
                                            onChanged: (v) {
                                              setState(() => _radiusMiles = v);
                                              _scheduleRadiusRpc();
                                              if (_requestPos != null) {
                                                _fitMapToRadiusCircle(
                                                    panelLeftPad: panelW);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${onMap.length} open requests in range (tap pins). Circle ≈ search reach.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 11,
                                          height: 1.3,
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    height: 52,
                                    child: FilledButton(
                                      onPressed: _canSubmitHelpRequest
                                          ? _openPostSheet
                                          : null,
                                      style: FilledButton.styleFrom(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                      ),
                                      child: const Text('Request help',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 88,
                child: Column(
                  children: [
                    _roundMapBtn(Icons.add, () => _zoomBy(1)),
                    const SizedBox(height: 8),
                    _roundMapBtn(Icons.remove, () => _zoomBy(-1)),
                    const SizedBox(height: 8),
                    _roundMapBtn(Icons.my_location, _useMyLocation),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _yangoLocationCard(ColorScheme scheme) {
    final busyLoc = _locLoading || _locSuggestLoading;
    final hint = TextStyle(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
      fontWeight: FontWeight.w500,
      fontSize: 14,
    );
    final value = TextStyle(
      color: scheme.onSurface,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.place_rounded, color: scheme.primary, size: 22),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _locationSearchController,
              focusNode: _locationFocusNode,
              style: value,
              decoration: InputDecoration(
                hintText: 'Your request location',
                hintStyle: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runLocationSearchOrSubmit(),
            ),
          ),
          if (busyLoc)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Search',
              onPressed: _runLocationSearchOrSubmit,
              style: IconButton.styleFrom(foregroundColor: scheme.primary),
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
    );
  }

  /// Yango-style floating white card over the map.
  Widget _yangoSheetCard({required ColorScheme scheme, required Widget child}) {
    return Material(
      elevation: 12,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.14),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _addressSuggestionsList({
    required bool loading,
    required List<NominatimPlace> places,
    required void Function(NominatimPlace) onPick,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: loading && places.isEmpty
              ? const SizedBox(
                  height: 52,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : places.isEmpty
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: places.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.35)),
                        itemBuilder: (context, i) {
                          final p = places[i];
                          return InkWell(
                            onTap: () => onPick(p),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              child: Text(
                                p.shortLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      height: 1.25,
                                    ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _roundMapBtn(IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.95),
      elevation: 2,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      shape: CircleBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 22, color: scheme.primary),
        ),
      ),
    );
  }

  Widget _categoryCard(String label, IconData icon, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.65)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.9),
        elevation: selected ? 0 : 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: 0.55),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _selectedCategory = label),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 120,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 26,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? scheme.primary : scheme.onSurface,
                        height: 1.2,
                      ),
                ),
                const Spacer(),
                Text(
                  'Volunteer',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
