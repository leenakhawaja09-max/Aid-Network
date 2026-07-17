import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/nominatim_geocode.dart';
import '../utils/app_user.dart';

class CreateRequestSheet extends StatefulWidget {
  final Function(String, String, String) onActionAccepted;
  final String? initialCategory;
  final double? initialLatitude;
  final double? initialLongitude;
  final double? initialRadiusMiles;
  @Deprecated('Use initialRadiusMiles')
  double? get initialHorizonMiles => initialRadiusMiles;
  /// Human-readable place when opening from the map (avoids an extra lookup).
  final String? initialPlaceDescription;

  const CreateRequestSheet({
    super.key,
    required this.onActionAccepted,
    this.initialCategory,
    this.initialLatitude,
    this.initialLongitude,
    double? initialRadiusMiles,
    this.initialPlaceDescription,
    @Deprecated('Use initialRadiusMiles') double? initialHorizonMiles,
  }) : initialRadiusMiles = initialRadiusMiles ?? initialHorizonMiles;

  @override
  State<CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends State<CreateRequestSheet> {
  String selectedType = "General";
  String selectedCategory = "General Help";
  double helpRange = 5.0;
  bool _isLoading = false;
  bool _locating = false;
  double? _pickedLat;
  double? _pickedLng;
  final MapController _mapController = MapController();
  final TextEditingController _radiusController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final FocusNode _placeFocusNode = FocusNode();
  Timer? _placeReverseTimer;
  Timer? _placeSuggestTimer;
  int _placeGen = 0;
  int _placeSuggestSeq = 0;
  bool _placeSearchLoading = false;
  bool _placeSuggestLoading = false;
  List<NominatimPlace> _placeSuggestions = [];
  /// True after the user edits the place field — posted coords must come from search, not stale GPS/map.
  bool _placeTextUserEdited = false;
  /// True when lat/lng came from GPS, map tap, or picking a suggestion (not stale).
  bool _coordinatesTrusted = false;
  late final VoidCallback _descriptionListener;

  @override
  void initState() {
    super.initState();
    _descriptionListener = () {
      if (mounted) setState(() {});
    };
    _descriptionController.addListener(_descriptionListener);
    _placeFocusNode.addListener(_onPlaceFocusChanged);

    if (widget.initialCategory != null && widget.initialCategory!.trim().isNotEmpty) {
      selectedCategory = widget.initialCategory!.trim();
    }
    if (widget.initialRadiusMiles != null && widget.initialRadiusMiles! > 0) {
      helpRange = widget.initialRadiusMiles!.clamp(0.5, 250.0);
      _radiusController.text = helpRange.toStringAsFixed(1);
    }
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _pickedLat = widget.initialLatitude;
      _pickedLng = widget.initialLongitude;
      final pre = widget.initialPlaceDescription?.trim();
      if (pre != null && pre.isNotEmpty) {
        _placeController.text = pre;
        _coordinatesTrusted = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _schedulePlaceReverse(updatePlaceField: _placeController.text.trim().isEmpty);
        });
      }
      _coordinatesTrusted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(widget.initialLatitude!, widget.initialLongitude!),
            14,
          );
        }
      });
    }

    _placeController.addListener(_onPlaceTextChanged);
  }

  void _schedulePlaceReverse({bool updatePlaceField = true}) {
    _placeReverseTimer?.cancel();
    final lat = _pickedLat;
    final lng = _pickedLng;
    if (lat == null || lng == null) return;
    final gen = ++_placeGen;
    _placeReverseTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || gen != _placeGen) return;
      setState(() => _placeSearchLoading = true);
      final addr = await NominatimGeocode.reverse(lat, lng);
      if (!mounted || gen != _placeGen) return;
      setState(() {
        _placeSearchLoading = false;
        if (updatePlaceField && addr != null && addr.isNotEmpty) {
          _placeController.value = TextEditingValue(
            text: addr,
            selection: TextSelection.collapsed(offset: addr.length),
          );
          _placeTextUserEdited = false;
        }
        _placeSuggestions = [];
      });
    });
  }

  void _onPlaceFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onPlaceTextChanged() {
    _placeTextUserEdited = true;
    _coordinatesTrusted = false;
    _placeReverseTimer?.cancel();
    _placeSuggestTimer?.cancel();
    if (_placeController.text.trim().length < 3) {
      if (_placeSuggestions.isNotEmpty || _placeSuggestLoading) {
        setState(() {
          _placeSuggestions = [];
          _placeSuggestLoading = false;
        });
      }
      return;
    }
    final seq = ++_placeSuggestSeq;
    _placeSuggestTimer = Timer(const Duration(milliseconds: 450), () => _fetchPlaceSuggestions(seq));
  }

  Future<void> _fetchPlaceSuggestions(int seq) async {
    final q = _placeController.text.trim();
    if (q.length < 3 || seq != _placeSuggestSeq) return;
    if (mounted) setState(() => _placeSuggestLoading = true);
    final hits = await NominatimGeocode.search(q, limit: 10);
    if (!mounted || seq != _placeSuggestSeq) return;
    setState(() {
      _placeSuggestLoading = false;
      _placeSuggestions = hits;
    });
  }

  Future<void> _runPlaceSearchOrSubmit() async {
    final q = _placeController.text.trim();
    if (q.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type at least 2 characters, then search or pick a suggestion.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _placeSuggestTimer?.cancel();
    _placeSuggestSeq++;
    setState(() => _placeSuggestLoading = true);
    final hits = await NominatimGeocode.search(q, limit: 10);
    if (!mounted) return;
    setState(() {
      _placeSuggestLoading = false;
      _placeSuggestions = hits;
    });
    if (_placeSuggestions.length == 1) {
      _pickPlaceSuggestion(_placeSuggestions.first);
      return;
    }
    if (_placeSuggestions.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching places — try adding city or area.')),
      );
    }
  }

  void _pickPlaceSuggestion(NominatimPlace p) {
    _placeReverseTimer?.cancel();
    _placeGen++;
    _placeSuggestSeq++;
    setState(() {
      _pickedLat = p.latitude;
      _pickedLng = p.longitude;
      _placeController.text = p.shortLabel;
      _placeSuggestions = [];
      _placeTextUserEdited = false;
      _coordinatesTrusted = true;
    });
    _placeFocusNode.unfocus();
    _mapController.move(LatLng(p.latitude, p.longitude), 14);
  }

  /// Resolve lat/lng from typed place when user did not pick GPS / map / suggestion.
  Future<bool> _resolveCoordinatesForPost() async {
    if (_coordinatesTrusted && !_placeTextUserEdited) {
      return _pickedLat != null && _pickedLng != null;
    }
    final q = _placeController.text.trim();
    if (q.length < 2) {
      return _pickedLat != null && _pickedLng != null;
    }
    setState(() => _placeSearchLoading = true);
    final hits = await NominatimGeocode.search(q, limit: 5);
    if (!mounted) return false;
    setState(() => _placeSearchLoading = false);
    if (hits.isEmpty) return false;
    final p = hits.first;
    setState(() {
      _pickedLat = p.latitude;
      _pickedLng = p.longitude;
      _coordinatesTrusted = true;
      _placeTextUserEdited = false;
    });
    _mapController.move(LatLng(p.latitude, p.longitude), 14);
    return true;
  }

  @override
  void dispose() {
    _placeSuggestTimer?.cancel();
    _placeReverseTimer?.cancel();
    _placeController.removeListener(_onPlaceTextChanged);
    _placeFocusNode.removeListener(_onPlaceFocusChanged);
    _descriptionController.removeListener(_descriptionListener);
    _descriptionController.dispose();
    _placeController.dispose();
    _placeFocusNode.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _useDeviceLocation() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _pickedLat = pos.latitude;
        _pickedLng = pos.longitude;
        _placeTextUserEdited = false;
        _coordinatesTrusted = true;
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
      _schedulePlaceReverse(updatePlaceField: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read GPS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _post() async {
    String userText = _descriptionController.text;
    if (userText.isEmpty) return;

    final uid = currentUserId();
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required.')),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isLoading = true);
    final resolved = await _resolveCoordinatesForPost();
    if (!resolved) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find that place. Pick a suggestion from the list, tap the map, or use current location.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final lat = _pickedLat;
    final lng = _pickedLng;
    if (lat == null || lng == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Set where you need help: search and pick a place, tap the map, or use GPS.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      String userName = 'User';
      try {
        final prof = await Supabase.instance.client
            .from('profiles')
            .select('full_name')
            .eq('id', uid)
            .maybeSingle();
        final n = prof?['full_name']?.toString().trim();
        if (n != null && n.isNotEmpty) userName = n;
      } catch (_) {}

      await Supabase.instance.client.from('requests').insert({
        'title': selectedCategory,
        'description': userText,
        'category': selectedCategory,
        'distance': "${helpRange.toStringAsFixed(1)} miles",
        'status': selectedType == "Urgent" ? "pending" : "created",
        'user_id': uid,
        'userName': userName,
        'current_radius': helpRange,
        'latitude': lat,
        'longitude': lng,
      }).timeout(const Duration(seconds: 30));

      if (mounted) {
        widget.onActionAccepted(selectedCategory, userText, "${helpRange.toStringAsFixed(1)} miles");
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text("Request live — helpers within your radius will see it."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Request insert: $e");
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Could not post: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mapLat = _pickedLat ?? 24.8607;
    final mapLng = _pickedLng ?? 67.0011;
    final selectedLatLng = LatLng(mapLat, mapLng);

    return Container(
      padding: EdgeInsets.only(
        top: 8,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
                Expanded(
                  child: Text(
                    'Create request',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Priority', style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeCard("General", "Standard assistance", Icons.help_outline, selectedType == "General"),
                const SizedBox(width: 15),
                _buildTypeCard("Urgent", "Emergency help", Icons.report_problem_outlined, selectedType == "Urgent"),
              ],
            ),
            const SizedBox(height: 20),
            Text('Category', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryIcon("Medical", Icons.medical_services_outlined),
                  _buildCategoryIcon("Safety", Icons.shield_outlined),
                  _buildCategoryIcon("Food & Supplies", Icons.local_grocery_store_outlined),
                  _buildCategoryIcon("Elder Support", Icons.elderly_outlined),
                  _buildCategoryIcon("General Help", Icons.help_center_outlined),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('Describe your request', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'What do you need help with?',
              ).applyDefaults(Theme.of(context).inputDecorationTheme),
            ),
            const SizedBox(height: 20),
            Text('Where you need help', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _placeController,
              focusNode: _placeFocusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runPlaceSearchOrSubmit(),
              decoration: InputDecoration(
                hintText: 'e.g. Lake City M Block, Lahore',
                isDense: true,
                suffixIcon: (_placeSearchLoading || _placeSuggestLoading)
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Search places',
                        icon: const Icon(Icons.search_rounded),
                        onPressed: _runPlaceSearchOrSubmit,
                      ),
              ).applyDefaults(Theme.of(context).inputDecorationTheme),
            ),
            if (_placeFocusNode.hasFocus && (_placeSuggestLoading || _placeSuggestions.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: scheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: _placeSuggestLoading && _placeSuggestions.isEmpty
                      ? const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _placeSuggestions.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
                            itemBuilder: (context, i) {
                              final p = _placeSuggestions[i];
                              return InkWell(
                                onTap: () => _pickPlaceSuggestion(p),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Text(
                                    p.shortLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, height: 1.25),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _locating ? null : _useDeviceLocation,
              icon: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(_locating ? 'Getting location…' : 'Use my current location'),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  height: 210,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: selectedLatLng,
                      initialZoom: 14,
                      onTap: (_, latLng) {
                        setState(() {
                          _pickedLat = latLng.latitude;
                          _pickedLng = latLng.longitude;
                          _placeTextUserEdited = false;
                          _coordinatesTrusted = true;
                        });
                        _schedulePlaceReverse(updatePlaceField: true);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'rapid_aid',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selectedLatLng,
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: AppBranding.mapPin,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the map to move the pin, or search for a place above.',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Quick radius:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  _quickRangeChip(5.0),
                  _quickRangeChip(10.0),
                  _quickRangeChip(25.0),
                  _quickRangeChip(50.0),
                  _quickRangeChip(100.0),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _radiusController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Custom radius (miles)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final custom = double.tryParse(_radiusController.text.trim());
                    if (custom == null || custom < 0.5 || custom > 250) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid radius from 0.5 to 250 miles.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      helpRange = custom;
                    });
                  },
                  child: const Text('Set'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Search radius: ${helpRange.toStringAsFixed(1)} mi',
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Slider(
              value: helpRange,
              min: 0.5,
              max: 100.0,
              divisions: 199,
              activeColor: scheme.primary,
              onChanged: (val) => setState(() => helpRange = val),
            ),
            Text(
              'Helpers only see your request if they are within this distance of the pin above.',
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: _isLoading ? null : _post,
                child: _isLoading
                    ? SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: scheme.onPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.send_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Post request',
                            style: textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard(String title, String sub, IconData icon, bool isSelected) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedType = title),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.8),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? scheme.primary : scheme.onSurfaceVariant, size: 30),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? scheme.primary : scheme.onSurface,
                ),
              ),
              Text(
                sub,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryIcon(String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = selectedCategory == label;
    return GestureDetector(
      onTap: () => setState(() => selectedCategory = label),
      child: Container(
        margin: const EdgeInsets.only(right: 15),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.8),
                ),
              ),
              child: Icon(icon, color: isSelected ? scheme.primary : scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickRangeChip(double value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('${value.toInt()} mi'),
        selected: helpRange == value,
        onSelected: (_) => setState(() => helpRange = value),
        visualDensity: VisualDensity.compact,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: helpRange == value ? FontWeight.w700 : FontWeight.w500,
          color: helpRange == value ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
