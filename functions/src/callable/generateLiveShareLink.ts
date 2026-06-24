import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { CONSTANTS } from "../config/constants";

const db = () => admin.firestore();

// TODO(deploy): replace with the production web domain that hosts the
// public "Live Trip Sharing" viewer page (Firebase Hosting). Must match
// `LIVE_SHARE_BASE_URL` in `.env.example`.
const LIVE_SHARE_BASE_URL = "https://michwar-prod.web.app/track";

/**
 * Creates a short-lived, unauthenticated-readable link so a passenger (or
 * driver) can share their live trip location with a contact who doesn't
 * have the app. Writes a `live_shares/{token}` document (matched by
 * `firestore.rules` for public read while `expiresAt` is in the future) and
 * stamps `rides/{rideId}.liveShareToken` / `liveShareExpiresAt`.
 */
export const generateLiveShareLink = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { rideId } = request.data as { rideId?: string };
  if (!rideId) {
    throw new HttpsError("invalid-argument", "rideId is required.");
  }

  const rideRef = db().collection("rides").doc(rideId);
  const rideSnap = await rideRef.get();
  if (!rideSnap.exists) {
    throw new HttpsError("not-found", "Ride not found.");
  }
  const ride = rideSnap.data()!;

  if (ride.passengerId !== uid && ride.driverId !== uid) {
    throw new HttpsError("permission-denied", "Only ride participants can share this trip.");
  }

  const token = crypto.randomBytes(16).toString("hex");
  const expiresAtMs = Date.now() + CONSTANTS.LIVE_SHARE_LINK_VALIDITY_MS;
  const expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);

  await Promise.all([
    db().collection("live_shares").doc(token).set({
      rideId,
      createdBy: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    }),
    rideRef.update({
      liveShareToken: token,
      liveShareExpiresAt: expiresAt,
    }),
  ]);

  return { url: `${LIVE_SHARE_BASE_URL}/${token}`, expiresAt: expiresAtMs };
});
