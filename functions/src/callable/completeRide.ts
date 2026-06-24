import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CONSTANTS } from "../config/constants";
import { computeBaseFare, computeFareBreakdown, computePointsAwarded, computeSurcharge, resolveCommissionTier, resolveLoyaltyTier } from "../utils/pricing";

const db = () => admin.firestore();

/**
 * THE financial trigger (Section 6 / "Cloud Function Logic").
 *
 * Given the trip's actual tracked distance/duration:
 *  1. Computes the base fare and the 1-4 DZD platform surcharge.
 *  2. Applies the driver's current commission tier to the base fare.
 *  3. Deducts (commission + surcharge) from the driver's pre-paid wallet.
 *  4. Writes a `wallets/{driverId}/transactions/{transactionId}` ledger entry.
 *  5. Awards MICHWAR Points to the passenger and updates their loyalty tier.
 *  6. Re-checks Elite tier promotion (>=100 rides & >=4.0 rating).
 *  7. Marks the ride `completed` with the final `fare` breakdown.
 */
export const completeRide = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId, actualDistanceKm, actualDurationMin } = request.data as {
    rideId?: string;
    actualDistanceKm?: number;
    actualDurationMin?: number;
  };

  if (!rideId || actualDistanceKm == null || actualDurationMin == null) {
    throw new HttpsError("invalid-argument", "rideId, actualDistanceKm and actualDurationMin are required.");
  }
  if (actualDistanceKm < 0 || actualDurationMin < 0) {
    throw new HttpsError("invalid-argument", "Distance and duration must be non-negative.");
  }

  const rideRef = db().collection("rides").doc(rideId);
  const transactionId = db().collection("_ids").doc().id;

  const result = await db().runTransaction(async (tx) => {
    const rideSnap = await tx.get(rideRef);
    if (!rideSnap.exists) {
      throw new HttpsError("not-found", "Ride not found.");
    }
    const ride = rideSnap.data()!;

    if (ride.status !== "ongoing") {
      throw new HttpsError("failed-precondition", `Ride must be 'ongoing' to complete (currently '${ride.status}').`);
    }
    if (ride.driverId !== uid) {
      throw new HttpsError("permission-denied", "Only the assigned driver can complete this ride.");
    }

    const driverRef = db().collection("drivers").doc(uid);
    const walletRef = db().collection("wallets").doc(uid);
    const passengerRef = db().collection("users").doc(ride.passengerId);

    const [driverSnap, walletSnap, passengerSnap] = await Promise.all([
      tx.get(driverRef),
      tx.get(walletRef),
      tx.get(passengerRef),
    ]);

    if (!driverSnap.exists) {
      throw new HttpsError("not-found", "Driver profile not found.");
    }
    const driver = driverSnap.data()!;

    // --- 1. Fare calculation -------------------------------------------------
    const baseFare = computeBaseFare(actualDistanceKm, actualDurationMin, ride.rideTier ?? "standard");
    const surchargeDzd = computeSurcharge(rideId);
    const commissionRate = (driver.commissionRate as number) ?? CONSTANTS.TIER1_COMMISSION_RATE;
    const breakdown = computeFareBreakdown(baseFare, surchargeDzd, commissionRate);

    // --- 2. Wallet deduction --------------------------------------------------
    const currentBalance = (walletSnap.exists ? (walletSnap.data()!.balance as number) : driver.walletBalance) ?? 0;
    const newBalance = currentBalance - breakdown.companyRevenue;
    const lowBalance = newBalance <= CONSTANTS.WALLET_LOW_BALANCE_THRESHOLD_DZD;

    // --- 3. Driver tier / stats update ----------------------------------------
    const ridesCompleted = ((driver.ridesCompleted as number) ?? 0) + 1;
    const tier = resolveCommissionTier(ridesCompleted, (driver.ratingAverage as number) ?? 5.0, (driver.commissionTier as string) ?? "tier1");

    tx.update(driverRef, {
      walletBalance: newBalance,
      ridesCompleted,
      commissionTier: tier.tier,
      commissionRate: tier.commissionRate,
      driverShareRate: tier.driverShareRate,
      isOnTrip: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // --- 4. Wallet document + ledger entry -------------------------------------
    tx.set(
      walletRef,
      {
        driverId: uid,
        balance: newBalance,
        lowBalance,
        lastDeductionAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const ledgerRef = walletRef.collection("transactions").doc(transactionId);
    tx.set(ledgerRef, {
      transactionId,
      rideId,
      driverId: uid,
      passengerId: ride.passengerId,
      type: "ride_earning",
      baseFare: breakdown.baseFare,
      surchargeRevenue: breakdown.surchargeDzd,
      commissionRate: breakdown.commissionRate,
      commissionDeducted: breakdown.commissionAmount,
      netPayoutToDriver: breakdown.driverPayout,
      companyRevenue: breakdown.companyRevenue,
      walletBalanceAfter: newBalance,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // --- 5. Passenger loyalty points -------------------------------------------
    const pointsAwarded = computePointsAwarded(breakdown.totalFare);
    if (passengerSnap.exists) {
      const passenger = passengerSnap.data()!;
      const loyalty = (passenger.loyalty as { points?: number; totalRidesCompleted?: number }) ?? {};
      const newPoints = (loyalty.points ?? 0) + pointsAwarded;
      const newTotalRides = (loyalty.totalRidesCompleted ?? 0) + 1;

      tx.update(passengerRef, {
        "loyalty.points": newPoints,
        "loyalty.totalRidesCompleted": newTotalRides,
        "loyalty.tier": resolveLoyaltyTier(newPoints),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // --- 6. Finalize ride --------------------------------------------------------
    tx.update(rideRef, {
      status: "completed",
      actualDistanceKm,
      actualDurationMin,
      pointsAwarded,
      fare: {
        baseFare: breakdown.baseFare,
        surchargeDzd: breakdown.surchargeDzd,
        totalFare: breakdown.totalFare,
        commissionRate: breakdown.commissionRate,
        commissionAmount: breakdown.commissionAmount,
        driverPayout: breakdown.driverPayout,
        companyRevenue: breakdown.companyRevenue,
        transactionId,
      },
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(rideRef.collection("status_history").doc(), {
      status: "completed",
      actorId: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { ...breakdown, transactionId, pointsAwarded };
  });

  return {
    baseFare: result.baseFare,
    surchargeDzd: result.surchargeDzd,
    totalFare: result.totalFare,
    commissionRate: result.commissionRate,
    commissionAmount: result.commissionAmount,
    driverPayout: result.driverPayout,
    companyRevenue: result.companyRevenue,
    transactionId: result.transactionId,
  };
});
