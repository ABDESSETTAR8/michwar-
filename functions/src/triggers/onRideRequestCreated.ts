import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { CONSTANTS } from "../config/constants";
import { bearingDeg, cellSizeKm, distanceKm, geohashQueryBounds, neighborsForRadius } from "../utils/geohash";

const db = () => admin.firestore();

interface CandidateDriver {
  id: string;
  distanceKm: number;
}

/**
 * Geohash-based driver matching (Section: "Core Logic - Matching Engine").
 *
 * Triggered whenever a passenger creates `rides/{rideId}` with
 * `status: searching`. Queries the `drivers` collection for online,
 * available drivers within an expanding radius, ranks them by distance
 * (with a small bonus for drivers whose "Heading Home" direction aligns
 * with the ride's drop-off), and writes up to
 * `CONSTANTS.MAX_CANDIDATE_DRIVERS` driver IDs to `candidateDriverIds`.
 *
 * If no drivers are found even at `MAX_DRIVER_SEARCH_RADIUS_KM`, the ride
 * is marked `no_drivers_found` so the passenger app can show a retry CTA.
 */
export const onRideRequestCreated = onDocumentCreated("rides/{rideId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const ride = snap.data();
  if (ride.status !== "searching") return;

  const pickup = ride.pickup as { lat: number; lng: number } | undefined;
  if (!pickup) {
    logger.warn(`Ride ${event.params.rideId} has no pickup location.`);
    return;
  }

  let candidates: CandidateDriver[] = [];
  let radiusKm = CONSTANTS.DEFAULT_DRIVER_SEARCH_RADIUS_KM;

  while (candidates.length === 0 && radiusKm <= CONSTANTS.MAX_DRIVER_SEARCH_RADIUS_KM) {
    candidates = await findCandidateDrivers(pickup.lat, pickup.lng, radiusKm, ride.dropoff);
    if (candidates.length === 0) {
      radiusKm *= 2;
    }
  }

  const rideRef = db().collection("rides").doc(event.params.rideId);

  if (candidates.length === 0) {
    await rideRef.update({
      status: "no_drivers_found",
      candidateDriverIds: [],
    });
    return;
  }

  const candidateIds = candidates
    .sort((a, b) => a.distanceKm - b.distanceKm)
    .slice(0, CONSTANTS.MAX_CANDIDATE_DRIVERS)
    .map((c) => c.id);

  await rideRef.update({ candidateDriverIds: candidateIds });
});

async function findCandidateDrivers(
  lat: number,
  lng: number,
  radiusKm: number,
  dropoff?: { lat: number; lng: number }
): Promise<CandidateDriver[]> {
  let precision = CONSTANTS.GEOHASH_PRECISION;
  for (let p = 1; p <= 9; p++) {
    if (cellSizeKm(p) >= radiusKm) precision = p;
  }

  const prefixes = neighborsForRadius(lat, lng, radiusKm, precision);
  const seen = new Map<string, FirebaseFirestore.DocumentData>();

  await Promise.all(
    prefixes.map(async (prefix) => {
      const { start, end } = geohashQueryBounds(prefix);
      const snap = await db()
        .collection("drivers")
        .where("isOnline", "==", true)
        .where("isOnTrip", "==", false)
        .where("location.geohash", ">=", start)
        .where("location.geohash", "<", end)
        .limit(20)
        .get();

      snap.forEach((doc) => {
        if (!seen.has(doc.id)) seen.set(doc.id, doc.data());
      });
    })
  );

  const candidates: CandidateDriver[] = [];

  for (const [id, driver] of seen.entries()) {
    const walletBalance = (driver.walletBalance as number) ?? 0;
    const verificationStatus = driver.verification?.status as string | undefined;
    if (verificationStatus !== "approved") continue;
    if (walletBalance <= CONSTANTS.WALLET_LOW_BALANCE_THRESHOLD_DZD) continue;

    const location = driver.location as { lat: number; lng: number } | undefined;
    if (!location) continue;

    const dKm = distanceKm(lat, lng, location.lat, location.lng);
    if (dKm > radiusKm) continue;

    // "Heading Home" preference: if enabled and the ride's drop-off roughly
    // aligns with the driver's bearing toward home, treat the driver as
    // slightly closer so they're prioritized for a "last ride home".
    let effectiveDistance = dKm;
    const headingHome = driver.headingHome as
      | { enabled?: boolean; destinationLat?: number; destinationLng?: number; bearingToleranceDeg?: number }
      | undefined;

    if (headingHome?.enabled && headingHome.destinationLat != null && headingHome.destinationLng != null && dropoff) {
      const bearingToHome = bearingDeg(location.lat, location.lng, headingHome.destinationLat, headingHome.destinationLng);
      const bearingToDropoff = bearingDeg(location.lat, location.lng, dropoff.lat, dropoff.lng);
      const diff = Math.abs(((bearingToHome - bearingToDropoff + 540) % 360) - 180);
      const tolerance = headingHome.bearingToleranceDeg ?? 30;
      if (diff <= tolerance) {
        effectiveDistance = Math.max(0, dKm - 1.0); // priority bonus
      }
    }

    candidates.push({ id, distanceKm: effectiveDistance });
  }

  return candidates;
}
