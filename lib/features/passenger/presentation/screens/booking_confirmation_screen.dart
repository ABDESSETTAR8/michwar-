import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/ride_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';

/// Arguments passed from [RideOptionsScreen] to [BookingConfirmationScreen]:
/// the chosen pickup/dropoff, ride tier, and fare estimate.
class BookingConfirmationArgs {
  final GeoPoint2 pickup;
  final GeoPoint2 dropoff;
  final String rideTier;
  final RideEstimate estimate;

  const BookingConfirmationArgs({
    required this.pickup,
    required this.dropoff,
    required this.rideTier,
    required this.estimate,
  });
}

/// "Booking Confirmation" screen — final step of the Ride Request Flow.
/// Summarizes the trip and, on confirm, creates the `rides/{rideId}`
/// document via [RideRepository.requestRide] (status: `searching`), then
/// pushes the passenger to [ActiveRideScreen] to await driver matching.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  const BookingConfirmationScreen({super.key, required this.args});

  final BookingConfirmationArgs args;

  @override
  ConsumerState<BookingConfirmationScreen> createState() => _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends ConsumerState<BookingConfirmationScreen> {
  bool _requesting = false;

  Future<void> _requestRide() async {
    final auth = ref.read(authStateProvider).value;
    if (auth == null) return;

    setState(() => _requesting = true);

    try {
      final rideId = await ref.read(rideRepositoryProvider).requestRide(
            passengerId: auth,
            pickup: widget.args.pickup,
            dropoff: widget.args.dropoff,
            estimate: widget.args.estimate,
            rideTier: widget.args.rideTier,
          );

      if (!mounted) return;
      context.goNamed(AppRoutes.activeRide, pathParameters: {'rideId': rideId});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not request ride: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your ride')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LocationRow(
              icon: Icons.my_location_rounded,
              iconColor: AppColors.primary,
              label: 'Pickup',
              address: args.pickup.address ?? 'Current location',
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 11),
              child: SizedBox(
                height: 20,
                child: VerticalDivider(thickness: 2),
              ),
            ),
            _LocationRow(
              icon: Icons.flag_rounded,
              iconColor: AppColors.danger,
              label: 'Destination',
              address: args.dropoff.address ?? '',
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              color: AppColors.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _SummaryRow(label: 'Ride tier', value: args.rideTier.toUpperCase()),
                    _SummaryRow(label: 'Distance', value: Formatters.distanceKm(args.estimate.distanceKm)),
                    _SummaryRow(label: 'Estimated time', value: Formatters.durationMin(args.estimate.durationMin)),
                    const Divider(),
                    _SummaryRow(
                      label: 'Estimated fare',
                      value: Formatters.currency(args.estimate.fareEstimate),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Final fare is calculated from actual trip distance/time and may '
              'include a small platform surcharge (1-4 DA).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _requesting ? null : _requestRide,
                child: _requesting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Find my driver'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(address, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              fontSize: emphasize ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
