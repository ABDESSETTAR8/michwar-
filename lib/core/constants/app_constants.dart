/// Centralized, immutable configuration for MICHWAR.
///
/// IMPORTANT: The financial constants below mirror the "Financial &
/// Performance Logic (Revised)" section of the MICHWAR specification.
/// They are duplicated (and authoritative) in `functions/src/config/constants.ts`
/// for server-side enforcement. The client copies are used ONLY for
/// showing fare *estimates* to the user — the Cloud Functions always
/// recompute and persist the final, billable numbers.
library;

class AppConstants {
  AppConstants._();

  // ---------------------------------------------------------------------
  // App metadata
  // ---------------------------------------------------------------------
  static const String appName = 'MICHWAR';
  static const String currencyCode = 'DZD';
  static const String currencySymbol = 'DA';
  static const String defaultCountryCode = '+213'; // Algeria

  // ---------------------------------------------------------------------
  // Commission tiers (Section 6.A — Dynamic Commission Model)
  // ---------------------------------------------------------------------
  /// Tier 1 (Base): company keeps 15% of the BASE FARE, driver keeps 85%.
  static const double tier1CommissionRate = 0.15;
  static const double tier1DriverRate = 0.85;

  /// Tier 2 (Elite): company keeps 7% of the BASE FARE, driver keeps 93%.
  static const double tier2CommissionRate = 0.07;
  static const double tier2DriverRate = 0.93;

  /// Threshold criteria for automatic promotion to Elite.
  static const int eliteMinCompletedRides = 100;
  static const double eliteMinAverageRating = 4.0;

  // ---------------------------------------------------------------------
  // Platform surcharge (Section 6.B) — 100% company revenue, NOT shared
  // with the driver and NOT part of the commission calculation base.
  // ---------------------------------------------------------------------
  static const int surchargeMinDzd = 1;
  static const int surchargeMaxDzd = 4;

  // ---------------------------------------------------------------------
  // Driver wallet (Section 6.C)
  // ---------------------------------------------------------------------
  /// Drivers whose wallet balance falls at/below this value cannot accept
  /// new ride requests until they top up.
  static const double walletLowBalanceThresholdDzd = 200.0;

  /// Default starting balance granted to a newly-verified driver so they
  /// can complete their first few rides before their first top-up.
  static const double walletWelcomeCreditDzd = 500.0;

  // ---------------------------------------------------------------------
  // Loyalty / Gamification — "MICHWAR Points"
  // ---------------------------------------------------------------------
  /// Points earned per 100 DZD of fare paid (rounded down).
  static const int pointsPerHundredDzd = 2;

  /// Points required to unlock the "Eco" discount tier (5% off next ride).
  static const int pointsForEcoDiscount = 50;

  /// Points required to unlock "Premium" ride access.
  static const int pointsForPremiumTier = 200;

  // ---------------------------------------------------------------------
  // Geohash / proximity matching
  // ---------------------------------------------------------------------
  /// Geohash precision (character length) stored on each driver document.
  /// 7 characters ≈ 153m x 153m cell — a good balance between index size
  /// and query precision for urban ride-hailing.
  static const int geohashPrecision = 7;

  /// Default search radius (in kilometers) when looking for nearby drivers.
  static const double defaultDriverSearchRadiusKm = 3.0;

  /// Maximum radius the matching engine will expand to before giving up.
  static const double maxDriverSearchRadiusKm = 10.0;

  // ---------------------------------------------------------------------
  // Adaptive GPS tracking intervals (Section: Smart Driver Tools)
  // ---------------------------------------------------------------------
  static const Duration gpsIntervalIdle = Duration(seconds: 30);
  static const Duration gpsIntervalOnlineWaiting = Duration(seconds: 8);
  static const Duration gpsIntervalActiveTrip = Duration(seconds: 3);

  // ---------------------------------------------------------------------
  // Base fare formula (used for client-side estimates only)
  // ---------------------------------------------------------------------
  static const double baseFareFlagDzd = 100.0; // starting fare
  static const double farePerKmDzd = 35.0;
  static const double farePerMinuteDzd = 5.0;
  static const double minimumFareDzd = 150.0;

  /// Multipliers applied on top of the standard fare for premium tiers.
  static const Map<String, double> rideTierMultipliers = {
    'standard': 1.0,
    'eco': 0.92,
    'premium': 1.35,
  };

  // ---------------------------------------------------------------------
  // Live trip sharing
  // ---------------------------------------------------------------------
  static const Duration liveShareLinkValidity = Duration(hours: 6);

  // ---------------------------------------------------------------------
  // Compliance — required driver documents (Section 4)
  // ---------------------------------------------------------------------
  static const List<String> requiredDriverDocuments = [
    'national_id',
    'driver_license',
    'carte_grise',
    'insurance',
    'control_technique',
  ];

  static const Map<String, String> driverDocumentLabels = {
    'national_id': 'National Identity Card',
    'driver_license': "Driver's License",
    'carte_grise': 'Vehicle Registration (Carte Grise)',
    'insurance': 'Valid Insurance',
    'control_technique': 'Control Technique Certificate',
  };
}
