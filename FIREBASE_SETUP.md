# MICHWAR — Firebase Setup Guide

Complete steps to create a Firebase project, connect it to the Flutter app,
deploy Cloud Functions, and go live.

---

## Prerequisites

Install these once, globally:

```bash
# Node.js 20+ (for Cloud Functions)
# https://nodejs.org — download and install

# Firebase CLI
npm install -g firebase-tools

# FlutterFire CLI (connects Flutter to Firebase)
dart pub global activate flutterfire_cli
```

---

## Step 1 — Create the Firebase project

1. Go to **https://console.firebase.google.com**
2. Click **Add project**
3. Name it **michwar** (or anything you like)
4. Disable Google Analytics (optional) → click **Create project**
5. Wait for provisioning, then click **Continue**

---

## Step 2 — Enable Authentication

1. In the left sidebar: **Build → Authentication**
2. Click **Get started**
3. Under **Sign-in method**, click **Email/Password**
4. Enable the top toggle → **Save**

---

## Step 3 — Enable Firestore

1. Left sidebar: **Build → Firestore Database**
2. Click **Create database**
3. Choose **Start in production mode** → **Next**
4. Pick the closest region (e.g. `europe-west1` for Algeria) → **Enable**
5. Wait for the database to provision (~30 seconds)

---

## Step 4 — Enable Storage

1. Left sidebar: **Build → Storage**
2. Click **Get started**
3. Choose **Start in production mode** → **Next**
4. Same region as Firestore → **Done**

---

## Step 5 — Enable Cloud Functions

1. Left sidebar: **Build → Functions**
2. Click **Get started** → **Continue** → **Finish**
3. Cloud Functions requires the **Blaze (pay-as-you-go)** plan.
   Click **Upgrade** → link a billing account (Google gives you a free
   $300 credit; MICHWAR's traffic won't cost anything in development).

---

## Step 6 — Add the Android app

1. On the Firebase project homepage, click the **Android** icon
2. **Android package name**: open `android/app/build.gradle` in the
   project and copy the value of `applicationId`
   (default: `com.example.michwar`)
3. **App nickname**: MICHWAR Android
4. Click **Register app**
5. Click **Download google-services.json**
6. Move the downloaded file into `android/app/` (replacing any existing one)
7. Click **Next → Next → Continue to console**

---

## Step 7 — Add the Web app (for admin PWA)

1. On the Firebase project homepage, click the **Web** (</>) icon
2. **App nickname**: MICHWAR Admin
3. Leave **Firebase Hosting** unchecked
4. Click **Register app**
5. You'll see a `firebaseConfig` block like:

```js
const firebaseConfig = {
  apiKey: "AIza...",
  authDomain: "michwar-xxxxx.firebaseapp.com",
  projectId: "michwar-xxxxx",
  storageBucket: "michwar-xxxxx.appspot.com",
  messagingSenderId: "123456789",
  appId: "1:123:web:abc..."
};
```

6. **Copy these values** — you need them in two places (Steps 9 and 11).
7. Click **Continue to console**

---

## Step 8 — Connect Flutter with FlutterFire CLI

In the project root (`C:\Users\MOH\Desktop\michwar`), open a terminal and run:

```bash
# Log in to Firebase
firebase login

# Auto-configure flutter app — select the project you just created
flutterfire configure
```

When prompted:
- Select your **michwar** project
- Select **Android** (and iOS/Web if needed)
- Confirm overwriting `lib/firebase_options.dart`

This auto-fills `lib/firebase_options.dart` with the real credentials.
**You do not need to edit that file manually.**

---

## Step 9 — Update the Admin PWA config

Open `web/admin/index.html` and find this block near the bottom:

```js
const FIREBASE_CONFIG = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  ...
};
```

Replace all `YOUR_*` placeholders with the values from **Step 7**.

---

## Step 10 — Deploy Firestore rules and indexes

```bash
cd C:\Users\MOH\Desktop\michwar

# Deploy security rules
firebase deploy --only firestore:rules

# Deploy indexes (needed for compound queries)
firebase deploy --only firestore:indexes
```

---

## Step 11 — Deploy Cloud Functions

```bash
cd C:\Users\MOH\Desktop\michwar\functions

# Install dependencies
npm install

# Build TypeScript
npm run build

# Go back to project root and deploy
cd ..
firebase deploy --only functions
```

This deploys all functions including:
- `onRideRequestCreated` — geohash driver matching trigger
- `acceptRide`, `completeRide`, `updateRideStatus` — ride lifecycle
- `signupRateLimiter` — blocks mass account creation
- `seedDemoAccounts` — creates the 3 demo accounts
- `topUpWallet`, `sosAlert`, and others

Deployment takes 3–5 minutes. Watch the terminal for errors.

---

## Step 12 — Seed the demo accounts

After functions deploy, call `seedDemoAccounts` once to create the
demo logins that appear on the login screen.

**Option A — Firebase CLI (easiest):**

```bash
firebase functions:shell
# Inside the shell:
seedDemoAccounts({secret: "michwar-seed-2024"})
```

**Option B — From the Flutter app itself (temporary):**
Add a one-time call in `main.dart` after Firebase init:

```dart
import 'package:cloud_functions/cloud_functions.dart';

// After Firebase.initializeApp(...)
await FirebaseFunctions.instance
    .httpsCallable('seedDemoAccounts')
    .call({'secret': 'michwar-seed-2024'});
```

Remove this line after running once.

**Demo accounts created:**
| Email | Password | Role |
|---|---|---|
| demo.passenger@michwar.dz | Demo@1234 | Passenger |
| demo.driver@michwar.dz | Demo@1234 | Driver |
| demo.admin@michwar.dz | Demo@1234 | Admin |

---

## Step 13 — Create the admin superuser

The admin dashboard requires a Firebase Auth account with `role: "admin"`
in Firestore. Create it manually:

1. In Firebase Console → **Authentication → Users → Add user**
2. Email: `admin@michwar.dz`, set a strong password
3. Copy the **UID** shown in the users table
4. In **Firestore → users → Add document**:
   - Document ID: *(the UID you copied)*
   - Fields:
     ```
     email        (string)  admin@michwar.dz
     fullName     (string)  Admin
     role         (string)  admin
     roleSelected (boolean) true
     ```

---

## Step 14 — Flutter: install packages and run

```bash
cd C:\Users\MOH\Desktop\michwar

# Install/update all packages
flutter pub get

# Run on connected Android device or emulator
flutter run

# Release APK
flutter build apk --release
```

---

## Step 15 — Access the Admin PWA

The admin dashboard at `web/admin/index.html` is a standalone HTML file.
**No hosting setup required** — open it directly in a browser:

```
file:///C:/Users/MOH/Desktop/michwar/web/admin/index.html
```

Or serve it with any static server:

```bash
# Quick local server (Python)
cd web/admin && python -m http.server 8080
# Open: http://localhost:8080
```

Sign in with the admin credentials you created in Step 13.

To install it as a PWA on your phone:
- Open the URL in Chrome on Android
- Tap the browser menu → **Add to Home screen**

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `firebase_options.dart` still has placeholder values | Run `flutterfire configure` again from the project root |
| `google-services.json` not found error | Make sure the file is in `android/app/`, not the project root |
| Functions deploy fails on Windows | Use PowerShell or WSL; avoid Command Prompt |
| `PERMISSION_DENIED` in Firestore | Re-deploy the rules: `firebase deploy --only firestore:rules` |
| Admin PWA shows blank / CORS error | Make sure `FIREBASE_CONFIG` in `index.html` has the real values |
| Demo accounts login fails | Re-run `seedDemoAccounts` (it is idempotent) |

---

## What each Firebase service is used for

| Service | Usage in MICHWAR |
|---|---|
| **Firebase Auth** | Email + password login for passengers, drivers, admins |
| **Firestore** | All collections: users, drivers, rides, wallets, etc. |
| **Cloud Functions** | Authoritative business logic: pricing, matching, fare calculation |
| **Storage** | Driver verification document uploads |
| **Firestore Rules** | Row-level security — clients can only read/write their own data |
