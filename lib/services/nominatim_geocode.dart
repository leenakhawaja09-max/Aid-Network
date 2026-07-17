import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenStreetMap Nominatim — reverse / forward geocoding.
/// Uses caching and a stable User-Agent per [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/).
/// All queries are restricted to **Pakistan** (`countrycodes=pk` + result checks).
abstract final class NominatimGeocode {
  static const _userAgent = 'RapidAid/1.0 (community aid app)';
  static const String _countryCodes = 'pk';

  static final Map<String, String> _reverseCache = {};
  static final Map<String, List<NominatimPlace>> _searchCache = {};

  static String _reverseKey(double lat, double lng) =>
      'v4pk|${lat.toStringAsFixed(5)}|${lng.toStringAsFixed(5)}';

  /// True if Nominatim JSON is inside Pakistan (by `address.country_code` or display name).
  static bool isPakistanResult(Map<String, dynamic> json) {
    final addrRaw = json['address'];
    if (addrRaw is Map<String, dynamic>) {
      final cc = addrRaw['country_code']?.toString().toLowerCase().trim();
      if (cc == 'pk') return true;
    }
    final dn = json['display_name']?.toString() ?? '';
    final parts = dn.toLowerCase().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty && parts.last == 'pakistan';
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static bool _ciEq(String a, String b) => a.toLowerCase() == b.toLowerCase();

  /// Tehsil / district / division / province / postcode — not shown in short labels.
  static bool _isAdminNoise(String? s) {
    if (s == null) return true;
    final t = s.trim();
    if (t.isEmpty) return true;
    final low = t.toLowerCase();
    if (low == 'pakistan') return true;
    if (low == 'punjab' || low == 'sindh' || low == 'balochistan' || low == 'khyber pakhtunkhwa' || low == 'gilgit-baltistan') {
      return true;
    }
    if (RegExp(r'^\d{4,7}$').hasMatch(low)) return true;
    if (low.contains('tehsil')) return true;
    if (low.endsWith(' district') || low.contains(' district,')) return true;
    if (low.endsWith(' division') || low.contains(' division,')) return true;
    return false;
  }

  static String? _cityFromCounty(String? county) {
    if (county == null || county.isEmpty) return null;
    final low = county.toLowerCase();
    if (low.endsWith(' district')) {
      return county.substring(0, county.length - 9).trim();
    }
    return null;
  }

  /// City / town name only (no tehsil, no `… District` string).
  static String? _resolveCityName(Map<String, String> addr) {
    for (final k in ['city', 'municipality']) {
      final v = addr[k];
      if (v != null && v.isNotEmpty && !_isAdminNoise(v)) return v;
    }
    final cd = addr['city_district'];
    if (cd != null && cd.isNotEmpty && !_isAdminNoise(cd)) return cd;
    final fromCounty = _cityFromCounty(addr['county']);
    if (fromCounty != null && !_isAdminNoise(fromCounty)) return fromCounty;
    final town = addr['town'];
    if (town != null && town.isNotEmpty && !_isAdminNoise(town)) return town;
    final vill = addr['village'];
    if (vill != null && vill.isNotEmpty && !_isAdminNoise(vill)) return vill;
    return null;
  }

  static void _appendLabelPart(List<String> out, String? part) {
    if (part == null) return;
    final t = part.trim();
    if (t.isEmpty || _isAdminNoise(t)) return;
    if (out.isNotEmpty && _ciEq(out.last, t)) return;
    if (out.any((e) => _ciEq(e, t))) return;
    out.add(t);
  }

  /// Short label: landmark (optional) → house + road → block/area → town → city.
  /// Omits Tehsil, District, Division, province, postcode, Pakistan.
  static String shortLabelFromNominatimJson(Map<String, dynamic> json) {
    final dn = json['display_name']?.toString().trim() ?? '';
    final addrRaw = json['address'];
    if (addrRaw is Map<String, dynamic>) {
      final addr = addrRaw.map((k, v) => MapEntry(k.toString(), v?.toString().trim() ?? ''));
      final fromStructured = _labelFromAddressMap(json, addr);
      if (fromStructured != null && fromStructured.isNotEmpty) return fromStructured;
    }
    if (dn.isNotEmpty) return _shortenDisplayNameComma(dn);
    return dn;
  }

  static String? _labelFromAddressMap(Map<String, dynamic> json, Map<String, String> addr) {
    final out = <String>[];

    final poi = json['name']?.toString().trim();
    if (poi != null && poi.isNotEmpty && !_isAdminNoise(poi)) {
      _appendLabelPart(out, poi);
    }

    final hn = addr['house_number'];
    final road = addr['road'];
    String? street;
    if (hn != null && hn.isNotEmpty && road != null && road.isNotEmpty && !_isAdminNoise(road)) {
      street = '${hn.trim()} ${road.trim()}'.trim();
    } else if (road != null && road.isNotEmpty && !_isAdminNoise(road)) {
      street = road.trim();
    } else if (hn != null && hn.isNotEmpty) {
      street = hn.trim();
    }
    final houseName = addr['house_name'];
    if (houseName != null && houseName.isNotEmpty && !_isAdminNoise(houseName)) {
      street = (street == null || street.isEmpty)
          ? houseName.trim()
          : '${houseName.trim()}, $street';
    }
    _appendLabelPart(out, street);

    final blockOrArea = _firstNonEmpty([
      addr['city_block'],
      addr['locality'],
      addr['suburb'],
      addr['neighbourhood'],
      addr['quarter'],
    ]);
    _appendLabelPart(out, blockOrArea);

    final cityResolved = _resolveCityName(addr);
    final townLike = _firstNonEmpty([
      addr['hamlet'],
      addr['village'],
    ]);
    if (townLike != null &&
        !_isAdminNoise(townLike) &&
        (cityResolved == null || !_ciEq(townLike, cityResolved))) {
      _appendLabelPart(out, townLike);
    } else {
      final townOnly = addr['town'];
      if (townOnly != null &&
          townOnly.isNotEmpty &&
          !_isAdminNoise(townOnly) &&
          (cityResolved == null || !_ciEq(townOnly, cityResolved))) {
        _appendLabelPart(out, townOnly);
      }
    }

    _appendLabelPart(out, cityResolved);

    if (out.isEmpty) return null;
    return out.join(', ');
  }

  /// Fallback when structured `address` is thin: keep only non-admin segments before Pakistan.
  static String _shortenDisplayNameComma(String full) {
    final parts = full.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return full;

    final kept = <String>[];
    String? cityFromDistrict;

    for (final p in parts) {
      final low = p.toLowerCase();
      if (low == 'pakistan') break;
      if (low.endsWith(' district')) {
        cityFromDistrict = p.substring(0, p.length - 9).trim();
        continue;
      }
      if (_isAdminNoise(p)) continue;
      if (kept.length >= 5) break;
      kept.add(p);
    }

    if (cityFromDistrict != null &&
        cityFromDistrict.isNotEmpty &&
        !_isAdminNoise(cityFromDistrict)) {
      if (kept.isEmpty) return cityFromDistrict;
      if (!_ciEq(kept.last, cityFromDistrict)) {
        kept.add(cityFromDistrict);
      }
    }

    return kept.isEmpty ? full : kept.join(', ');
  }

  /// Compact label for [lat], [lng], or `null` if lookup fails.
  static Future<String?> reverse(double lat, double lng) async {
    final key = _reverseKey(lat, lng);
    if (_reverseCache.containsKey(key)) return _reverseCache[key];

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'json',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'addressdetails': '1',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (!isPakistanResult(decoded)) return null;
      final label = shortLabelFromNominatimJson(decoded);
      if (label.isNotEmpty) {
        _reverseCache[key] = label;
        return label;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Search by free text (e.g. "Lake City M Block Lahore").
  static Future<List<NominatimPlace>> search(String query, {int limit = 5}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final cacheKey = 'v4pk|${q.toLowerCase()}';
    if (_searchCache.containsKey(cacheKey)) return _searchCache[cacheKey]!;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'q': q,
        'limit': limit.clamp(1, 10).toString(),
        'addressdetails': '1',
        'countrycodes': _countryCodes,
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return [];
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        return [];
      }
      final out = <NominatimPlace>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        if (!isPakistanResult(item)) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        final dn = item['display_name']?.toString().trim();
        if (lat == null || lon == null || dn == null || dn.isEmpty) continue;
        final short = shortLabelFromNominatimJson(item);
        out.add(NominatimPlace(
          latitude: lat,
          longitude: lon,
          displayName: dn,
          shortLabel: short.isNotEmpty ? short : dn,
        ));
      }
      if (out.isNotEmpty) _searchCache[cacheKey] = out;
      return out;
    } catch (_) {
      return [];
    }
  }
}

class NominatimPlace {
  final double latitude;
  final double longitude;
  final String displayName;
  /// Map-style line: POI → house / road → block / town → city (no admin chain).
  final String shortLabel;

  NominatimPlace({
    required this.latitude,
    required this.longitude,
    required this.displayName,
    String? shortLabel,
  }) : shortLabel = (shortLabel != null && shortLabel.isNotEmpty) ? shortLabel : displayName;
}
