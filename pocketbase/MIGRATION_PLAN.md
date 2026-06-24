# MICHWAR: Firebase → PocketBase Migration Plan

This document maps the current Firebase design (Firestore + Auth + Storage + Cloud
Functions) to a self-hosted PocketBase backend, and tracks the Flutter-side changes
needed to use it.

PocketBase version targeted: **0.23.x** (JSVM migrations/hooks, `app.save()` /
`app.findCollectionByNameOrId()` API, `fields` schema format).

Run locally with: `./pocketbase serve` from the `pocketbase/` directory (migrations in
`pb_migrations/` apply automatically on first run; hooks in `pb_hooks/` are loaded
automatically).

---

## 1. Authentication

**Old**: Firebase Phone Auth (OTP via SMS), `users/{uid}` Firestore profile doc.

**New**: PocketBase `users` **auth collection** with email + password.
- `phoneNumber` becomes a plain profile field (no longer used for login).
- Signup: `POST /api/collections/users/records` (PocketBase auto-hashes password).
- Login: `POST /api/collections/users/auth-with-password`.
- Session: PocketBase auth token stored by the Dart SDK's `AuthStore`
  (persisted via `AsyncAuthStore` + `shared_preferences`).
- The old "Dev: Skip phone verification" button is replaced by a normal
  email/password login — for local testing, just create a real account.

---

## 2. Collection Schema Mapping

| Firestore | PocketBase collection | Notes |
|---|---|---|
| `users/{uid}` | `users` (auth) | role, loyalty*, savedPlaces, sosContacts, fcmTokens, avatar (file) |
| `drivers/{uid}` | `drivers` | `user` relation (1:1, unique) instead of shared doc ID |
| `rides/{rideId}` | `rides` | `passenger`/`driver` relations replace string uids |
| `rides/{id}/status_history` | `ride_status_history` | `ride` relation + `actor` relation |
| `wallets/{driverId}` | `wallets` | `driver` relation (1:1, unique) |
| `wallets/{id}/transactions` | `wallet_transactions` | `driver`/`ride`/`passenger` relations |
| `live_shares/{token}` | `live_shares` | record `id` itself acts as the share token |
| `sos_alerts/{id}` | `sos_alerts` | `ride`/`user`/`passenger`/`driver` relations |
| `heatmap_cells/{geohash}` | `heatmap_cells` | `geohash` text field (unique) |
| `transactions/{id}` (unused) | — | dropped |
| `ratings/{id}` (unused) | — | dropped (rating stays embedded in `rides`) |
| `driver_documents/{uid}/{type}` (Storage) | `drivers.documents` | PocketBase native multi-file field + `documentsMeta` json for status |

Geo fields: PocketBase has no native geo type. Keep `lat`/`lng` as numbers and
`geohash` as an indexed text field (same geohash algorithm, ported to JS in hooks
and to Dart in `geohash_util.dart` — already exists, just needs precision check
against `functions/src/utils/geohash.ts`, precision 7).

---

## 3. Cloud Functions → PocketBase Hooks / Custom Routes

All financial/authoritative writes move from "Admin-SDK-only Cloud Functions" to
"PocketBase hooks running with full DB access, exposed via custom routes". Routes
require an authenticated user (`$apis.requireAuth()` style in 0.23: check
`e.auth` is non-nil).

| Cloud Function | PocketBase equivalent |
|---|---|
| `onRideRequestCreated` (Firestore trigger) | `OnRecordAfterCreateSuccess` hook on `rides` (status=searching) → geohash driver matching, sets `candidateDriverIds` |
| `acceptRide` (callable) | `POST /api/michwar/rides/:id/accept` |
| `updateRideStatus` (callable) | `POST /api/michwar/rides/:id/status` |
| `completeRide` (callable) | `POST /api/michwar/rides/:id/complete` |
| `submitRating` (callable) | `POST /api/michwar/rides/:id/rate` |
| `topUpWallet` (callable) | `POST /api/michwar/wallet/topup` |
| `sosAlert` (callable) | `POST /api/michwar/sos` |
| `generateLiveShareLink` (callable) | `POST /api/michwar/rides/:id/share` |

All routes use `app.runInTransaction()` (equivalent of Firestore transactions) and
reuse the same business-logic constants as `functions/src/config/constants.ts`
(ported to `pocketbase/pb_hooks/lib/constants.js`).

---

## 4. API Rules (replacing `firestore.rules` / `storage.rules`)

General principle (same as before): clients can **read** their own/related records
and **create** initial ride requests, but all financial/status mutations go through
hook routes (which use `$app` directly and bypass collection rules). Direct
`update`/`delete` API rules on protected collections are set to `null` (locked) so
only the hooks — running as the system — can write them.

| Collection | list/view | create | update | delete |
|---|---|---|---|---|
| `users` | view: self or admin | public (signup) | self (non-financial fields only — enforced in `OnRecordUpdateRequest` hook) | — |
| `drivers` | any authenticated user | self (`switchRole` flow) | self for `isOnline`/`headingHome`/`location`/docs; rest hook-only | — |
| `rides` | participants or admin | passenger (initial `searching` doc) | hook-only (`null`) | — |
| `ride_status_history` | participants or admin | hook-only | hook-only | — |
| `wallets` | owner or admin | hook-only | hook-only | — |
| `wallet_transactions` | owner driver or admin | hook-only | hook-only | — |
| `live_shares` | public while unexpired | hook-only | hook-only | — |
| `sos_alerts` | reporter or admin | hook-only | hook-only | — |
| `heatmap_cells` | any authenticated user | any authenticated user | any authenticated user (increment) | — |

---

## 5. Flutter-side Changes

1. **pubspec.yaml**: remove `firebase_*` packages, add `pocketbase`,
   `shared_preferences` (for `AsyncAuthStore`).
2. **`lib/main.dart`**: remove `Firebase.initializeApp` / emulator wiring; init
   `PocketBaseService` with base URL from `.env` (`POCKETBASE_URL`).
3. **`lib/core/services/`**: new `pocketbase_service.dart` (client singleton);
   `auth_service.dart` rewritten for email/password (`signUp`, `signIn`, `signOut`,
   `authStateChanges` via `pb.authStore.onChange`).
4. **Authentication feature**: replace phone-entry/OTP screens with
   email + password sign-up/sign-in screens; `role_selection_screen.dart` keeps
   creating the `drivers`/`wallets` records via a hook route (`/api/michwar/role`)
   instead of direct Firestore writes (since `drivers`/`wallets` create is hook-only
   for consistency with welcome-credit logic).
5. **Repositories** (`ride_repository.dart`, `driver_repository.dart`,
   `geohash_service.dart`, `driver_document_service.dart`, `auth_service.dart`):
   swap `cloud_firestore` calls for `pb.collection(...).getList/getOne/create/update`
   and `pb.collection(...).subscribe('*', ...)` for realtime; swap Cloud Functions
   `httpsCallable` for `pb.send('/api/michwar/...', method: 'POST', body: {...})`.
6. **Models** (`lib/core/models/*.dart`): flatten nested maps that PocketBase
   stores as top-level fields (e.g. `pickup.lat` → `pickup_lat`) OR keep as `json`
   field type and parse client-side (chosen approach: **keep nested objects as
   PocketBase `json` fields** to minimize model/UI changes — only `passengerId`/
   `driverId` etc. become PocketBase relation id strings, which the models already
   treat as plain strings).
7. **Storage**: driver verification docs uploaded via PocketBase's multipart
   record create/update (`files` field on `drivers`) instead of
   `firebase_storage`.
8. **Remove**: `lib/firebase_options.dart`, `.firebaserc`, `firebase.json`,
   `firestore.rules`, `firestore.indexes.json`, `storage.rules`, `functions/`
   (Cloud Functions code — superseded by `pocketbase/pb_hooks/`).

---

## 6. Deployment

PocketBase ships as a single static binary + `pb_data/` directory. Deployment options:
- Any small VPS (1 vCPU/512MB is plenty for MVP traffic): copy `pocketbase/` folder,
  run `./pocketbase serve --http=0.0.0.0:8090`, put behind Caddy/Nginx for HTTPS.
- Fly.io / Railway / Render: Docker image running the binary, persistent volume for
  `pb_data/`.
- The Flutter app points at `https://<your-domain>` via `POCKETBASE_URL` in `.env`
  (and `--dart-define` for release builds) — works from any phone/network, no
  Google billing required.

---

## 7. Status

- [x] Inventory of current Firebase usage (this doc, §1-4)
- [ ] `pocketbase/pb_migrations/*.js` — collection schema + API rules
- [ ] `pocketbase/pb_hooks/*.pb.js` — business-logic routes
- [ ] Flutter: PocketBase SDK + service layer
- [ ] Flutter: auth screens (email/password)
- [ ] Flutter: passenger/driver/ride_engine repositories
- [ ] Remove Firebase artifacts, update docs
- [ ] End-to-end verification against local `pocketbase serve`
