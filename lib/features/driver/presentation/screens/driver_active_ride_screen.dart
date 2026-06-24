import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/map_placeholder.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/models/ride_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geohash_util.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import '../../../shared/presentation/widgets/sos_button.dart';

/// Driver-side "Active Ride" screen — covers navigation to pickup, arrival,
/// the trip itself, and triggers `completeRide` with the actual tracked
/// distance/duration (Section 6 — "Cloud Function Logic" requires the
/// server, not the client, to compute the final fare from these values).
class DriverActiveRideScreen extends ConsumerStatefulWidget {
  const DriverActiveRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<DriverActiveRideScreen> createState() => _DriverActiveRideScreenState();
}

class _DriverActiveRideScreenState extends ConsumerState<DriverActiveRideScreen> {
  StreamSubscription? _positionSub;
  double _trackedDistanceKm = 0;
  DateTime? _tripStartedAt;
  ({double latitude, double longitude})? _lastPosition;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(offlineSyncServiceProvider).start(widget.rideId);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  void _startTrackingTrip() {
    if (_positionSub != null) return;
    _tripStartedAt = DateTime.now();

    final locationService = ref.read(locationServiceProvider);
    locationService.setActivityState(GpsActivityState.activeTrip);
    locationService.start();

    _positionSub = locationService.positionStream.listen((position) {
      final current = (latitude: position.latitude, longitude: position.longitude);
      if (_lastPosition != null) {
        _trackedDistanceKm += GeohashUtil.distanceKm(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          current.latitude,
          current.longitude,
        );
      }
      _lastPosition = current;

      final uid = ref.read(authStateProvider).value;
      if (uid != null) {
        ref.read(geohashServiceProvider).updateDriverLocation(
              driverId: uid,
              lat: position.latitude,
              lng: position.longitude,
              heading: position.heading,
              speed: position.speed,
            );
      }
    });
  }

  Future<void> _updateStatus(RideStatus status) async {
    setState(() => _busy = true);
    try {
      await ref.read(rideRepositoryProvider).updateStatus(widget.rideId, status);
      if (status == RideStatus.ongoing) {
        _startTrackingTrip();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update status: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeTrip() async {
    setState(() => _busy = true);
    try {
      final durationMin = _tripStartedAt == null
          ? 0.0
          : DateTime.now().difference(_tripStartedAt!).inSeconds / 60.0;

      await ref.read(rideRepositoryProvider).completeRide(
            rideId: widget.rideId,
            actualDistanceKm: _trackedDistanceKm,
            actualDurationMin: durationMin,
          );

      _positionSub?.cancel();
      _positionSub = null;
      ref.read(locationServiceProvider).setActivityState(GpsActivityState.onlineWaiting);

      if (mounted) context.goNamed(AppRoutes.driverHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not complete ride: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text('This will cancel the trip and notify the passenger.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(rideRepositoryProvider).cancelRide(widget.rideId, byDriver: true);
      if (mounted) context.goNamed(AppRoutes.driverHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
      }
    }
  }

  Future<void> _openExternalNav(GeoPoint2 destination) async {
    final uri = Uri.parse(
      'google.navigation:q=${destination.lat},${destination.lng}&mode=d',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${destination.lat},${destination.lng}',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return Scaffold(
      body: rideAsync.when(
        data: (ride) {
          if (ride == null) return const Center(child: Text('This ride no longer exists.'));
          return _buildBody(context, ride);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RideModel ride) {
    final destination = ride.status == RideStatus.ongoing ? ride.dropoff : ride.pickup;

    return Stack(
      children: [
        const MapPlaceholder(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Spacer(),
                SosButton(rideId: ride.id, compact: true),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusLabel(ride.status),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      destination.address ?? '',
                      style: const TextStyle(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openExternalNav(destination),
                            icon: const Icon(Icons.navigation_outlined),
                            label: const Text('Navigate'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _busy ? null : () => _primaryAction(ride.status),
                            child: _busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(_primaryActionLabel(ride.status)),
                          ),
                        ),
                      ],
                    ),
                    if (ride.status == RideStatus.accepted) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _cancelTrip,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Cancel ride'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(RideStatus status) {
    switch (status) {
      case RideStatus.accepted:
        return 'Drive to pickup location';
      case RideStatus.arrived:
        return "You've arrived — waiting for passenger";
      case RideStatus.ongoing:
        return 'Trip in progress';
      default:
        return 'Trip';
    }
  }

  String _primaryActionLabel(RideStatus status) {
    switch (status) {
      case RideStatus.accepted:
        return "I've arrived";
      case RideStatus.arrived:
        return 'Start trip';
      case RideStatus.ongoing:
        return 'Complete trip';
      default:
        return 'Continue';
    }
  }

  Future<void> _primaryAction(RideStatus status) async {
    switch (status) {
      case RideStatus.accepted:
        await _updateStatus(RideStatus.arrived);
        break;
      case RideStatus.arrived:
        await _updateStatus(RideStatus.ongoing);
        break;
      case RideStatus.ongoing:
        await _completeTrip();
        break;
      default:
        break;
    }
  }
}
