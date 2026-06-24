import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/map_placeholder.dart';

import '../../../../core/models/ride_model.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import 'booking_confirmation_screen.dart';

/// Arguments passed from [DestinationSearchScreen] to [RideOptionsScreen]:
/// the planned route between pickup and dropoff.
class RideOptionsArgs {
  final GeoPoint2 pickup;
  final GeoPoint2 dropoff;
  final double distanceKm;
  final double durationMin;
  const RideOptionsArgs({
    required this.pickup,
    required this.dropoff,
    required this.distanceKm,
    required this.durationMin,
  });
}

class _TierOption {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  const _TierOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}

const _tierOptions = [
  _TierOption(
    id: 'eco',
    label: 'Eco',
    description: 'Budget-friendly, shared-style pricing',
    icon: Icons.eco_outlined,
  ),
  _TierOption(
    id: 'standard',
    label: 'Standard',
    description: 'Everyday rides, comfortable sedans',
    icon: Icons.directions_car_filled_outlined,
  ),
  _TierOption(
    id: 'premium',
    label: 'Premium',
    description: 'Top-rated drivers, premium vehicles',
    icon: Icons.workspace_premium_outlined,
  ),
];

/// "Ride Options" screen — second step of the Ride Request Flow. Shows the
/// planned route on a small map preview and lets the passenger choose a
/// ride tier (Eco / Standard / Premium), each with its own fare estimate.
class RideOptionsScreen extends ConsumerStatefulWidget {
  const RideOptionsScreen({super.key, required this.args});

  final RideOptionsArgs args;

  @override
  ConsumerState<RideOptionsScreen> createState() => _RideOptionsScreenState();
}

class _RideOptionsScreenState extends ConsumerState<RideOptionsScreen> {
  String _selectedTier = 'standard';

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final pricing = ref.read(pricingServiceProvider);


    return Scaffold(
      appBar: AppBar(title: const Text('Choose a ride')),
      body: Column(
        children: [
          const SizedBox(height: 200, child: MapPlaceholder()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.route_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(Formatters.distanceKm(args.distanceKm)),
                const SizedBox(width: 16),
                const Icon(Icons.schedule_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(Formatters.durationMin(args.durationMin)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tierOptions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final tier = _tierOptions[index];
                final fare = pricing.estimateFare(
                  distanceKm: args.distanceKm,
                  durationMin: args.durationMin,
                  rideTier: tier.id,
                );
                final points = pricing.estimatePoints(fare);
                final selected = _selectedTier == tier.id;

                return Material(
                  color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selectedTier = tier.id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.background,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.background,
                            child: Icon(tier.icon, color: AppColors.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tier.label,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  tier.description,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '+$points MICHWAR Points',
                                  style: const TextStyle(fontSize: 11, color: AppColors.secondary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Formatters.currency(fare),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () {
                    final fare = pricing.estimateFare(
                      distanceKm: args.distanceKm,
                      durationMin: args.durationMin,
                      rideTier: _selectedTier,
                    );

                    context.pushNamed(
                      AppRoutes.bookingConfirmation,
                      extra: BookingConfirmationArgs(
                        pickup: args.pickup,
                        dropoff: args.dropoff,
                        rideTier: _selectedTier,
                        estimate: RideEstimate(
                          distanceKm: args.distanceKm,
                          durationMin: args.durationMin,
                          fareEstimate: fare,
                        ),
                      ),
                    );
                  },
                  child: const Text('Confirm ride'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
