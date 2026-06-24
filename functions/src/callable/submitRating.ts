import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { resolveCommissionTier } from "../utils/pricing";

const db = () => admin.firestore();

/**
 * The passenger rates the driver after a completed ride (1-5 stars + an
 * optional comment). Recomputes the driver's running `ratingAverage` /
 * `ratingCount` and re-checks Elite-tier eligibility, since promotion to
 * tier2 requires `ratingAverage >= ELITE_MIN_AVERAGE_RATING`.
 */
export const submitRating = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId, stars, comment } = request.data as { rideId?: string; stars?: number; comment?: string };
  if (!rideId || stars == null) {
    throw new HttpsError("invalid-argument", "rideId and stars are required.");
  }
  if (stars < 1 || stars > 5) {
    throw new HttpsError("invalid-argument", "stars must be between 1 and 5.");
  }

  const rideRef = db().collection("rides").doc(rideId);

  await db().runTransaction(async (tx) => {
    const rideSnap = await tx.get(rideRef);
    if (!rideSnap.exists) {
      throw new HttpsError("not-found", "Ride not found.");
    }
    const ride = rideSnap.data()!;

    if (ride.passengerId !== uid) {
      throw new HttpsError("permission-denied", "Only the passenger can rate this ride.");
    }
    if (ride.status !== "completed") {
      throw new HttpsError("failed-precondition", "Only completed rides can be rated.");
    }
    if (ride.rating) {
      throw new HttpsError("already-exists", "This ride has already been rated.");
    }
    if (!ride.driverId) {
      throw new HttpsError("failed-precondition", "This ride has no assigned driver.");
    }

    const rating: Record<string, unknown> = { stars };
    if (comment) rating.comment = comment;

    // All reads must happen before any writes within a transaction.
    const driverRef = db().collection("drivers").doc(ride.driverId as string);
    const driverSnap = await tx.get(driverRef);

    tx.update(rideRef, { rating });

    if (driverSnap.exists) {
      const driver = driverSnap.data()!;
      const prevCount = (driver.ratingCount as number) ?? 0;
      const prevAverage = (driver.ratingAverage as number) ?? 5.0;
      const newCount = prevCount + 1;
      const newAverage = (prevAverage * prevCount + stars) / newCount;

      const tier = resolveCommissionTier(
        (driver.ridesCompleted as number) ?? 0,
        newAverage,
        (driver.commissionTier as string) ?? "tier1"
      );

      tx.update(driverRef, {
        ratingAverage: newAverage,
        ratingCount: newCount,
        commissionTier: tier.tier,
        commissionRate: tier.commissionRate,
        driverShareRate: tier.driverShareRate,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  return { ok: true };
});
