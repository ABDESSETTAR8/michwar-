# MICHWAR — Deployment Guide

This app ships configured to run against a **self-hosted PocketBase**
server. This guide covers running it locally for development, on your LAN
for testing on a real phone, and on a VPS/cloud host for production.

## 0. Prerequisites

- Flutter SDK (3.x) and Dart SDK (>=3.3.0)
- The [PocketBase](https://pocketbase.io/docs/) binary for your platform —
  a single executable, no other dependencies
- (Production) a small VM/VPS (PocketBase is lightweight — 1 vCPU / 512MB RAM
  is enough for moderate traffic) or a PaaS that supports persistent disks
  (Fly.io, Railway, a Docker host, etc.)

## 1. Run locally (no credentials needed)

```bash
# Backend
cd pocketbase
./pocketbase serve
# Admin UI: http://127.0.0.1:8090/_/  — create your admin account on first visit
# API:      http://127.0.0.1:8090/api/

# In a second terminal
flutter pub get
flutter run
```

- On first launch, PocketBase applies every migration in `pb_migrations/`
  (creates the `users`, `drivers`, `rides`, `ride_status_history`, `wallets`,
  `wallet_transactions`, `live_shares`, `sos_alerts`, `heatmap_cells`
  collections with their fields, indexes, and API rules) and loads every hook
  in `pb_hooks/` (`*.pb.js`).
- Data and uploaded files are stored in `pocketbase/pb_data/` (created on
  first run, gitignored).
- Android emulator note: `lib/core/services/pocketbase_service.dart` defaults
  to `http://10.0.2.2:8090`, which the Android emulator maps to your host
  machine's `localhost`.
- To seed initial data (e.g. an "Elite" driver, a wallet with balance), use
  the Admin UI's collection browser to add/edit records directly — see
  `SCHEMA.md` for field shapes. New driver records automatically get the 500
  DZD welcome credit via `pb_hooks/11_drivers.pb.js`.

## 2. Run on your LAN (testing on a real phone)

1. Start the server bound to all interfaces:
   ```bash
   ./pocketbase serve --http=0.0.0.0:8090
   ```
2. Find your machine's LAN IP (e.g. `192.168.1.50`).
3. Point the app at it:
   ```bash
   flutter run --dart-define=POCKETBASE_URL=http://192.168.1.50:8090
   ```
4. Make sure your firewall allows inbound connections on port 8090.

## 3. Production deployment

PocketBase is a single statically-linked binary plus a data directory —
deployment is just "run the binary, persist `pb_data/`, put TLS in front of
it."

### Option A — VPS (systemd)

1. Copy `pocketbase/` (binary + `pb_migrations/` + `pb_hooks/`) to the server.
2. Create a systemd unit, e.g. `/etc/systemd/system/michwar-pb.service`:
   ```ini
   [Unit]
   Description=MICHWAR PocketBase
   After=network.target

   [Service]
   Type=simple
   WorkingDirectory=/opt/michwar/pocketbase
   ExecStart=/opt/michwar/pocketbase/pocketbase serve --http=127.0.0.1:8090
   Restart=always

   [Install]
   WantedBy=multi-user.target
   ```
3. `systemctl enable --now michwar-pb`.
4. Put a reverse proxy (Caddy, nginx, or Traefik) in front for TLS, e.g.
   Caddy:
   ```
   api.michwar.example {
       reverse_proxy 127.0.0.1:8090
   }
   ```
5. Back up `pb_data/` regularly (it contains the SQLite database and all
   uploaded driver documents/avatars).

### Option B — Docker

`pocketbase/Dockerfile` (already in the repo) downloads the PocketBase
binary at build time and bundles `pb_migrations/` + `pb_hooks/`:

```bash
cd pocketbase
docker build -t michwar-pb .
docker run -p 8090:8090 -v pb_data:/pb/pb_data michwar-pb
```

Mount a volume at `/pb/pb_data` for persistence. Works as-is on Fly.io,
Railway, Render, or any container host that supports persistent volumes.

### Option C — Fly.io (free, recommended for "anyone can download the APK")

Fly.io gives you a public HTTPS URL (`https://<app>.fly.dev`) on its free
allowance — no domain or own server needed. `pocketbase/Dockerfile` and
`pocketbase/fly.toml` are already set up for this.

1. Install the Fly CLI and sign up/log in:
   ```bash
   # Windows (PowerShell)
   iwr https://fly.io/install.ps1 -useb | iex
   fly auth signup   # or: fly auth login
   ```
2. From the `pocketbase/` directory, launch the app (this reads
   `fly.toml`/`Dockerfile`; choose a globally-unique app name when prompted,
   or edit `app = "michwar-pb"` in `fly.toml` first):
   ```bash
   cd pocketbase
   fly launch --no-deploy
   ```
   Say **no** to adding a Postgres/Redis database — PocketBase uses its own
   embedded SQLite.
3. Create the persistent volume for `pb_data` (must match the `[[mounts]]`
   block in `fly.toml`, one per region you deploy to):
   ```bash
   fly volumes create pb_data --size 1 --region cdg
   ```
4. Deploy:
   ```bash
   fly deploy
   ```
5. Your server is now live at `https://<app-name>.fly.dev`. Open
   `https://<app-name>.fly.dev/_/` to create your admin (superuser) account.
6. Rebuild the Flutter app pointing at this URL — see Section 4 below.

Notes:
- `min_machines_running = 1` keeps PocketBase always-on (no cold-start delay
  for users, and realtime SSE subscriptions stay connected). This uses part
  of Fly's free monthly allowance (3 shared-cpu-1x VMs); a single 256MB VM
  fits comfortably within it for light traffic.
- Back up the `pb_data` volume periodically: `fly ssh console` then archive
  `/pb/pb_data`, or use `fly volumes snapshots`.
- To update backend logic later, edit `pb_hooks/*.pb.js` and re-run
  `fly deploy` from `pocketbase/` — no app rebuild needed.

## 4. Configure the Flutter app for production

```bash
flutter run --dart-define=POCKETBASE_URL=https://api.michwar.example
```

Or bake it into release builds (Section 6).

## 5. Google Maps API keys

The spec targets the Algerian market — restrict keys appropriately
(Android package name + SHA-1, iOS bundle ID, HTTP referrer for web).
Enable: **Maps SDK for Android/iOS**, **Directions API**, **Distance Matrix
API**, **Geocoding API**.

- `MapsService` (used for routing/ETA,
  `lib/features/ride_engine/services/maps_service.dart`) reads its key from
  `--dart-define=GOOGLE_MAPS_API_KEY=...`.
- For `google_maps_flutter` itself, add the **Android** key to
  `android/app/src/main/AndroidManifest.xml`
  (`com.google.android.geo.API_KEY` meta-data) and the **iOS** key to
  `ios/Runner/AppDelegate.swift` (`GMSServices.provideAPIKey(...)`) — neither
  file is pre-populated since they don't exist until you run `flutter create
  .` / open the platform projects, but both are standard
  `google_maps_flutter` setup steps.

No key is required to run the UI — `MapsService` degrades gracefully
(`hasApiKey == false`) and falls back to straight-line estimates.

## 6. Builds

```bash
flutter build apk --release \
  --dart-define=POCKETBASE_URL=https://api.michwar.example \
  --dart-define=GOOGLE_MAPS_API_KEY=...

flutter build ios --release \
  --dart-define=POCKETBASE_URL=https://api.michwar.example \
  --dart-define=GOOGLE_MAPS_API_KEY=...

flutter build web --release \
  --dart-define=POCKETBASE_URL=https://api.michwar.example \
  --dart-define=GOOGLE_MAPS_API_KEY=...
```

## 7. Custom backend routes (`pb_hooks/*.pb.js`)

All ride lifecycle, wallet, SOS, and heatmap logic lives in
`pocketbase/pb_hooks/*.pb.js`, loaded automatically by `pocketbase serve` —
no separate build/deploy step (unlike the old Cloud Functions). To change
business logic, edit the relevant `.pb.js` file and restart the server.
Routes exposed:

| Route | Purpose |
|---|---|
| `POST /api/michwar/role` | Switch between passenger/driver, create `drivers` record |
| `POST /api/michwar/rides/:id/accept` | Driver accepts a ride (race-safe transaction) |
| `POST /api/michwar/rides/:id/status` | arrived / ongoing / cancelled_* transitions |
| `POST /api/michwar/rides/:id/complete` | **Authoritative fare split**, wallet credit, ledger, loyalty |
| `POST /api/michwar/rides/:id/rate` | Passenger rates driver, updates `ratingAverage`/tier |
| `POST /api/michwar/rides/:id/share` | Mints a 6-hour public live-tracking token |
| `POST /api/michwar/sos` | Records SOS alert with location + ride context |
| `POST /api/michwar/wallet/topup` | Credits a driver's pre-paid wallet (placeholder — see Section 8) |
| `POST /api/michwar/heatmap/ping` | Atomically increments a demand heatmap cell |

## 8. Payments integration

`POST /api/michwar/wallet/topup` currently credits the wallet directly on
call — this is intentional for testability (no payment provider needed to
exercise the full app). For production, put this route behind a verified
webhook from your payment provider (CIB/EDAHABIA, etc.) instead of trusting
the client-supplied amount directly — e.g. have the payment provider call a
separate authenticated webhook route that then calls the same
`mwCreditWallet` logic.

## 9. Live Trip Sharing page

`POST /api/michwar/rides/:id/share` returns a URL of the form
`<LIVE_SHARE_BASE_URL>/{token}` (`LIVE_SHARE_BASE_URL` in
`pb_hooks/00_constants.pb.js`). The `live_shares` collection's `view` API
rule (`@now < expiresAt`) makes
`GET /api/collections/live_shares/records/{token}` publicly readable without
authentication. Host a minimal static page anywhere (PocketBase can serve
static files too, via `--publicDir`) that fetches that record, follows the
`ride` relation, and subscribes to the ride's realtime updates to show live
status/location.

## 10. Verification checklist before going live

- [ ] `POCKETBASE_URL` set to your production URL for release builds
- [ ] TLS configured in front of PocketBase (reverse proxy)
- [ ] `pb_data/` backed up on a schedule
- [ ] Admin account created with a strong password (Admin UI, first run)
- [ ] Real Google Maps keys restricted per-platform
- [ ] Payment provider webhook wired into `/api/michwar/wallet/topup` (Section 8)
- [ ] Live-share tracker page hosted (Section 9)
- [ ] Legacy Firebase files removed (`.firebaserc`, `firebase.json`,
      `firestore.rules`, `firestore.indexes.json`, `storage.rules`,
      `functions/`, `lib/firebase_options.dart`,
      `lib/core/constants/firestore_paths.dart`)
