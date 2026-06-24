import * as admin from "firebase-admin";

admin.initializeApp();

// --- Firestore triggers -----------------------------------------------------
export { onRideRequestCreated } from "./triggers/onRideRequestCreated";

// --- Callable functions (invoked from the Flutter app) ----------------------
export { acceptRide } from "./callable/acceptRide";
export { updateRideStatus } from "./callable/updateRideStatus";
export { completeRide } from "./callable/completeRide";
export { submitRating } from "./callable/submitRating";
export { sosAlert } from "./callable/sosAlert";
export { generateLiveShareLink } from "./callable/generateLiveShareLink";
export { topUpWallet } from "./callable/topUpWallet";
export { seedDemoAccounts } from "./callable/seedDemoAccounts";
export { signupRateLimiter } from "./triggers/signupRateLimiter";
