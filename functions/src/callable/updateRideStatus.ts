import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

/** Non-financial ride status transitions and who may perform them. */
const ALLOWED_TRANSITIONS: Record<string, { from: string[]; actor: "driver" | "passenger" | "either" }> = {
  arrived: { from: ["accepted"], actor: "driver" },
  ongoing: { from: ["arrived"], actor: "driver" },
  cancelled_by_driver: { from: ["accepted", "arrived"], actor: "driver" },
  cancelled_by_passenger: { from: ["searching", "accepted", "arrived"], actor: "passenger" },
};

const TIMESTAMP_FIELD: Record<string, string> = {
  arrived: "arrivedAt",
  ongoing: "startedAt",
};

/**
 * Validated, non-financial ride lifecycle transitions: `arrived`,
 * `ongoing`, `cancelled_by_driver`, `cancelled_by_passenger`. The final
 * `completed` transition is handled exclusively by `completeRide`, which
 * also performs the financial split.
 */
export const updateRideStatus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId, status } = request.data as { rideId?: string; status?: string };
  if (!rideId || !status) {
    throw new HttpsError("invalid-argument", "rideId and status are required.");
  }

  const transition = ALLOWED_TRANSITIONS[status];
  if (!transition) {
    throw new HttpsError("invalid-argument", `Unsupported status transition: ${status}`);
  }

  const rideRef = db().collection("rides").doc(rideId);

  await db().runTransaction(async (tx) => {
    const rideSnap = await tx.get(rideRef);
    if (!rideSnap.exists) {
      throw new HttpsError("not-found", "Ride not found.");
    }
    const ride = rideSnap.data()!;

    if (!transition.from.includes(ride.status)) {
      throw new HttpsError("failed-precondition", `Cannot move ride from '${ride.status}' to '${status}'.`);
    }

    const isDriver = ride.driverId === uid;
    const isPassenger = ride.passengerId === uid;

    if (transition.actor === "driver" && !isDriver) {
      throw new HttpsError("permission-denied", "Only the assigned driver can perform this action.");
    }
    if (transition.actor === "passenger" && !isPassenger) {
      throw new HttpsError("permission-denied", "Only the passenger can perform this action.");
    }

    const update: Record<string, unknown> = { status };
    const timestampField = TIMESTAMP_FIELD[status];
    if (timestampField) {
      update[timestampField] = admin.firestore.FieldValue.serverTimestamp();
    }

    if (status === "cancelled_by_driver" || status === "cancelled_by_passenger") {
      update.cancelledAt = admin.firestore.FieldValue.serverTimestamp();
    }

    tx.update(rideRef, update);

    tx.set(rideRef.collection("status_history").doc(), {
      status,
      actorId: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Free up the driver if the ride is cancelled after acceptance.
    if ((status === "cancelled_by_driver" || status === "cancelled_by_passenger") && ride.driverId) {
      const driverRef = db().collection("drivers").doc(ride.driverId);
      tx.update(driverRef, {
        isOnTrip: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  return { ok: true };
});
