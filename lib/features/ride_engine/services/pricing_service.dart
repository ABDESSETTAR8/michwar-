import '../../../core/constants/app_constants.dart';

/// Client-side fare ESTIMATE only — shown during the booking flow before a
/// ride is requested.
///
/// ⚠️ This is NOT the billable amount. Per the spec's "Server-Side
/// Validation" requirement, the authoritative fare/commission/surcharge
/// split is computed exclusively by the `completeRide` Cloud Function
/// (see `functions/src/triggers/onRideCompleted.ts`) using the trip's
/// actual tracked distance/duration. This estimate exists purely for UX.
class PricingService {
  const PricingService();

  /// Returns an estimated fare in DZD for a trip of [distanceKm] /
  /// [durationMin] at the given [rideTier] ("standard" | "eco" | "premium").
  double estimateFare({
    required double distanceKm,
    required double durationMin,
    String rideTier = 'standard',
  }) {
    final multiplier = AppConstants.rideTierMultipliers[rideTier] ?? 1.0;

    final raw = AppConstants.baseFareFlagDzd +
        (distanceKm * AppConstants.farePerKmDzd) +
        (durationMin * AppConstants.farePerMinuteDzd);

    final tiered = raw * multiplier;

    return tiered < AppConstants.minimumFareDzd
        ? AppConstants.minimumFareDzd
        : _roundToNearest(tiered, 5);
  }

  /// Estimated platform surcharge shown to the user (the server computes
  /// the authoritative value, but it always falls within this range).
  ({int min, int max}) surchargeRangeDzd() => (
        min: AppConstants.surchargeMinDzd,
        max: AppConstants.surchargeMaxDzd,
      );

  /// "MICHWAR Points" the passenger will earn if this ride is completed.
  int estimatePoints(double fareEstimate) {
    return ((fareEstimate / 100).floor() * AppConstants.pointsPerHundredDzd);
  }

  double _roundToNearest(double value, int nearest) {
    return (value / nearest).round() * nearest.toDouble();
  }
}
