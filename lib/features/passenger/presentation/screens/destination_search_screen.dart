import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/ride_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geohash_util.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import 'ride_options_screen.dart';

/// A single destination search result.
class _PlaceResult {
  final String label;
  final double lat;
  final double lng;

  const _PlaceResult({required this.label, required this.lat, required this.lng});
}

/// "Where to?" screen — first step of the Ride Request Flow. Lets the
/// passenger search for a destination (geocoded via the Geocoding API),
/// pick from saved places, then computes a route from the current location
/// before handing off to [RideOptionsScreen].
class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() => _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends ConsumerState<DestinationSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<_PlaceResult> _results = [];
  bool _searching = false;
  bool _resolvingRoute = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final locations = await locationFromAddress(query);
      final results = <_PlaceResult>[];

      for (final loc in locations.take(5)) {
        String label = query;
        try {
          final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            label = [p.street, p.locality, p.administrativeArea]
                .where((e) => e != null && e.isNotEmpty)
                .join(', ');
            if (label.isEmpty) label = query;
          }
        } catch (_) {
          // Keep the query text as the label if reverse-geocoding fails.
        }

        results.add(_PlaceResult(label: label, lat: loc.latitude, lng: loc.longitude));
      }

      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _error = 'No results found for "$query"';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectDestination(_PlaceResult place) async {
    setState(() => _resolvingRoute = true);

    try {
      final locationService = ref.read(locationServiceProvider);
      final position = await locationService.getCurrentPosition();

      final pickup = GeoPoint2(
        lat: position.latitude,
        lng: position.longitude,
        address: 'Current location',
        geohash: GeohashUtil.encode(
          position.latitude,
          position.longitude,
          precision: AppConstants.geohashPrecision,
        ),
      );

      final dropoff = GeoPoint2(
        lat: place.lat,
        lng: place.lng,
        address: place.label,
        geohash: GeohashUtil.encode(
          place.lat,
          place.lng,
          precision: AppConstants.geohashPrecision,
        ),
      );

      // Route calculation disabled while Maps API is unavailable.
      const route = null;

      if (!mounted) return;

      context.pushNamed(
        AppRoutes.rideOptions,
        extra: RideOptionsArgs(
          pickup: pickup,
          dropoff: dropoff,
          distanceKm: route?.distanceKm ?? 0,
          durationMin: route?.durationMin ?? 0,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not plan route: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resolvingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final savedPlaces = profile?.savedPlaces ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Where to?')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search for a destination',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: _search,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ),
              Expanded(
                child: ListView(
                  children: [
                    if (_results.isNotEmpty) ...[
                      const _SectionLabel('Search results'),
                      ..._results.map(
                        (r) => ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(r.label),
                          onTap: () => _selectDestination(r),
                        ),
                      ),
                    ],
                    if (savedPlaces.isNotEmpty) ...[
                      const _SectionLabel('Saved places'),
                      ...savedPlaces.map(
                        (place) => ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(place.label),
                          subtitle: place.address != null ? Text(place.address!) : null,
                          onTap: () => _selectDestination(
                            _PlaceResult(label: place.label, lat: place.lat, lng: place.lng),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_resolvingRoute)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
