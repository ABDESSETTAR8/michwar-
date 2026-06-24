import { CONSTANTS } from "../config/constants";

/**
 * Authoritative fare/commission calculations (Section 6 — "Financial &
 * Performance Logic (Revised)"). This is the ONLY place that should ever
 * produce numbers that get billed to a passenger or paid out to a driver.
 */

function roundToNearest(value: number, nearest: number): number {
  return Math.round(value / nearest) * nearest;
}

/**
 * Computes the BASE FARE from actual trip distance/duration. This is the
 * pool that gets split between the driver and the company via the
 * commission rate — it does NOT include the platform surcharge.
 */
export function computeBaseFare(distanceKm: number, durationMin: number, rideTier: string): number {
  const multiplier = CONSTANTS.RIDE_TIER_MULTIPLIERS[rideTier] ?? 1.0;

  const raw =
    CONSTANTS.BASE_FARE_FLAG_DZD + distanceKm * CONSTANTS.FARE_PER_KM_DZD + durationMin * CONSTANTS.FARE_PER_MINUTE_DZD;

  const tiered = raw * multiplier;

  return tiered < CONSTANTS.MINIMUM_FARE_DZD ? CONSTANTS.MINIMUM_FARE_DZD : roundToNearest(tiered, 5);
}

/**
 * Deterministic-but-varying platform surcharge in the range
 * [SURCHARGE_MIN_DZD, SURCHARGE_MAX_DZD] (Section 6.B — 100% company
 * revenue, never shared with the driver and never part of the commission
 * base). Derived from the rideId so repeated calls for the same ride are
 * stable.
 */
export function computeSurcharge(rideId: string): number {
  let hash = 0;
  for (let i = 0; i < rideId.length; i++) {
    hash = (hash * 31 + rideId.charCodeAt(i)) >>> 0;
  }
  const range = CONSTANTS.SURCHARGE_MAX_DZD - CONSTANTS.SURCHARGE_MIN_DZD + 1;
  return CONSTANTS.SURCHARGE_MIN_DZD + (hash % range);
}

export interface FareBreakdown {
  baseFare: number;
  surchargeDzd: number;
  totalFare: number;
  commissionRate: number;
  commissionAmount: number;
  driverPayout: number;
  companyRevenue: number;
}

/**
 * Splits the base fare between driver and company according to the
 * driver's current commission tier, and adds the (company-only) surcharge.
 */
export function computeFareBreakdown(
  baseFare: number,
  surchargeDzd: number,
  commissionRate: number
): FareBreakdown {
  const commissionAmount = roundToNearest(baseFare * commissionRate, 1);
  const driverPayout = baseFare - commissionAmount;
  const companyRevenue = commissionAmount + surchargeDzd;
  const totalFare = baseFare + surchargeDzd;

  return {
    baseFare,
    surchargeDzd,
    totalFare,
    commissionRate,
    commissionAmount,
    driverPayout,
    companyRevenue,
  };
}

/** "MICHWAR Points" earned by the passenger for a completed ride. */
export function computePointsAwarded(totalFare: number): number {
  return Math.floor(totalFare / 100) * CONSTANTS.POINTS_PER_HUNDRED_DZD;
}

/** Resolves the passenger's loyalty tier from their accumulated points. */
export function resolveLoyaltyTier(points: number): "standard" | "eco" | "premium" {
  if (points >= CONSTANTS.POINTS_FOR_PREMIUM_TIER) return "premium";
  if (points >= CONSTANTS.POINTS_FOR_ECO_DISCOUNT) return "eco";
  return "standard";
}

export interface CommissionTier {
  tier: "tier1" | "tier2";
  commissionRate: number;
  driverShareRate: number;
}

/**
 * Determines a driver's commission tier given their lifetime stats
 * (Section 6.A): Elite (tier2) requires >= 100 completed rides AND an
 * average rating >= 4.0. Once promoted, a driver stays Elite even if their
 * average later dips slightly — this function is also used to *check*
 * eligibility for first-time promotion, so callers should only downgrade
 * deliberately (not implemented — promotions are one-way in this build).
 */
export function resolveCommissionTier(ridesCompleted: number, ratingAverage: number, currentTier: string): CommissionTier {
  const alreadyElite = currentTier === "tier2";
  const qualifiesForElite =
    ridesCompleted >= CONSTANTS.ELITE_MIN_COMPLETED_RIDES && ratingAverage >= CONSTANTS.ELITE_MIN_AVERAGE_RATING;

  if (alreadyElite || qualifiesForElite) {
    return {
      tier: "tier2",
      commissionRate: CONSTANTS.TIER2_COMMISSION_RATE,
      driverShareRate: CONSTANTS.TIER2_DRIVER_RATE,
    };
  }

  return {
    tier: "tier1",
    commissionRate: CONSTANTS.TIER1_COMMISSION_RATE,
    driverShareRate: CONSTANTS.TIER1_DRIVER_RATE,
  };
}
