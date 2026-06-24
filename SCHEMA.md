# MICHWAR — PocketBase Data Schema

This document is the single source of truth for the shape of every PocketBase
collection used by the app. It mirrors:

- The Dart models in `lib/core/models/`
- `lib/core/constants/pb_paths.dart` (`PbCollections` / `PbRoutes`)
- `pocketbase/pb_migrations/*.js` (collection schema + API rules)
- `pocketbase/pb_hooks/*.pb.js` (business-logic hook routes)

**Write ownership legend**

- **Client** — written directly by the Flutter app via the PocketBase SDK (subject to the collection's API rules)
- **Hook** — written only by a `pocketbase/pb_hooks/*.pb.js` route running with full `$app` access (collection `update`/`delete` rules are `null` — locked to hooks/admin)
- **Auto** — PocketBase-managed `id`/`created`/`updated` fields, present on every collection

---

## `users` (auth collection)

Profile + loyalty data for both passengers and drivers (a driver also has a
related `drivers` record via the `user` relation).

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | Auto | PocketBase record id (replaces Firebase Auth UID) |
| `email` / `password` | string | Client (signup) | PocketBase email+password auth (`passwordAuth`, `identityFields: ["email"]`) |
| `phoneNumber` | string | Client | Plain profile field — no longer used for login |
| `fullName` | string | Client | Editable in Settings |
| `role` | `'passenger' \| 'driver' \| 'admin'` | **Hook** (`10_users.pb.js` default; changes via `/api/michwar/role`) | Protected — a normal PATCH cannot change it |
| `roleSelected` | bool | Client | Set to `true` once the user picks a role |
| `avatar` | file (1, ≤5MB, png/jpeg/webp) | Client | |
| `loyaltyPoints` | number | **Hook** (`/api/michwar/rides/:id/complete`) | "MICHWAR Points" |
| `loyaltyTier` | `'standard' \| 'eco' \| 'premium'` | **Hook** | via `mwResolveLoyaltyTier` |
| `totalRidesCompleted` | number | **Hook** | |
| `savedPlaces` | json (array of `{label, lat, lng, address}`) | Client | Home/Work/Favorites |
| `sosContacts` | json (array of `{name, phone}`, max 3) | Client | Safety feature |
| `fcmTokens` | json (array<string>) | Client | Unused placeholder — no push provider configured (see `notification_service.dart`) |
| `created` / `updated` | date | Auto | |

**API rules**: `view` self or admin; `create` open (signup); `update` self only — `role`/`loyaltyPoints`/`loyaltyTier`/`totalRidesCompleted` are reverted to their original values for non-admin updates by the `onRecordUpdateRequest` hook in `10_users.pb.js`.

---

## `drivers`

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | Auto | |
| `user` | relation → `users` (1:1, unique, required, cascade delete) | **Hook** (`/api/michwar/role`) | Replaces shared-document-ID pattern |
| `vehicleMake` / `vehicleModel` / `vehiclePlate` / `vehicleColor` | text | Client | |
| `vehicleCategory` | `'standard' \| 'eco' \| 'premium'` | Client | |
| `verificationStatus` | `'pending' \| 'under_review' \| 'approved' \| 'rejected'` | **Hook** | `pending`→`under_review` auto-transition once all required docs are uploaded (`11_drivers.pb.js`); `approved`/`rejected` are admin-only |
| `documents` | file (≤6, ≤10MB, png/jpeg) | Client (multipart upload) | One file per document type, named `{type}{ext}` |
| `documentsMeta` | json (`{[type]: {filename, status, uploadedAt}}`) | Client (status `pending`) / Admin (`approved`/`rejected`) | Drives `DocumentUploadScreen` |
| `commissionTier` | `'tier1' \| 'tier2'` | **Hook** | `tier2` = "Elite" |
| `commissionRate` | number | **Hook** | 0.15 (tier1) or 0.07 (tier2) |
| `driverShareRate` | number | **Hook** | 0.85 or 0.93 |
| `ridesCompleted` | number | **Hook** (`/complete`) | Elite requires ≥100 |
| `ratingAverage` | number | **Hook** (`/rate`) | Elite requires ≥4.0; default 5.0 |
| `ratingCount` | number | **Hook** (`/rate`) | |
| `isOnline` | bool | Client | Driver's online/offline toggle |
| `isOnTrip` | bool | **Hook** | Set by `/accept`, cleared by `/status` (on cancel) and `/complete` |
| `headingHomeEnabled` / `headingHomeDestLat` / `headingHomeDestLng` / `headingHomeBearingTolerance` | bool / number / number / number | Client | "Heading Home" matching bonus |
| `locationLat` / `locationLng` / `locationGeohash` / `locationHeading` / `locationSpeed` / `locationUpdatedAt` | number / number / text(12) / number / number / date | Client | Adaptive GPS ping; `locationGeohash` precision 7 |
| `walletBalance` | number (DZD) | **Hook** (`/api/michwar/wallet/topup`, `/complete`) | Pre-paid wallet; low-balance threshold 200 DZD |
| `created` / `updated` | date | Auto | |

**Indexes**: unique on `user`; `(isOnline, isOnTrip, locationGeohash)` for geohash matching.

**API rules**: `list`/`view` any authenticated user; `create` self (`/api/michwar/role` flow); `update` self or admin — `MW_DRIVER_PROTECTED_FIELDS` (`verificationStatus`, `commissionTier`, `commissionRate`, `driverShareRate`, `ridesCompleted`, `ratingAverage`, `ratingCount`, `isOnTrip`, `walletBalance`) are reverted to their original values for non-admin updates by `11_drivers.pb.js`.

---

## `rides`

Created directly by the passenger's app (`status: 'searching'`); every other
field/transition is written exclusively by `pocketbase/pb_hooks/12_rides.pb.js`.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | Auto | |
| `passenger` | relation → `users` (required) | **Hook** (set from `e.auth.id` on create) | |
| `driver` | relation → `users` | **Hook** (`/accept`) | |
| `status` | select (`searching`, `accepted`, `arrived`, `ongoing`, `completed`, `cancelled_by_passenger`, `cancelled_by_driver`, `no_drivers_found`) | Client (create=`searching`) / **Hook** (rest) | See status machine below |
| `rideTier` | `'standard' \| 'eco' \| 'premium'` | Client (create) | Drives fare multiplier |
| `pickup` / `dropoff` | json (`{lat, lng, address?}`) | Client (create) | |
| `pickupGeohash` | text(12) | **Hook** (on create, from `pickup`) | precision 7 |
| `estimate` | json (`{distanceKm, durationMin, estimatedFare}`) | Client (create) | Client-side estimate only — **not** billed |
| `candidateDriverIds` | json (array<string>) | **Hook** (`onRecordAfterCreateSuccess` matching) | Geohash-matched, ≤10, sorted by distance |
| `actualDistanceKm` / `actualDurationMin` | number | **Hook** (`/complete`) | GPS-tracked by the driver app, sent to `/complete` |
| `fare` | json (`{baseFare, surchargeDzd, totalFare, commissionRate, commissionAmount, driverPayout, companyRevenue, transactionId}`) | **Hook** (`/complete`) | Authoritative — see "Fare model" below |
| `pointsAwarded` | number | **Hook** (`/complete`) | |
| `rating` | json (`{stars, comment?}`) | **Hook** (`/rate`) | Passenger → driver, one-time |
| `liveShareToken` / `liveShareExpiresAt` | text / date | **Hook** (`/share`) | `liveShareToken` = `live_shares` record id |
| `requestedAt`, `acceptedAt`, `arrivedAt`, `startedAt`, `completedAt`, `cancelledAt` | date | Client (`requestedAt`) / **Hook** (rest) | |
| `created` / `updated` | date | Auto | |

**Indexes**: `status`; `(passenger, status)`; `(driver, status)`; `pickupGeohash`.

**Ride status machine**:

```
searching ──(after-create-success matching hook finds drivers)──► searching (candidateDriverIds set)
searching ──(no drivers at max radius)──► no_drivers_found
searching ──(/accept)──► accepted
accepted  ──(/status 'arrived')──► arrived
accepted  ──(/status 'cancelled_by_driver')──► cancelled_by_driver
{searching,accepted,arrived} ──(/status 'cancelled_by_passenger')──► cancelled_by_passenger
arrived   ──(/status 'ongoing')──► ongoing
arrived   ──(/status 'cancelled_by_driver')──► cancelled_by_driver
ongoing   ──(/complete)──► completed
```

**API rules**: `list`/`view` participants (passenger/driver) or admin; `create` passenger only, `status` must be `searching` (`MW_RIDE_PROTECTED_FIELDS` reverted for non-admin updates, but `update` rule is `null` anyway — all transitions go through hook routes); `update`/`delete` hook-only.

### `ride_status_history` — Hook only

Append-only audit trail. One record per transition, written alongside
`/accept`, `/status`, and `/complete`.

| Field | Type | Notes |
|---|---|---|
| `id` | string | Auto |
| `ride` | relation → `rides` (required, cascade delete) | |
| `status` | text (required) | |
| `actor` | relation → `users` | The user who triggered the transition |
| `created` / `updated` | date | Auto |

**Indexes**: `ride`. **API rules**: `list`/`view` ride participants or admin; `create`/`update`/`delete` hook-only.

---

## `wallets`

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | Auto | |
| `driver` | relation → `users` (1:1, unique, required, cascade delete) | **Hook** | |
| `balance` | number (DZD, required) | **Hook** | |
| `lowBalance` | bool | **Hook** | `balance <= 200` |
| `lastTopUpAt` / `lastDeductionAt` | date | **Hook** | |
| `created` / `updated` | date | Auto | |

**Indexes**: unique on `driver`. **API rules**: `list`/`view` owner driver or admin; `create`/`update`/`delete` hook-only.

### `wallet_transactions` — Hook only

Ledger of every wallet movement (`TransactionModel`):

| Field | Type | Notes |
|---|---|---|
| `id` | string | = `transactionId` |
| `ride` | relation → `rides` (optional) | empty for top-ups |
| `driver` | relation → `users` | |
| `passenger` | relation → `users` (optional) | |
| `type` | `'ride_earning' \| 'wallet_top_up' \| 'wallet_deduction' \| 'adjustment'` | |
| `baseFare` | number | "Fare_Revenue" pool for the ride |
| `surchargeRevenue` | number | 100% company |
| `commissionRate` | number | Rate applied to `baseFare` |
| `commissionDeducted` | number | = `baseFare * commissionRate` |
| `netPayoutToDriver` | number | = `baseFare - commissionDeducted` |
| `companyRevenue` | number | = `commissionDeducted + surchargeRevenue` |
| `walletBalanceAfter` | number | Running balance snapshot |
| `created` | date | Auto — replaces `createdAt` |

**API rules**: `list`/`view` owner driver (`driver = @request.auth.id`) or admin; `create`/`update`/`delete` hook-only.

---

## `sos_alerts` — Hook only

Written by `POST /api/michwar/sos` when a passenger or driver triggers in-app SOS.

| Field | Type | Notes |
|---|---|---|
| `id` | string | Auto |
| `ride` | relation → `rides` (required) | |
| `reportedBy` | `'passenger' \| 'driver'` (required) | |
| `user` | relation → `users` (required) | The reporting user |
| `locationLat` / `locationLng` | number | |
| `rideStatus` | text | Snapshot of the ride's status at alert time |
| `passenger` / `driver` | relation → `users` | Snapshot of the ride's participants |
| `status` | text | `'open'` (admin triages externally) |
| `notifiedContacts` | json (array<string>) | Phone numbers from `users.sosContacts`, best-effort |
| `created` / `updated` | date | Auto |

**API rules**: `list`/`view` the reporting `user` or admin; `create`/`update`/`delete` hook-only.

---

## `live_shares` — Hook only

Publicly (unauthenticated) readable while `expiresAt > now`. Written only by
`POST /api/michwar/rides/:id/share`. The record `id` itself is the share
token (`LIVE_SHARE_BASE_URL/{id}`), valid 6 hours (`LIVE_SHARE_LINK_VALIDITY_MS`).

| Field | Type | Notes |
|---|---|---|
| `id` | string | = share token |
| `ride` | relation → `rides` (required) | |
| `createdBy` | relation → `users` (required) | |
| `expiresAt` | date (required) | |
| `created` / `updated` | date | Auto |

**API rules**: `view` rule `@now < expiresAt` (public, no auth required); `list`/`create`/`update`/`delete` are `null` (hook-only / disabled).

---

## `heatmap_cells`

Demand heatmap for the driver app. Updated atomically via
`POST /api/michwar/heatmap/ping`, called by the passenger app on every ride
request.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `id` | string | Auto | |
| `geohash` | text(12, required, unique) | **Hook** | precision 6, ≈1.2 km cells |
| `lat` / `lng` | number (required) | **Hook** | cell center (first ping) |
| `count` | number (required) | **Hook** | incremented per ping |
| `updatedAt` | date | **Hook** | |
| `created` / `updated` | date | Auto | |

**Indexes**: unique on `geohash`; `updatedAt`. **API rules**: `list`/`view` any authenticated user; `create`/`update`/`delete` hook-only (direct client writes disabled — replaces the old client-side `FieldValue.increment(1)`).

---

## Dropped / not carried over

The original Firestore schema's top-level `transactions` and `ratings`
collections were unused placeholders and were **not** ported — wallet ledger
entries live in `wallet_transactions` (above) and ratings are embedded in
`rides.rating`.

---

## Fare model (Section 6 — authoritative, computed in `POST /api/michwar/rides/:id/complete`, `pocketbase/pb_hooks/02_pricing.pb.js`)

```
baseFare      = round5( max(MINIMUM_FARE_DZD,
                  (BASE_FARE_FLAG_DZD
                   + actualDistanceKm * FARE_PER_KM_DZD
                   + actualDurationMin * FARE_PER_MINUTE_DZD)
                  * RIDE_TIER_MULTIPLIERS[rideTier]) )

surchargeDzd  = deterministic hash(rideId) in [1, 4]   // 100% company revenue

commissionAmount = round1( baseFare * commissionRate )
driverPayout      = baseFare - commissionAmount
companyRevenue    = commissionAmount + surchargeDzd
totalFare         = baseFare + surchargeDzd
```

**Commission tiers** (`mwResolveCommissionTier`):

| Tier | Trigger | commissionRate | driverShareRate |
|---|---|---|---|
| `tier1` | default | 15% | 85% |
| `tier2` ("Elite") | `ridesCompleted >= 100 && ratingAverage >= 4.0` (one-way promotion) | 7% | 93% |

**MICHWAR Points** (`mwComputePointsAwarded`): `floor(totalFare / 100) * 2`.
**Loyalty tiers** (`mwResolveLoyaltyTier`): `points >= 200` → `premium`,
`points >= 50` → `eco`, else `standard`.

All constants above live in `pocketbase/pb_hooks/00_constants.pb.js`
(`MICHWAR` object), mirrored client-side (for estimates only) in
`lib/core/constants/app_constants.dart`.

---

## Indexes

Defined directly in each `pocketbase/pb_migrations/*.js` file (SQLite `CREATE
INDEX` statements run as part of the migration), replacing
`firestore.indexes.json`:

1. `rides (status)`, `rides (passenger, status)`, `rides (driver, status)`, `rides (pickupGeohash)`.
2. `drivers (user)` unique, `drivers (isOnline, isOnTrip, locationGeohash)` — geohash driver matching.
3. `ride_status_history (ride)`.
4. `wallets (driver)` unique.
5. `heatmap_cells (geohash)` unique, `heatmap_cells (updatedAt)`.
