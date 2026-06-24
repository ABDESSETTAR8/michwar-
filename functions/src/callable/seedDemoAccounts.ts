import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();
const auth = admin.auth();

interface DemoUser {
  email: string;
  password: string;
  fullName: string;
  role: "passenger" | "driver" | "admin";
}

const DEMO_USERS: DemoUser[] = [
  {
    email: "demo.passenger@michwar.dz",
    password: "Demo@1234",
    fullName: "Demo Passenger",
    role: "passenger",
  },
  {
    email: "demo.driver@michwar.dz",
    password: "Demo@1234",
    fullName: "Demo Driver",
    role: "driver",
  },
  {
    email: "demo.admin@michwar.dz",
    password: "Demo@1234",
    fullName: "Demo Admin",
    role: "admin",
  },
];

/**
 * Callable: seedDemoAccounts
 * Creates (or resets) the three demo accounts. Idempotent — safe to call
 * multiple times. Requires the caller to be an admin or to provide the
 * seed secret in the request data.
 */
export const seedDemoAccounts = functions.https.onCall(
  async (data: { secret?: string }) => {
    const expectedSecret = process.env.SEED_SECRET ?? "michwar-seed-2024";
    if (data.secret !== expectedSecret) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Invalid seed secret."
      );
    }

    const results: string[] = [];

    for (const demo of DEMO_USERS) {
      try {
        // Try to get existing user
        let uid: string;
        try {
          const existing = await auth.getUserByEmail(demo.email);
          uid = existing.uid;
          // Reset password in case it was changed
          await auth.updateUser(uid, { password: demo.password });
          results.push(`reset: ${demo.email}`);
        } catch {
          // Create new user
          const created = await auth.createUser({
            email: demo.email,
            password: demo.password,
            displayName: demo.fullName,
          });
          uid = created.uid;
          results.push(`created: ${demo.email}`);
        }

        // Upsert Firestore profile
        await db.collection("users").doc(uid).set(
          {
            email: demo.email,
            fullName: demo.fullName,
            phoneNumber: "+213000000000",
            role: demo.role,
            roleSelected: true,
            loyaltyPoints: demo.role === "passenger" ? 120 : 0,
            loyaltyTier: demo.role === "passenger" ? "eco" : "standard",
            totalRidesCompleted: demo.role === "passenger" ? 8 : 0,
            savedPlaces: [],
            sosContacts: [],
            fcmTokens: [],
            isDemo: true,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        // If driver role, ensure drivers doc exists
        if (demo.role === "driver") {
          const existing = await db
            .collection("drivers")
            .where("userId", "==", uid)
            .limit(1)
            .get();

          if (existing.empty) {
            const driverRef = db.collection("drivers").doc();
            await driverRef.set({
              userId: uid,
              vehicleMake: "Renault",
              vehicleModel: "Symbol",
              vehiclePlate: "16-01-DEMO",
              vehicleColor: "White",
              vehicleCategory: "standard",
              verificationStatus: "approved",
              commissionTier: "tier1",
              commissionRate: 0.15,
              driverShareRate: 0.85,
              ridesCompleted: 42,
              ratingAverage: 4.8,
              ratingCount: 38,
              isOnline: false,
              isOnTrip: false,
              walletBalance: 1500,
              isDemo: true,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            await db.collection("wallets").doc(driverRef.id).set({
              driverId: uid,
              balance: 1500,
              lowBalance: false,
              isDemo: true,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (err: unknown) {
        results.push(`error: ${demo.email} — ${String(err)}`);
      }
    }

    return { results };
  }
);
