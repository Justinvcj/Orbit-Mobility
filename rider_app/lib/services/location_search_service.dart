// AEGIS LOCATION SEARCH SERVICE
// Architecture: 4-Pillar design — LRU Cache, CancelToken (race-condition killer),
// 500ms debounce, and a Photon → Nominatim failover cascade.

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LocationSearchService {
  // ── SINGLETON ────────────────────────────────────────────────────────────────
  LocationSearchService._internal();
  static final LocationSearchService _instance =
      LocationSearchService._internal();
  factory LocationSearchService() => _instance;

  // ── PILLAR 1: IN-MEMORY LRU CACHE ────────────────────────────────────────────
  // Key: normalised query string → Value: parsed result list
  // Cap at 50 entries; oldest entry is evicted on overflow.
  static const int _maxCacheSize = 50;
  final Map<String, List<Map<String, dynamic>>> _searchCache = {};

  void _cacheWrite(String key, List<Map<String, dynamic>> value) {
    if (_searchCache.length >= _maxCacheSize) {
      // Evict the oldest key (insertion-ordered in Dart LinkedHashMap)
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = value;
  }

  // ── PILLAR 2: CANCELTOKEN (RACE-CONDITION KILLER) ─────────────────────────────
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      // Nominatim requirement — will be overridden per-request when needed
      'User-Agent': 'EquinoxApp/1.0 (orbit.mobility)',
    },
  ));

  CancelToken? _cancelToken;

  void _cancelPending() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Superseded by newer request');
    }
  }

  // ── PILLAR 3: DEBOUNCE ────────────────────────────────────────────────────────
  Timer? _debounceTimer;

  /// Public entry-point.
  ///
  /// Call this directly from [onChanged]. The Completer-based debounce
  /// ensures the network stack is only hit 500 ms after the user stops typing.
  /// Returns an empty list on any error so the app never crashes.
  Future<List<Map<String, dynamic>>> searchPlaces(String query) {
    final completer = Completer<List<Map<String, dynamic>>>();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final result = await _executeSearch(query);
      if (!completer.isCompleted) completer.complete(result);
    });

    return completer.future;
  }

  Future<List<Map<String, dynamic>>> _executeSearch(String rawQuery) async {
    final query = rawQuery.trim();

    // Guard: don't fire for very short queries
    if (query.length < 3) return [];

    // ── PILLAR 1: Cache hit ───────────────────────────────────────────────────
    final cacheKey = query.toLowerCase();
    if (_searchCache.containsKey(cacheKey)) {
      debugPrint('[Aegis] Cache HIT for "$cacheKey"');
      return _searchCache[cacheKey]!;
    }

    // ── PILLAR 2: Cancel previous in-flight request ───────────────────────────
    _cancelPending();
    _cancelToken = CancelToken();

    // ── PILLAR 4: GEOCODING CASCADE ───────────────────────────────────────────
    try {
      final results = await _tryPhoton(query);
      _cacheWrite(cacheKey, results);
      return results;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // Not an error — request was deliberately superseded
        debugPrint('[Aegis] Request cancelled for "$query"');
        return [];
      }

      // Rate-limit (HTTP 429) or timeout → fall back to Nominatim
      final isRecoverable = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          (e.response?.statusCode == 429);

      if (isRecoverable) {
        debugPrint('[Aegis] Photon failed (${e.type} / ${e.response?.statusCode}). Falling back to Nominatim.');
        try {
          // Create a fresh token — the old one was used for Photon
          _cancelToken = CancelToken();
          final fallback = await _tryNominatim(query);
          _cacheWrite(cacheKey, fallback);
          return fallback;
        } catch (fallbackErr) {
          debugPrint('[Aegis] Nominatim fallback also failed: $fallbackErr');
          return [];
        }
      }

      debugPrint('[Aegis] Photon non-recoverable error: $e');
      return [];
    } catch (e) {
      debugPrint('[Aegis] Unexpected error: $e');
      return [];
    }
  }

  // ── PRIMARY: PHOTON (Komoot) ──────────────────────────────────────────────────
  // Biased towards Coimbatore coordinates (lat=11.0168, lon=76.9558)
  Future<List<Map<String, dynamic>>> _tryPhoton(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final url =
        'https://photon.komoot.io/api/?q=$encodedQuery&lat=11.0168&lon=76.9558&limit=5';

    final response = await _dio.get(
      url,
      cancelToken: _cancelToken,
      options: Options(
        // Photon doesn't enforce a specific UA but it's good practice
        headers: {'User-Agent': 'EquinoxApp/1.0 (orbit.mobility)'},
      ),
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final features = (response.data['features'] as List<dynamic>?) ?? [];
    return _parsePhotonFeatures(features);
  }

  List<Map<String, dynamic>> _parsePhotonFeatures(List<dynamic> features) {
    return features.map<Map<String, dynamic>>((f) {
      final props = (f['properties'] as Map<dynamic, dynamic>?) ?? {};
      final coords = (f['geometry']?['coordinates'] as List<dynamic>?) ??
          [0.0, 0.0]; // [lon, lat]

      final primaryText = (props['name']?.toString() ??
              props['street']?.toString() ??
              props['locality']?.toString() ??
              props['neighbourhood']?.toString() ??
              'Unknown Location');

      final secParts = <String>[];
      for (final key in ['street', 'locality', 'neighbourhood', 'city', 'state']) {
        final val = props[key]?.toString();
        if (val != null && val != primaryText) secParts.add(val);
      }
      final secondaryText =
          secParts.isNotEmpty ? secParts.join(', ') : 'Details unavailable';

      return {
        'display_name': '$primaryText, $secondaryText',
        'primary_text': primaryText,
        'secondary_text': secondaryText,
        'lat': (coords[1] as num).toString(),
        'lon': (coords[0] as num).toString(),
      };
    }).toList();
  }

  // ── FALLBACK: OSM NOMINATIM ───────────────────────────────────────────────────
  // CRITICAL: Custom User-Agent is MANDATORY per Nominatim usage policy.
  Future<List<Map<String, dynamic>>> _tryNominatim(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    const nominatimUrl = 'https://nominatim.openstreetmap.org/search';

    final response = await _dio.get(
      nominatimUrl,
      queryParameters: {
        'q': encodedQuery,
        'format': 'json',
        'limit': '5',
        'viewbox': '76.8,11.1,77.1,10.9',
        'bounded': '1',
      },
      cancelToken: _cancelToken,
      options: Options(
        // MANDATORY for Nominatim — without this header, requests will be blocked.
        headers: {'User-Agent': 'EquinoxApp/1.0 (orbit.mobility)'},
      ),
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: RequestOptions(path: nominatimUrl),
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final results = (response.data as List<dynamic>?) ?? [];
    return _parseNominatimResults(results);
  }

  List<Map<String, dynamic>> _parseNominatimResults(List<dynamic> results) {
    return results.map<Map<String, dynamic>>((r) {
      final rawName = r['display_name']?.toString() ?? 'Unknown Location';
      final parts = rawName.split(',');
      final primaryText = parts.isNotEmpty ? parts.first.trim() : rawName;
      final secondaryText =
          parts.length > 1 ? parts.sublist(1).join(',').trim() : '';

      return {
        'display_name': rawName,
        'primary_text': primaryText,
        'secondary_text': secondaryText,
        'lat': r['lat']?.toString() ?? '0.0',
        'lon': r['lon']?.toString() ?? '0.0',
      };
    }).toList();
  }

  /// Cancels any pending debounce and in-flight requests.
  /// Call from [StatefulWidget.dispose].
  void dispose() {
    _debounceTimer?.cancel();
    _cancelPending();
  }
}
