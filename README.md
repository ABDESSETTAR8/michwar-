# MICHWAR — Ride-Hailing Platform (Algeria)

A full-stack, feature-first Flutter app + self-hosted **PocketBase** backend
implementing the MICHWAR ride-hailing spec: passenger booking, driver
matching via geohash, tiered commission/wallet economics, MICHWAR Points
loyalty, live trip sharing, in-app SOS, demand heatmaps, and "Heading Home"
driver matching.

> **Status:** fully scaffolded and runnable against a **local PocketBase
> server** out of the box — no Firebase project, API keys, or cloud account
> required to explore every screen and flow. See [DEPLOYMENT.md](DEPLOYMENT.md)
> for running the server on a real device/VPS, and [SCHEMA.md](SCHEMA.md) /
> [ARCHITECTURE.md](ARCHITECTURE.md) for the data model and code structure.

## Tech stack

| Layer | Choice |
|---|---|
| App | Flutter 3.x, feature-first under `lib/features/` |
| State | Riverpod (`flutter_riverpod`) |
| Navigation | `go_router` |
| Backend | [PocketBase](https://pocketbase.io) (single Go binary + SQLite): auth, collections/realtime, file storage, JSVM hooks (`pb_hooks/*.pb.js`) for business logic |
| Maps | `google_maps_flutter`, Google Directions/Distance Matrix (via `MapsService`) |
| Offline | `hive`/`hive_flutter` + `connectivity_plus` (`OfflineSyncService`) |
| Matching | Geohash proximity (mirrored in Dart `GeohashUtil` and `pocketbase/pb_hooks/01_geohash.pb.js`) |

## Quick start (local PocketBase — no credentials needed)

1. **Download the PocketBase binary** for your platform from
   [pocketbase.io/docs](https://pocketbase.io/docs/) and place it at
   `pocketbase/pocketbase` (or `pocketbase/pocketbase.exe` on Windows).

2. **Start the server** from the `pocketbase/` directory — migrations
   (`pb_migrations/*.js`) run automatically on first launch, creating every
   collection and API rule:
   ```bash
   cd pocketbase
   ./pocketbase serve
   ```
   This starts the API at `http://127.0.0.1:8090` and the Admin UI at
   `http://127.0.0.1:8090/_/`. On first run, create an admin (superuser)
   account when prompted by the Admin UI.

3. **Run the Flutter app**. By default it points at
   `http://10.0.2.2:8090` (the host machine, from the Android emulator's
   point of view) — see `lib/core/services/pocketbase_service.dart`:
   ```bash
   flutter pub get
   flutter run
   ```
   For a physical device or a server on another host, override the URL:
   ```bash
   flutter run --dart-define=POCKETBASE_URL=http://<your-lan-ip>:8090
   ```

4. **Sign up** with an email + password (no phone/OTP — see
   [MIGRATION_PLAN.md](pocketbase/MIGRATION_PLAN.md)), pick a role
   (passenger/driver), create a ride, and use a second device/emulator signed
   in as a driver to accept it. New drivers automatically receive a 500 DZD
   wallet welcome credit (`pb_hooks/11_drivers.pb.js`). Watch records update
   live in the Admin UI at `http://127.0.0.1:8090/_/`.

No Google Maps API key is required to run the UI — `MapsService` degrades
gracefully (`hasApiKey == false`) and falls back to straight-line
estimates when no key is configured. Add one via
`flutter run --dart-define=GOOGLE_MAPS_API_KEY=...` for real routing.

## Project structure

```
lib/
  core/             # theme, models, constants, routing, shared services
    services/pocketbase_service.dart  # PocketBase client + base URL config
  features/
    authentication/ # email+password auth, role selection, driver onboarding/verification
    ride_engine/     # RideRepository, GeohashUtil, PricingService, MapsService
    passenger/       # booking flow, ride tracking, history, ratings
    driver/          # online toggle, incoming requests, active ride, earnings, wallet
    shared/          # settings, SOS contacts, support/FAQ
pocketbase/
  pocketbase            # server binary (download separately, see DEPLOYMENT.md)
  pb_migrations/         # collection schema + API rules (applied on first run)
  pb_hooks/               # business logic (JSVM)
    00_constants.pb.js     # mirrors lib/core/constants/app_constants.dart
    01_geohash.pb.js        # mirrors lib/core/utils/geohash_util.dart
    02_pricing.pb.js         # fare/commission/loyalty math (Section 6)
    10_users.pb.js, 11_drivers.pb.js  # profile defaults, field protection,
                                        # verification auto-transition, welcome credit
    12_rides.pb.js            # ride lifecycle: matching, accept/status/complete/rate/share
    13_wallet.pb.js            # wallet top-ups
    14_sos.pb.js                # in-app SOS alerts
    15_heatmap.pb.js             # demand heatmap pings
  MIGRATION_PLAN.md       # Firebase → PocketBase mapping reference
SCHEMA.md            # full PocketBase data model
ARCHITECTURE.md      # code architecture & data flow
DEPLOYMENT.md        # running the PocketBase server (local, LAN, VPS)
```

## Key business rules implemented

- **Tiered commission**: Tier 1 (15% company / 85% driver) by default;
  Tier 2 "Elite" (7% / 93%) once a driver reaches **≥100 completed rides**
  and **≥4.0 average rating** — one-way promotion, computed server-side in
  `pb_hooks/12_rides.pb.js` (`/complete` and `/rate` routes).
- **Platform surcharge**: 1–4 DZD per ride, 100% company revenue, deducted
  from the driver's pre-paid wallet alongside the commission.
- **Driver wallet**: low-balance threshold 200 DZD (drivers below this are
  excluded from matching and can't accept rides); 500 DZD welcome credit is
  granted automatically when a driver profile is created
  (`pb_hooks/11_drivers.pb.js`); top-ups via `POST /api/michwar/wallet/topup`.
- **MICHWAR Points**: 2 points per 100 DZD spent; 50 points unlocks the
  "eco" tier, 200 points unlocks "premium".
- **Geohash matching**: expanding-radius search (3 km → up to 10 km),
  excludes offline/on-trip drivers, with a "Heading Home" bearing-alignment
  priority bonus.
- **Server-side authority**: all fare math, commission splits, wallet
  balances, ratings, and status transitions are validated and written by
  `pocketbase/pb_hooks/*.pb.js` routes running with full database access —
  the client only ever reads the results (the `rides`, `drivers`, `wallets`,
  etc. collections have `update`/`delete` API rules locked to hooks/admin).

## Legacy Firebase files

The repo still contains a few unused files from the original Firebase build
(`.firebaserc`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`,
`storage.rules`, `functions/`, `lib/firebase_options.dart`,
`lib/core/constants/firestore_paths.dart`). None of these are referenced by
the Flutter app or build — the two `lib/` files have been replaced with
deprecation-stub comments, and the rest can be deleted manually.
