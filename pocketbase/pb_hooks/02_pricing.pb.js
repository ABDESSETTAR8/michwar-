/// <reference path="../pb_data/types.d.ts" />

// Port of functions/src/utils/pricing.ts — the ONLY logic that should ever
// produce numbers billed to a passenger or paid out to a driver.

function mwRoundToNearest(value, nearest) {
  return Math.round(value / nearest) * nearest;
}

/** Computes the BASE FARE from actual trip distance/duration. */
function mwComputeBaseFare(distanceKm, durationMin, rideTier) {
  var multiplier = MICHWAR.RIDE_TIER_MULTIPLIERS[rideTier];
  if (multiplier == null) multiplier = 1.0;

  var raw =
    MICHWAR.BASE_FARE_FLAG_DZD +
    distanceKm * MICHWAR.FARE_PER_KM_DZD +
    durationMin * MICHWAR.FARE_PER_MINUTE_DZD;

  var tiered = raw * multiplier;

  return tiered < MICHWAR.MINIMUM_FARE_DZD ? MICHWAR.MINIMUM_FARE_DZD : mwRoundToNearest(tiered, 5);
}

/**
 * Deterministic-but-varying platform surcharge in
 * [SURCHARGE_MIN_DZD, SURCHARGE_MAX_DZD], derived from the rideId so repeated
 * calls for the same ride are stable.
 */
function mwComputeSurcharge(rideId) {
  var hash = 0;
  for (var i = 0; i < rideId.length; i++) {
    hash = (hash * 31 + rideId.charCodeAt(i)) >>> 0;
  }
  var range = MICHWAR.SURCHARGE_MAX_DZD - MICHWAR.SURCHARGE_MIN_DZD + 1;
  return MICHWAR.SURCHARGE_MIN_DZD + (hash % range);
}

/** Splits the base fare between driver and company, adds the surcharge. */
function mwComputeFareBreakdown(baseFare, surchargeDzd, commissionRate) {
  var commissionAmount = mwRoundToNearest(baseFare * commissionRate, 1);
  var driverPayout = baseFare - commissionAmount;
  var companyRevenue = commissionAmount + surchargeDzd;
  var totalFare = baseFare + surchargeDzd;

  return {
    baseFare: baseFare,
    surchargeDzd: surchargeDzd,
    totalFare: totalFare,
    commissionRate: commissionRate,
    commissionAmount: commissionAmount,
    driverPayout: driverPayout,
    companyRevenue: companyRevenue,
  };
}

/** "MICHWAR Points" earned by the passenger for a completed ride. */
function mwComputePointsAwarded(totalFare) {
  return Math.floor(totalFare / 100) * MICHWAR.POINTS_PER_HUNDRED_DZD;
}

/** Resolves the passenger's loyalty tier from their accumulated points. */
function mwResolveLoyaltyTier(points) {
  if (points >= MICHWAR.POINTS_FOR_PREMIUM_TIER) return "premium";
  if (points >= MICHWAR.POINTS_FOR_ECO_DISCOUNT) return "eco";
  return "standard";
}

/**
 * Determines a driver's commission tier given lifetime stats. Elite (tier2)
 * requires >= ELITE_MIN_COMPLETED_RIDES rides AND >= ELITE_MIN_AVERAGE_RATING
 * average rating. Promotions are one-way (a driver already on tier2 stays
 * there even if their average later dips).
 */
function mwResolveCommissionTier(ridesCompleted, ratingAverage, currentTier) {
  var alreadyElite = currentTier === "tier2";
  var qualifiesForElite =
    ridesCompleted >= MICHWAR.ELITE_MIN_COMPLETED_RIDES && ratingAverage >= MICHWAR.ELITE_MIN_AVERAGE_RATING;

  if (alreadyElite || qualifiesForElite) {
    return { tier: "tier2", commissionRate: MICHWAR.TIER2_COMMISSION_RATE, driverShareRate: MICHWAR.TIER2_DRIVER_RATE };
  }

  return { tier: "tier1", commissionRate: MICHWAR.TIER1_COMMISSION_RATE, driverShareRate: MICHWAR.TIER1_DRIVER_RATE };
}
