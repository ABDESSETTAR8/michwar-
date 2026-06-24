import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/ride_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';

/// "MICHWAR Points" loyalty dashboard (Section 5 — Gamification). Shows the
/// passenger's current points balance, tier progress toward the Eco and
/// Premium unlocks, and a short ride history.
class LoyaltyDashboardScreen extends ConsumerWidget {
  const LoyaltyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final loyalty = profile?.loyalty;
    final points = loyalty?.points ?? 0;
    final tier = loyalty?.tier ?? 'standard';

    final uid = ref.watch(authStateProvider).value;
    final historyAsync = uid == null
        ? const AsyncValue<List<RideModel>>.data([])
        : ref.watch(_rideHistoryProvider(uid));

    final nextThreshold = points < AppConstants.pointsForEcoDiscount
        ? AppConstants.pointsForEcoDiscount
        : points < AppConstants.pointsForPremiumTier
            ? AppConstants.pointsForPremiumTier
            : null;

    final progress = nextThreshold == null ? 1.0 : (points / nextThreshold).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('MICHWAR Points')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your balance', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  '$points pts',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text(tier.toUpperCase()),
                  backgroundColor: _tierColor(tier).withOpacity(0.2),
                  labelStyle: TextStyle(color: _tierColor(tier), fontWeight: FontWeight.w700),
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (nextThreshold != null) ...[
            Text(
              nextThreshold == AppConstants.pointsForEcoDiscount
                  ? 'Earn ${nextThreshold - points} more points to unlock the Eco discount (5% off)'
                  : 'Earn ${nextThreshold - points} more points to unlock Premium tier access',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.background,
                color: AppColors.secondary,
              ),
            ),
          ] else
            const Text(
              'You have unlocked all loyalty tiers!',
              style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 8),
          const Text(
            'Earn 2 points for every 100 DA spent on rides.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          const Text('Recent rides', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          historyAsync.when(
            data: (rides) {
              if (rides.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No completed rides yet.', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                );
              }
              return Column(
                children: rides.map((ride) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.background,
                      child: Icon(Icons.directions_car_filled_outlined, color: AppColors.primary),
                    ),
                    title: Text(ride.dropoff.address ?? 'Trip', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(ride.completedAt != null ? Formatters.dateTime(ride.completedAt!) : ''),
                    trailing: Text(
                      Formatters.currency(ride.fare?.totalFare ?? ride.estimate.fareEstimate),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'eco':
        return AppColors.tierEco;
      case 'premium':
        return AppColors.tierPremium;
      default:
        return AppColors.tierStandard;
    }
  }
}

final _rideHistoryProvider = StreamProvider.family<List<RideModel>, String>((ref, uid) {
  return ref.watch(rideRepositoryProvider).watchRideHistory(uid, isDriver: false);
});
