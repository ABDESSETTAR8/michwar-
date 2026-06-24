import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

/**
 * A driver accepts a ride request. Runs inside a Firestore transaction so
 * that two drivers racing to accept the same `searching` ride can't both
 * succeed — only the first wins, the second gets an error and should
 * silently dismiss its incoming-request sheet.
 */
export const acceptRide = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId, driverId } = request.data as { rideId?: string; driverId?: string };
  if (!rideId || !driverId) {
    throw new HttpsError("invalid-argument", "rideId and driverId are required.");
  }
  if (driverId !== uid) {
    throw new HttpsError("permission-denied", "driverId must match the authenticated user.");
  }

  const rideRef = db().collection("rides").doc(rideId);
  const driverRef = db().collection("drivers").doc(driverId);

  await db().runTransaction(async (tx) => {
    const [rideSnap, driverSnap] = await Promise.all([tx.get(rideRef), tx.get(driverRef)]);

    if (!rideSnap.exists) {
      throw new HttpsError("not-found", "Ride not found.");
    }
    if (!driverSnap.exists) {
      throw new HttpsError("not-found", "Driver profile not found.");
    }

    const ride = rideSnap.data()!;
    const driver = driverSnap.data()!;

    if (ride.status !== "searching" || ride.driverId) {
      throw new HttpsError("failed-precondition", "This ride has already been accepted by another driver.");
    }
    if (driver.isOnTrip) {
      throw new HttpsError("failed-precondition", "You already have an active trip.");
    }
    if ((driver.walletBalance ?? 0) <= 200) {
      throw new HttpsError("failed-precondition", "Your wallet balance is too low to accept new rides.");
    }

    tx.update(rideRef, {
      driverId,
      status: "accepted",
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(driverRef, {
      isOnTrip: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(rideRef.collection("status_history").doc(), {
      status: "accepted",
      actorId: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});
