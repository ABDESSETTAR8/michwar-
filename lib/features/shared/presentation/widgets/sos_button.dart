import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';

/// Prominent emergency button (Safety & Reliability: "In-app SOS").
/// Tapping it asks for confirmation, then sends the current GPS
/// coordinates + ride context to the admin team via the `sosAlert`
/// Cloud Function, which is responsible for instant alerting.
class SosButton extends ConsumerWidget {
  const SosButton({super.key, this.rideId, this.compact = false});

  /// The active ride, if any. May be null when triggered from a Home
  /// screen (e.g. general emergency, not tied to a trip).
  final String? rideId;
  final bool compact;

  Future<void> _trigger(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS alert?'),
        content: const Text(
          'This will immediately notify the MICHWAR safety team with your '
          'live location. Only use this in a real emergency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.sos),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final locationService = ref.read(locationServiceProvider);
      final position = await locationService.getCurrentPosition();

      await ref.read(rideRepositoryProvider).triggerSos(
            rideId: rideId ?? '',
            lat: position.latitude,
            lng: position.longitude,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS alert sent. Help is on the way.'),
            backgroundColor: AppColors.sos,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send SOS: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) {
      return Material(
        color: AppColors.sos,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _trigger(context, ref),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.sos_rounded, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sos,
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: () => _trigger(context, ref),
        icon: const Icon(Icons.sos_rounded),
        label: const Text('SOS — Emergency'),
      ),
    );
  }
}
