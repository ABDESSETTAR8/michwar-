import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CONSTANTS } from "../config/constants";

const db = () => admin.firestore();

/**
 * Driver pre-paid wallet top-up (Section 6.C). In production this would be
 * called from a payment-provider webhook after a successful charge; for
 * this build it directly credits the driver's wallet so the app is fully
 * testable without a live payment integration.
 */
export const topUpWallet = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const { amountDzd } = request.data as { amountDzd?: number };
  if (amountDzd == null || amountDzd <= 0) {
    throw new HttpsError("invalid-argument", "amountDzd must be a positive number.");
  }

  const driverRef = db().collection("drivers").doc(uid);
  const walletRef = db().collection("wallets").doc(uid);
  const transactionId = db().collection("_ids").doc().id;

  const newBalance = await db().runTransaction(async (tx) => {
    const [driverSnap, walletSnap] = await Promise.all([tx.get(driverRef), tx.get(walletRef)]);
    if (!driverSnap.exists) {
      throw new HttpsError("not-found", "Driver profile not found.");
    }

    const driver = driverSnap.data()!;
    const currentBalance = (walletSnap.exists ? (walletSnap.data()!.balance as number) : driver.walletBalance) ?? 0;
    const updatedBalance = currentBalance + amountDzd;
    const lowBalance = updatedBalance <= CONSTANTS.WALLET_LOW_BALANCE_THRESHOLD_DZD;

    tx.update(driverRef, {
      walletBalance: updatedBalance,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(
      walletRef,
      {
        driverId: uid,
        balance: updatedBalance,
        lowBalance,
        lastTopUpAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    tx.set(walletRef.collection("transactions").doc(transactionId), {
      transactionId,
      driverId: uid,
      type: "wallet_top_up",
      baseFare: 0,
      surchargeRevenue: 0,
      commissionRate: 0,
      commissionDeducted: 0,
      netPayoutToDriver: amountDzd,
      companyRevenue: 0,
      walletBalanceAfter: updatedBalance,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return updatedBalance;
  });

  return { newBalance, transactionId };
});
