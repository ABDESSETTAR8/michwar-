/**
 * Server-side mirror of `lib/core/constants/app_constants.dart`.
 *
 * These values are AUTHORITATIVE — the client copies are for display
 * (fare estimates) only. Any change here MUST be mirrored on the client
 * to keep estimates close to the final billed amount, but the numbers
 * actually charged/paid always come from this file.
 */

export const CONSTANTS = {
  // -----------------------------------------------------------------
  // Commission tiers (Section 6.A — Dynamic Commission Model)
  // -----------------------------------------------------------------
  TIER1_COMMISSION_RATE: 0.15,
  TIER1_DRIVER_RATE: 0.85,
  TIER2_COMMISSION_RATE: 0.07,
  TIER2_DRIVER_RATE: 0.93,

  ELITE_MIN_COMPLETED_RIDES: 100,
  ELITE_MIN_AVERAGE_RATING: 4.0,

  // -----------------------------------------------------------------
  // Platform surcharge (Section 6.B) — 100% company revenue
  // -----------------------------------------------------------------
  SURCHARGE_MIN_DZD: 1,
  SURCHARGE_MAX_DZD: 4,

  // -----------------------------------------------------------------
  // Driver wallet (Section 6.C)
  // -----------------------------------------------------------------
  WALLET_LOW_BALANCE_THRESHOLD_DZD: 200.0,
  WALLET_WELCOME_CREDIT_DZD: 500.0,

  // -----------------------------------------------------------------
  // Loyalty / "MICHWAR Points"
  // -----------------------------------------------------------------
  POINTS_PER_HUNDRED_DZD: 2,
  POINTS_FOR_ECO_DISCOUNT: 50,
  POINTS_FOR_PREMIUM_TIER: 200,

  // -----------------------------------------------------------------
  // Geohash / proximity matching
  // -----------------------------------------------------------------
  GEOHASH_PRECISION: 7,
  DEFAULT_DRIVER_SEARCH_RADIUS_KM: 3.0,
  MAX_DRIVER_SEARCH_RADIUS_KM: 10.0,

  // -----------------------------------------------------------------
  // Base fare formula (authoritative)
  // -----------------------------------------------------------------
  BASE_FARE_FLAG_DZD: 100.0,
  FARE_PER_KM_DZD: 35.0,
  FARE_PER_MINUTE_DZD: 5.0,
  MINIMUM_FARE_DZD: 150.0,

  RIDE_TIER_MULTIPLIERS: {
    standard: 1.0,
    eco: 0.92,
    premium: 1.35,
  } as Record<string, number>,

  // -----------------------------------------------------------------
  // Live trip sharing
  // -----------------------------------------------------------------
  LIVE_SHARE_LINK_VALIDITY_MS: 6 * 60 * 60 * 1000, // 6 hours

  // -----------------------------------------------------------------
  // Driver matching
  // -----------------------------------------------------------------
  /** How many candidate driver IDs to attach to a new ride request. */
  MAX_CANDIDATE_DRIVERS: 10,
  /** Incoming-request countdown shown on the driver app, in seconds. */
  INCOMING_REQUEST_TIMEOUT_SECONDS: 15,
};
