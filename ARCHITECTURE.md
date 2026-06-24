# MICHWAR — Architecture

## 1. High-level shape

```
┌─────────────────────────────┐        ┌──────────────────────────────────┐
│  Flutter app (lib/)          │        │  PocketBase backend                │
│                               │        │  (single Go binary + SQLite)       │
│  features/authentication ────┼───────►│  users (auth collection)           │
│  features/passenger      ────┼───────►│  rides, ride_status_history, ...   │
│  features/driver         ────┼───────►│  drivers, wallets, wallet_tx, ...   │
│  features/ride_engine    ────┼───────►│  pb_hooks/*.pb.js (custom routes)  │
│  features/shared          ───┼───────►│  file storage (driver documents)   │
│                               │        │  realtime (SSE subscriptions)      │
└───────────────┬───────────────┘        └──────────────────────────────────┘
                │
                ▼
          core/ (shared theme, models, constants, routing, services)
```

The app is **feature-first**: each feature folder owns its screens,
providers, and (where relevant) a `services/*_repository.dart` that wraps
PocketBase collection/route access via the `pocketbase` Dart SDK. `core/`
holds everything shared across features — record models, app-wide constants
(the single source of truth mirrored into `pocketbase/pb_hooks/00_constants.pb.js`),
theming, routing (`go_router`), and cross-cutting services (auth, location,
connectivity, notifications, offline sync).

The PocketBase base URL is resolved by
`lib/core/services/pocketbase_service.dart` (`pocketbaseBaseUrl()`),
defaulting to `http://10.0.2.2:8090` on the Android emulator and overridable
via `--dart-define=POCKETBASE_URL=...` for real devices / production.

## 2. State management (Riverpod)

- `core/providers/app_providers.dart` exposes the foundational streams:
  `pocketbaseProvider` (the shared `PocketBase` client), `authStateProvider`
  (current user id, derived from `pb.authStore.onChange`),
  `userProfileProvider` (`users/{id}`, realtime-subscribed),
  `driverProfileProvider` (`drivers/{id}`, realtime-subscribed), and
  `activeRoleProvider`.
- Each feature adds its own providers (e.g.
  `lib/features/driver/providers/driver_providers.dart` for
  `earningsProvider`, incoming-request streams, etc.;
  `lib/features/ride_engine/providers/` for the active ride stream).
- Screens are `ConsumerWidget`/`ConsumerStatefulWidget`s that `watch()`
  these providers — no manual `StreamBuilder` nesting. Realtime updates use
  PocketBase's SSE-based `subscribe()` API on a collection or record id,
  functionally equivalent to a Firestore `DocumentReference.snapshots()`
  listener.

## 3. Navigation (`go_router`)

`lib/core/routing/app_router.dart` defines `AppRoutes` (route name
constants) and the `GoRouter` config, gated by `authStateProvider` /
`activeRoleProvider` (redirects unauthenticated users to the auth flow, and
routes drivers vs. passengers to their respective home screens, and
unverified drivers to `DocumentUploadScreen`).

## 4. The matching & ride lifecycle

```
Passenger app                PocketBase collections        pb_hooks/12_rides.pb.js
─────────────                ───────────────────────       ────────────────────────
requestRide() ──create──► rides/{id}
  status: searching                       ──onRecordAfterCreateSuccess──► matching
                                                          │ expanding-radius
                                                          │ geohash query on
                                                          │ drivers (online,
                                                          │ !onTrip, category
                                                          │ matches rideTier)
                              candidateDriverIds ◄────────┘ (or
                              status: no_drivers_found        no_drivers_found)

Driver app
──────────
watchIncomingRequests() ◄── rides where status='searching'
                              && candidateDriverIds contains me
                              (realtime subscribe on `rides`)

acceptRide(rideId) ──POST /api/michwar/rides/:id/accept──► (runInTransaction)
                              rides.status = accepted          │
                              rides.driver = me                │
                              drivers/{me}.isOnTrip = true ◄────┘
                              + ride_status_history row

updateStatus('arrived'/'ongoing'/cancelled_*)
                    ──POST /api/michwar/rides/:id/status──► (runInTransaction)
                              rides.status = ...                │
                              + ride_status_history row ◄───────┘

completeRide({actualDistanceKm, actualDurationMin})
                    ──POST /api/michwar/rides/:id/complete──► (runInTransaction)
   ├─ baseFare = mwComputeFare(...)               [02_pricing.pb.js]
   ├─ surcharge = deterministic hash(rideId)
   ├─ drivers/{driver}.walletBalance += driverPayout
   ├─ wallet_transactions/{txId} (ledger entry)
   ├─ wallets/{driver}.balance/lowBalance updated
   ├─ drivers/{driver}: ridesCompleted++, commissionTier/Rate via
   │     mwResolveCommissionTier(ridesCompleted, ratingAverage, ...)
   ├─ users/{passenger}.loyaltyPoints += mwComputePointsAwarded(totalFare),
   │     loyaltyTier via mwResolveLoyaltyTier(points)
   └─ rides/{id}: status=completed, fare={...}, pointsAwarded
                              + ride_status_history row
```

`POST /api/michwar/rides/:id/rate` runs after `completed`, updates the
driver's `ratingAverage`/`ratingCount` (incremental average) and re-checks
Elite (tier2) eligibility via the same `mwResolveCommissionTier`.

## 5. Geohash matching (`GeohashUtil` / `01_geohash.pb.js`)

Both the Dart client (`lib/core/utils/geohash_util.dart`,
used by `ride_engine/services`) and the PocketBase hook
(`pocketbase/pb_hooks/01_geohash.pb.js`) implement the **same** geohash
algorithm so that:

- Drivers periodically write `drivers/{id}.locationLat/locationLng/
  locationGeohash` (precision 7), plus `locationHeading`/`locationSpeed`/
  `locationUpdatedAt`. Polling cadence adapts via `GpsActivityState` (idle /
  onlineWaiting / activeTrip) to balance battery vs. freshness.
- On ride creation, the hook computes the geohash cell precision matching the
  current search radius, enumerates neighboring cells
  (`mwNeighborsForRadius`), and queries `drivers` whose `locationGeohash`
  falls in those cells via `$app.findRecordsByFilter()`.
- `mwDistanceKm` (Haversine) ranks candidates; `mwBearingDeg` powers the
  "Heading Home" bonus — if a driver's bearing toward their saved home
  destination is within `headingHomeBearingTolerance` of the bearing to the
  ride's drop-off, their effective distance is reduced, prioritizing them
  for a "last ride home".

## 6. Pricing & financial integrity

`pocketbase/pb_hooks/02_pricing.pb.js` is the **only** place fare/commission/
loyalty numbers are computed, and it is only ever invoked from inside
`$app.runInTransaction()` in the `/complete` and `/rate` routes. The Dart
`PricingService` (`lib/features/ride_engine/services/pricing_service.dart`)
implements the identical formulas **for client-side estimates only** (shown
before a ride is requested) — these numbers are explicitly never billed;
`rides/{id}.fare` written by `/complete` is authoritative.

The `rides` collection's API rules enforce this: clients can `create` a ride
(status `searching`) but the `update`/`delete` rules are `null` — every
transition (`accepted`, `arrived`, `ongoing`, `cancelled_*`, `completed`,
`fare`, `rating`) goes through a `pb_hooks` route running with full `$app`
(superuser) access.

## 7. Offline handling

`core/services/connectivity_service.dart` exposes `isOnlineProvider`.
`OfflineSyncService` (passenger/driver features) caches the active ride and
pending location pings in Hive when offline and replays them on
reconnection — surfaced in the UI as a "Reconnecting..." banner rather than
a hard error. The PocketBase Dart SDK persists `authStore` via
`shared_preferences` and auto-reconnects realtime subscriptions on network
recovery.

## 8. Safety features

- **In-app SOS** (`SosButton` widget, used on both active-ride screens):
  calls `POST /api/michwar/sos`, which records a `sos_alerts` record with
  ride context and the reporter's location, and best-effort copies the
  user's `sosContacts` into `notifiedContacts` for follow-up.
- **Live Trip Sharing**: `POST /api/michwar/rides/:id/share` mints a 6-hour
  token as a `live_shares/{id}` record (publicly readable while
  `@now < expiresAt` via the collection's `view` API rule — no auth required)
  and returns a shareable URL via `share_plus`. A minimal static page or the
  PocketBase Admin UI can read `GET /api/collections/live_shares/records/:id`
  and follow the `ride` relation to display live status.
- **SOS contacts**: up to 3 emergency contacts managed in
  `features/shared/presentation/screens/sos_contacts_screen.dart`, stored on
  `users/{id}.sosContacts`.

## 9. Demand heatmap

`POST /api/michwar/heatmap/ping` (called by the passenger app on every ride
request) atomically upserts `heatmap_cells/{geohash6}` inside
`$app.runInTransaction()` — incrementing `count` for an existing cell or
creating a new one. The `heatmap_cells` collection's `create`/`update` API
rules are hook-only (no direct client writes), making the increment
tamper-proof. `heatmapStream()` (realtime subscribe) feeds a `GoogleMap`
heatmap/circle overlay on the driver home screen
(`AppColors.heatmapGradient`).

## 10. Authentication & roles

Email + password via PocketBase's built-in `users` auth collection
(`passwordAuth`, `identityFields: ["email"]`) — see
`lib/core/services/auth_service.dart` for `signUp`/`signIn`/`signOut`/
`authStateChanges`/`switchRole`. `phoneNumber` is a plain profile field, no
longer used for sign-in.

Role switching (`passenger ↔ driver`) goes through `POST /api/michwar/role`,
a hook route that creates/links the `drivers` record and updates
`users.role` — both fields are otherwise protected from direct client writes
by `10_users.pb.js`/`11_drivers.pb.js`.

## 11. Driver verification

`document_upload_screen.dart` uploads each required document (see
`AppConstants.requiredDriverDocuments`) as a multipart file to
`drivers.documents` via `driver_document_service.dart`, and records
`{filename, status: 'pending', uploadedAt}` in `drivers.documentsMeta`. Once
every required document type has an entry, `11_drivers.pb.js` flips
`verificationStatus` from `pending` to `under_review`. An admin (via the
PocketBase Admin UI) then reviews documents and sets `verificationStatus` to
`approved`/`rejected`, which the router redirect uses to unlock the driver
home screen.

## 12. Notifications

`lib/core/services/notification_service.dart` is now a no-op stub. FCM push
notifications are not used — the app relies on PocketBase realtime
subscriptions (SSE) for live updates while foregrounded/backgrounded within
OS limits. `users.fcmTokens` remains as an unused placeholder field for a
future push provider, should one be added later.

## 13. Backend directory structure

```
pocketbase/
├── pocketbase                 # server binary (download per-platform, see DEPLOYMENT.md)
├── pb_data/                    # SQLite DB + uploaded files (gitignored, created at runtime)
├── pb_migrations/              # collection schema + API rules, applied on first run
│   ├── 1700000001_users.js
│   ├── 1700000002_drivers.js
│   ├── 1700000003_rides.js
│   ├── 1700000004_ride_status_history.js
│   ├── 1700000005_wallets.js
│   ├── 1700000006_wallet_transactions.js
│   ├── 1700000007_live_shares.js
│   ├── 1700000008_sos_alerts.js
│   └── 1700000009_heatmap_cells.js
├── pb_hooks/                    # business logic (JSVM)
│   ├── 00_constants.pb.js
│   ├── 01_geohash.pb.js
│   ├── 02_pricing.pb.js
│   ├── 10_users.pb.js
│   ├── 11_drivers.pb.js
│   ├── 12_rides.pb.js
│   ├── 13_wallet.pb.js
│   ├── 14_sos.pb.js
│   └── 15_heatmap.pb.js
└── MIGRATION_PLAN.md            # Firebase → PocketBase mapping reference
```

## 14. Legacy Firebase artifacts (unused)

The repository still contains a handful of files from the original Firebase
build that are no longer referenced by the app and can be deleted manually:
`.firebaserc`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`,
`storage.rules`, `functions/`, `lib/firebase_options.dart`, and
`lib/core/constants/firestore_paths.dart`. The two `lib/` files have already
been emptied to deprecation stubs so they don't affect the Flutter build.
