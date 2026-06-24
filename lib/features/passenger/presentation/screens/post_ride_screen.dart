import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/ride_model.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';

/// "Post-Ride" screen — shows the final fare receipt (computed server-side
/// by `completeRide`) and lets the passenger rate the driver. Submitting a
/// rating triggers the `submitRating` Cloud Function, which re-checks the
/// driver's Elite-tier eligibility.
class PostRideScreen extends ConsumerStatefulWidget {
  const PostRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<PostRideScreen> createState() => _PostRideScreenState();
}

class _PostRideScreenState extends ConsumerState<PostRideScreen> {
  double _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _submitting = true);
    try {
      await ref.read(rideRepositoryProvider).submitRating(
            rideId: widget.rideId,
            stars: _rating.round(),
            comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
          );
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit rating: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideStreamProvider(widget.rideId));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip receipt')),
      body: rideAsync.when(
        data: (ride) {
          if (ride == null) return const Center(child: Text('Ride not found.'));
          return _buildBody(context, ride);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, RideModel ride) {
    final fare = ride.fare;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
                  const SizedBox(height: 8),
                  const Text('Trip completed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),
                  if (fare != null) ...[
                    _ReceiptRow(label: 'Base fare', value: Formatters.currency(fare.baseFare)),
                    _ReceiptRow(label: 'Platform surcharge', value: Formatters.currency(fare.surchargeDzd)),
                    const Divider(),
                    _ReceiptRow(label: 'Total fare', value: Formatters.currency(fare.totalFare), emphasize: true),
                  ] else
                    _ReceiptRow(
                      label: 'Estimated fare',
                      value: Formatters.currency(ride.estimate.fareEstimate),
                      emphasize: true,
                    ),
                  if (ride.pointsAwarded > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '+${ride.pointsAwarded} MICHWAR Points earned',
                      style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (ride.rating != null || _submitted)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Thanks for your feedback!', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            )
          else ...[
            const Text('Rate your driver', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            Center(
              child: RatingBar.builder(
                initialRating: _rating,
                minRating: 1,
                allowHalfRating: false,
                itemCount: 5,
                itemSize: 36,
                itemBuilder: (context, _) => const Icon(Icons.star_rounded, color: AppColors.secondary),
                onRatingUpdate: (value) => setState(() => _rating = value),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _submitting ? null : _submitRating,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit rating'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.goNamed(AppRoutes.passengerHome),
              child: const Text('Back to home'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.emphasize = false});

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
