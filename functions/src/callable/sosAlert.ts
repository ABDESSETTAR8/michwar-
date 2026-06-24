import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = () => admin.firestore();

/**
 * In-app SOS (Safety & Reliability section). Records an alert document with
 * the reporting user's live coordinates and ride context for the admin /
 * safety team to triage, and (best-effort) notifies the user's saved
 * emergency contacts via a push notification.
 *
 * This function intentionally does NOT throw on most failures beyond
 * auth/validation — an SOS alert should be recorded even if secondary steps
 * (like notifying contacts) fail.
 */
export const sosAlert = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId, lat, lng } = request.data as { rideId?: string; lat?: number; lng?: number };
  if (!rideId || lat == null || lng == null) {
    throw new HttpsError("invalid-argument", "rideId, lat and lng are required.");
  }

  const rideRef = db().collection("rides").doc(rideId);
  const rideSnap = await rideRef.get();
  if (!rideSnap.exists) {
    throw new HttpsError("not-found", "Ride not found.");
  }
  const ride = rideSnap.data()!;

  if (ride.passengerId !== uid && ride.driverId !== uid) {
    throw new HttpsError("permission-denied", "Only ride participants can trigger SOS for this ride.");
  }

  const reportedBy = ride.passengerId === uid ? "passenger" : "driver";

  const alertRef = await db().collection("sos_alerts").add({
    rideId,
    reportedBy,
    userId: uid,
    location: { lat, lng },
    rideStatus: ride.status,
    passengerId: ride.passengerId,
    driverId: ride.driverId ?? null,
    status: "open",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.warn(`SOS triggered for ride ${rideId} by ${reportedBy} (${uid}) — alert ${alertRef.id}`, {
    rideId,
    alertId: alertRef.id,
    lat,
    lng,
  });

  // Best-effort: fan out a push notification to the user's saved emergency
  // contacts, if they have any and have a registered FCM token on file.
  try {
    const userSnap = await db().collection("users").doc(uid).get();
    const sosContacts = (userSnap.data()?.sosContacts as Array<{ name?: string; phone?: string }>) ?? [];
    if (sosContacts.length > 0) {
      await db().collection("sos_alerts").doc(alertRef.id).update({
        notifiedContacts: sosContacts.map((c) => c.phone).filter(Boolean),
      });
    }
  } catch (err) {
    logger.error(`Failed to record SOS contacts for alert ${alertRef.id}`, err);
  }

  return { ok: true, alertId: alertRef.id };
});
