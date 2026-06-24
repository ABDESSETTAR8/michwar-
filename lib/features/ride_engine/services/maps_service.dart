import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../core/utils/geohash_util.dart';

/// Result of a route lookup between two points.
class RouteResult {
  final List<LatLng> polylinePoints;
  final double distanceKm;
  final double durationMin;

  const RouteResult({
    required this.polylinePoints,
    required this.distanceKm,
    required this.durationMin,
  });
}

/// Wraps the Google Maps Directions & Distance Matrix APIs
/// (Technical Constraints: "Google Maps SDK (Maps, Directions, Distance
/// Matrix API)").
///
/// IMPORTANT: [apiKey] must be supplied at runtime (e.g. via `--dart-define
/// GOOGLE_MAPS_API_KEY=...` or read from `.env`). A placeholder is used by
/// default so the app still compiles without credentials configured.
class MapsService {
  MapsService({String? apiKey})
      : _apiKey = apiKey ?? const String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  final String _apiKey;
  final PolylinePoints _polylinePoints = PolylinePoints();

  bool get hasApiKey => _apiKey.isNotEmpty;

  /// Fetches a driving route (polyline + distance + ETA) between [origin]
  /// and [destination] via the Directions API.
  Future<RouteResult?> getRoute(LatLng origin, LatLng destination) async {
    if (!hasApiKey) {
      // No key configured — fall back to a straight-line estimate so the
      // UI remains usable in development/testing.
      return _straightLineFallback(origin, destination);
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'key': _apiKey,
    });

    try {
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        debugPrint('Directions API error: ${data['status']}');
        return _straightLineFallback(origin, destination);
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final overviewPolyline =
          (route['overview_polyline'] as Map<String, dynamic>)['points'] as String;

      final points = _polylinePoints
          .decodePolyline(overviewPolyline)
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();

      return RouteResult(
        polylinePoints: points,
        distanceKm: (leg['distance']['value'] as num) / 1000.0,
        durationMin: (leg['duration']['value'] as num) / 60.0,
      );
    } catch (e) {
      debugPrint('Directions API request failed: $e');
      return _straightLineFallback(origin, destination);
    }
  }

  /// Uses the Distance Matrix API to get ETA/distance for multiple
  /// candidate drivers at once (e.g. ranking nearby drivers by real travel
  /// time rather than straight-line distance).
  Future<List<RouteResult>> getDistanceMatrix(
    LatLng origin,
    List<LatLng> destinations,
  ) async {
    if (!hasApiKey || destinations.isEmpty) {
      return destinations
          .map((d) => _straightLineFallback(origin, d))
          .toList();
    }

    final destinationsParam =
        destinations.map((d) => '${d.latitude},${d.longitude}').join('|');

    final uri = Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
      'origins': '${origin.latitude},${origin.longitude}',
      'destinations': destinationsParam,
      'mode': 'driving',
      'key': _apiKey,
    });

    try {
      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['status'] != 'OK') {
        return destinations
            .map((d) => _straightLineFallback(origin, d))
            .toList();
      }

      final elements = (data['rows'] as List).first['elements'] as List;
      return List.generate(elements.length, (i) {
        final element = elements[i] as Map<String, dynamic>;
        if (element['status'] != 'OK') {
          return _straightLineFallback(origin, destinations[i]);
        }
        return RouteResult(
          polylinePoints: const [],
          distanceKm: (element['distance']['value'] as num) / 1000.0,
          durationMin: (element['duration']['value'] as num) / 60.0,
        );
      });
    } catch (e) {
      debugPrint('Distance Matrix API request failed: $e');
      return destinations
          .map((d) => _straightLineFallback(origin, d))
          .toList();
    }
  }

  /// Used when no Google Maps API key is configured (e.g. during local
  /// testing). Computes great-circle distance and assumes an average
  /// urban driving speed of 30 km/h.
  RouteResult _straightLineFallback(LatLng origin, LatLng destination) {
    final distanceKm = GeohashUtil.distanceKm(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final durationMin = (distanceKm / 30.0) * 60.0;

    return RouteResult(
      polylinePoints: [origin, destination],
      distanceKm: distanceKm,
      durationMin: durationMin,
    );
  }
}
