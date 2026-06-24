/// <reference path="../pb_data/types.d.ts" />

// Authoritative business constants — mirrors lib/core/constants/app_constants.dart
// (the Dart copy is for client-side ESTIMATES only; these numbers are what
// actually gets billed/paid). PocketBase loads every pb_hooks/*.pb.js file into
// one shared JS runtime, so this top-level `var` is available to all other hook
// files (loaded in filename order — keep the "00_" prefix so this loads first).
var MICHWAR = {
  // Commission tiers
  TIER1_COMMISSION_RATE: 0.15,
  TIER1_DRIVER_RATE: 0.85,
  TIER2_COMMISSION_RATE: 0.07,
  TIER2_DRIVER_RATE: 0.93,

  ELITE_MIN_COMPLETED_RIDES: 100,
  ELITE_MIN_AVERAGE_RATING: 4.0,

  // Platform surcharge (100% company revenue)
  SURCHARGE_MIN_DZD: 1,
  SURCHARGE_MAX_DZD: 4,

  // Driver wallet
  WALLET_LOW_BALANCE_THRESHOLD_DZD: 200.0,
  WALLET_WELCOME_CREDIT_DZD: 500.0,

  // Loyalty / "MICHWAR Points"
  POINTS_PER_HUNDRED_DZD: 2,
  POINTS_FOR_ECO_DISCOUNT: 50,
  POINTS_FOR_PREMIUM_TIER: 200,

  // Geohash / proximity matching
  GEOHASH_PRECISION: 7,
  DEFAULT_DRIVER_SEARCH_RADIUS_KM: 3.0,
  MAX_DRIVER_SEARCH_RADIUS_KM: 10.0,

  // Base fare formula (authoritative)
  BASE_FARE_FLAG_DZD: 100.0,
  FARE_PER_KM_DZD: 35.0,
  FARE_PER_MINUTE_DZD: 5.0,
  MINIMUM_FARE_DZD: 150.0,

  RIDE_TIER_MULTIPLIERS: { standard: 1.0, eco: 0.92, premium: 1.35 },

  // Live trip sharing
  LIVE_SHARE_LINK_VALIDITY_MS: 6 * 60 * 60 * 1000, // 6 hours
  // Public base URL for the (separately hosted) live-tracking page.
  LIVE_SHARE_BASE_URL: "https://example.com/track",

  // Driver matching
  MAX_CANDIDATE_DRIVERS: 10,
  INCOMING_REQUEST_TIMEOUT_SECONDS: 15,

  // Heatmap cell precision (~1.2km cells)
  HEATMAP_GEOHASH_PRECISION: 6,

  // Compliance — required driver verification documents (Section 4),
  // mirrors lib/core/constants/app_constants.dart requiredDriverDocuments.
  REQUIRED_DRIVER_DOCUMENTS: ["national_id", "driver_license", "carte_grise", "insurance", "control_technique"],
};
