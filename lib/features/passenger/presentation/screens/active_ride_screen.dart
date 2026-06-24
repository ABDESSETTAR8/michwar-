import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/map_placeholder.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/models/ride_model.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import '../../../shared/presentation/widgets/sos_button.dart';

/// "Active Ride" screen — covers the passenger side of the trip from the
/// moment a ride is requested (`searching`) through `accepted`, `arrived`,
/// `ongoing`, and finally `completed` (at which point the passenger is
/// routed to [PostRideScreen]).
///
/// Also surfaces Safety & Reliability features: in-app SOS and "Live Trip
/// Sharing" (a temporary link a friend/family member can open to follow the
/// trip in real time).
class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  bool _generatingLink = false;
  bool _navigatedToPostRide = false;

  @override
  void initState() {
    super.initState();
    ref.read(offlineSyncServiceProvider).start(widget.rideId);
  }

  Future<void> _cancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel ride?'),
        content: const Text('Are you sure you want to cancel this ride request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, cancel')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(rideRepositoryProvider).cancelRide(widget.rideId, byDriver: false);
      if (mounted) context.goNamed(AppRoutes.passengerHome);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
      }
    }
  }

  Future<void> _shareLiveTrip() async {
    setState(() => _generatingLink = true);
    try {
      final url = await ref.read(rideRepositoryProvider).generateLiveShareLink(widget.rideId);
      await Share.share(
        'Follow my MICHWAR trip live: $url',
        subject: 'My live MICHWAR trip',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate link: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return Scaffold(
      body: rideAsync.when(
        data: (ride) {
          if (ride == null) {
            return const Center(child: Text('This ride no longer exists.'));
          }

          if (ride.status == RideStatus.completed && !_navigatedToPostRide) {
            _navigatedToPostRide = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                context.goNamed(AppRoutes.postRide, pathParameters: {'rideId': ride.id});
              }
            });
          }

          return _buildBody(context, ride);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RideModel ride) {
    final driverAsync = ride.driverId != null
        ? ref.watch(driverByIdProvider(ride.driverId!))
        : const AsyncValue<dynamic>.data(null);

    // Location data kept for future map integration.
    final _ = driverAsync.value?.location;

    return Stack(
      children: [
        const MapPlaceholder(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.maybePop(context),
                ),
                const Spacer(),
                _RoundIconButton(
                  icon: Icons.ios_share_rounded,
                  loading: _generatingLink,
                  onTap: _shareLiveTrip,
                ),
                const SizedBox(width: 10),
                SosButton(rideId: ride.id, compact: true),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _StatusCard(
                ride: ride,
                driver: driverAsync.value,
                onCancel: _cancelRide,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.loading = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ride, required this.driver, required this.onCancel});

  final RideModel ride;
  final dynamic driver;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusContent(context),
          ],
        ),
      ),
    );
  }

  Widget _statusContent(BuildContext context) {
    switch (ride.status) {
      case RideStatus.searching:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Text('Looking for a nearby driver...', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Heading to ${ride.dropoff.address ?? 'your destination'}',
              style: const TextStyle(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Cancel ride'),
            ),
          ],
        );

      case RideStatus.noDriversFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('No drivers available right now',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Please try again in a few minutes.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Back'),
            ),
          ],
        );

      case RideStatus.accepted:
      case RideStatus.arrived:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ride.status == RideStatus.arrived
                  ? 'Your driver has arrived'
                  : 'Your driver is on the way',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            _DriverInfoRow(driver: driver),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Cancel ride'),
            ),
          ],
        );

      case RideStatus.ongoing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Trip in progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Heading to ${ride.dropoff.address ?? 'destination'}',
              style: const TextStyle(color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _DriverInfoRow(driver: driver),
          ],
        );

      case RideStatus.completed:
        return const Text('Trip completed — finalizing your receipt...');

      case RideStatus.cancelledByDriver:
      case RideStatus.cancelledByPassenger:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('This ride was cancelled', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Back to home'),
            ),
          ],
        );
    }
  }
}

class _DriverInfoRow extends StatelessWidget {
  const _DriverInfoRow({required this.driver});

  final dynamic driver;

  @override
  Widget build(BuildContext context) {
    if (driver == null) {
      return const Text('Loading driver details...', style: TextStyle(color: AppColors.textSecondary));
    }

    final vehicle = driver.vehicle;

    return Row(
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.background,
          child: Icon(Icons.person, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${vehicle.make} ${vehicle.model} · ${vehicle.color}',
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                vehicle.plate,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Icon(Icons.star_rounded, color: AppColors.secondary, size: 18),
            const SizedBox(width: 2),
            Text(
              driver.ratingAverage.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
