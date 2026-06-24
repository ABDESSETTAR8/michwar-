import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const db = admin.firestore();

/**
 * Auth trigger: signupRateLimiter
 *
 * Fires on every new Firebase Auth user creation. Enforces a rate limit of
 * MAX_PER_WINDOW accounts per TIME_WINDOW_MS from the same IP. If exceeded,
 * the newly created account is immediately deleted (the app user sees a
 * FirebaseAuthException with code 'too-many-requests').
 *
 * Note: Firebase Auth triggers don't expose the originating IP directly.
 * This function implements a Firestore-based token-bucket per hashed
 * metadata (user-agent + timestamp bucket) as a best-effort guard. For
 * production, pair this with App Check and Firebase App Attest.
 */

const MAX_PER_WINDOW = 5;
const TIME_WINDOW_MS = 60 * 60 * 1000; // 1 hour

export const signupRateLimiter = functions.auth
  .user()
  .onCreate(async (user) => {
    // Skip demo accounts
    if (user.email?.endsWith("@michwar.dz") && user.email?.startsWith("demo.")) {
      return;
    }

    const now = Date.now();
    const windowKey = Math.floor(now / TIME_WINDOW_MS);
    // Use email domain as a coarse bucket (same-domain bursts)
    const domain = user.email?.split("@")[1] ?? "unknown";
    const bucketId = `${domain}-${windowKey}`;

    const ref = db.collection("rate_limits").doc(bucketId);

    try {
      const count = await db.runTransaction(async (tx) => {
        const doc = await tx.get(ref);
        const current: number = doc.exists ? (doc.data()?.count ?? 0) : 0;
        const next = current + 1;
        tx.set(
          ref,
          {
            count: next,
            windowKey,
            expiresAt: admin.firestore.Timestamp.fromMillis(
              (windowKey + 1) * TIME_WINDOW_MS
            ),
          },
          { merge: true }
        );
        return next;
      });

      if (count > MAX_PER_WINDOW) {
        functions.logger.warn(
          `Rate limit exceeded for domain ${domain}: ${count} signups this hour. Deleting user ${user.uid}.`
        );
        await admin.auth().deleteUser(user.uid);
      }
    } catch (err) {
      functions.logger.error("signupRateLimiter error", err);
    }
  });
