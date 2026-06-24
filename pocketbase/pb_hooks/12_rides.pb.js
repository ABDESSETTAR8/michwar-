/// <reference path="../pb_data/types.d.ts" />

// ---------------------------------------------------------------------------
// Ride lifecycle: create defaults, driver-matching, and the
// accept/status/complete/rate/share hook routes that replace the
// corresponding Cloud Functions callables.
// ---------------------------------------------------------------------------

// Fields a normal client must never set/overwrite directly on `rides`.
var MW_RIDE_PROTECTED_FIELDS = [
  "status", "driver", "candidateDriverIds", "fare", "rating", "pointsAwarded",
  "actualDistanceKm", "actualDurationMin", "acceptedAt", "arrivedAt",
  "startedAt", "completedAt", "cancelledAt", "liveShareToken", "liveShareExpiresAt",
];

onRecordCreateRequest((e) => {
  // Only the passenger may create their own ride request, in 'searching'.
  if (e.auth) {
    e.record.set("passenger", e.auth.id);
  }
  e.record.set("status", "searching");
  e.record.set("driver", "");
  e.record.set("candidateDriverIds", []);
  if (!e.record.get("requestedAt")) {
    e.record.set("requestedAt", new Date().toISOString());
  }

  var pickup = e.record.get("pickup");
  if (pickup && pickup.lat != null && pickup.lng != null) {
    e.record.set("pickupGeohash", mwGeohashEncode(pickup.lat, pickup.lng, MICHWAR.GEOHASH_PRECISION));
  }

  e.next();
}, "rides");

onRecordUpdateRequest((e) => {
  var isAdmin = e.auth && e.auth.get("role") === "admin";
  if (!isAdmin) {
    var original = $app.findRecordById("rides", e.record.id);
    for (var i = 0; i < MW_RIDE_PROTECTED_FIELDS.length; i++) {
      var field = MW_RIDE_PROTECTED_FIELDS[i];
      e.record.set(field, original.get(field));
    }
  }
  e.next();
}, "rides");

// ---------------------------------------------------------------------------
// Driver matching — replaces functions/src/triggers/onRideRequestCreated.ts
// ---------------------------------------------------------------------------

onRecordAfterCreateSuccess((e) => {
  try {
    mwMatchDriversForRide(e.record);
  } catch (err) {
    console.log("[rides matching] error for ride " + e.record.id + ": " + err);
  }
  e.next();
}, "rides");

function mwMatchDriversForRide(ride) {
  if (ride.get("status") !== "searching") return;

  var pickup = ride.get("pickup") || {};
  var dropoff = ride.get("dropoff") || {};
  if (pickup.lat == null || pickup.lng == null) {
    console.log("[rides matching] ride " + ride.id + " has no pickup location");
    return;
  }

  var candidates = [];
  var radiusKm = MICHWAR.DEFAULT_DRIVER_SEARCH_RADIUS_KM;

  while (candidates.length === 0 && radiusKm <= MICHWAR.MAX_DRIVER_SEARCH_RADIUS_KM) {
    candidates = mwFindCandidateDrivers(pickup.lat, pickup.lng, radiusKm, dropoff);
    if (candidates.length === 0) {
      radiusKm *= 2;
    }
  }

  var fresh = $app.findRecordById("rides", ride.id);
  // Another request may have already moved this ride out of 'searching'.
  if (fresh.get("status") !== "searching") return;

  if (candidates.length === 0) {
    fresh.set("status", "no_drivers_found");
    fresh.set("candidateDriverIds", []);
    $app.save(fresh);
    return;
  }

  candidates.sort(function (a, b) { return a.distanceKm - b.distanceKm; });
  var candidateIds = [];
  for (var i = 0; i < candidates.length && i < MICHWAR.MAX_CANDIDATE_DRIVERS; i++) {
    candidateIds.push(candidates[i].userId);
  }

  fresh.set("candidateDriverIds", candidateIds);
  $app.save(fresh);
}

function mwFindCandidateDrivers(lat, lng, radiusKm, dropoff) {
  var precision = MICHWAR.GEOHASH_PRECISION;
  for (var p = 1; p <= 9; p++) {
    if (mwCellSizeKm(p) >= radiusKm) precision = p;
  }

  var prefixes = mwNeighborsForRadius(lat, lng, radiusKm, precision);
  var seen = {};

  for (var i = 0; i < prefixes.length; i++) {
    var bounds = mwGeohashBounds(prefixes[i]);
    var records = [];
    try {
      records = $app.findRecordsByFilter(
        "drivers",
        "isOnline = true && isOnTrip = false && verificationStatus = 'approved' && walletBalance > {:threshold} && locationGeohash >= {:start} && locationGeohash < {:end}",
        "",
        50,
        0,
        {
          threshold: MICHWAR.WALLET_LOW_BALANCE_THRESHOLD_DZD,
          start: bounds.start,
          end: bounds.end,
        }
      );
    } catch (err) {
      records = [];
    }
    for (var j = 0; j < records.length; j++) {
      seen[records[j].id] = records[j];
    }
  }

  var candidates = [];
  for (var id in seen) {
    var driver = seen[id];
    var dLat = driver.get("locationLat");
    var dLng = driver.get("locationLng");
    if (dLat == null || dLng == null) continue;

    var dKm = mwDistanceKm(lat, lng, dLat, dLng);
    if (dKm > radiusKm) continue;

    var effectiveDistance = dKm;

    if (driver.get("headingHomeEnabled") && dropoff && dropoff.lat != null && dropoff.lng != null) {
      var destLat = driver.get("headingHomeDestLat");
      var destLng = driver.get("headingHomeDestLng");
      if (destLat != null && destLng != null) {
        var bearingToHome = mwBearingDeg(dLat, dLng, destLat, destLng);
        var bearingToDropoff = mwBearingDeg(dLat, dLng, dropoff.lat, dropoff.lng);
        var diff = Math.abs(((bearingToHome - bearingToDropoff + 540) % 360) - 180);
        var tolerance = driver.get("headingHomeBearingTolerance") || 30;
        if (diff <= tolerance) {
          effectiveDistance = Math.max(0, dKm - 1.0);
        }
      }
    }

    candidates.push({ userId: driver.get("user"), distanceKm: effectiveDistance });
  }

  return candidates;
}

// ---------------------------------------------------------------------------
// POST /api/michwar/rides/:id/accept — replaces callable/acceptRide.ts
// ---------------------------------------------------------------------------

routerAdd("POST", "/api/michwar/rides/{id}/accept", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var rideId = e.request.pathValue("id");

  $app.runInTransaction((txApp) => {
    var ride = txApp.findRecordById("rides", rideId);
    var driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: e.auth.id });

    if (ride.get("status") !== "searching" || ride.get("driver")) {
      throw new BadRequestError("This ride has already been accepted by another driver.");
    }
    if (driver.get("isOnTrip")) {
      throw new BadRequestError("You already have an active trip.");
    }
    if ((driver.get("walletBalance") || 0) <= MICHWAR.WALLET_LOW_BALANCE_THRESHOLD_DZD) {
      throw new BadRequestError("Your wallet balance is too low to accept new rides.");
    }

    ride.set("driver", e.auth.id);
    ride.set("status", "accepted");
    ride.set("acceptedAt", new Date().toISOString());
    txApp.save(ride);

    driver.set("isOnTrip", true);
    txApp.save(driver);

    var history = new Record(txApp.findCollectionByNameOrId("ride_status_history"));
    history.set("ride", rideId);
    history.set("status", "accepted");
    history.set("actor", e.auth.id);
    txApp.save(history);
  });

  return e.json(200, { ok: true });
}, $apis.requireAuth());

// ---------------------------------------------------------------------------
// POST /api/michwar/rides/:id/status — replaces callable/updateRideStatus.ts
// ---------------------------------------------------------------------------

var MW_ALLOWED_TRANSITIONS = {
  arrived: { from: ["accepted"], actor: "driver" },
  ongoing: { from: ["arrived"], actor: "driver" },
  cancelled_by_driver: { from: ["accepted", "arrived"], actor: "driver" },
  cancelled_by_passenger: { from: ["searching", "accepted", "arrived"], actor: "passenger" },
};

var MW_STATUS_TIMESTAMP_FIELD = { arrived: "arrivedAt", ongoing: "startedAt" };

routerAdd("POST", "/api/michwar/rides/{id}/status", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var rideId = e.request.pathValue("id");
  var data = new DynamicModel({ status: "" });
  e.bindBody(data);

  var transition = MW_ALLOWED_TRANSITIONS[data.status];
  if (!transition) throw new BadRequestError("Unsupported status transition: " + data.status);

  $app.runInTransaction((txApp) => {
    var ride = txApp.findRecordById("rides", rideId);
    var currentStatus = ride.get("status");

    if (transition.from.indexOf(currentStatus) === -1) {
      throw new BadRequestError("Cannot move ride from '" + currentStatus + "' to '" + data.status + "'.");
    }

    var isDriver = ride.get("driver") === e.auth.id;
    var isPassenger = ride.get("passenger") === e.auth.id;

    if (transition.actor === "driver" && !isDriver) {
      throw new ForbiddenError("Only the assigned driver can perform this action.");
    }
    if (transition.actor === "passenger" && !isPassenger) {
      throw new ForbiddenError("Only the passenger can perform this action.");
    }

    ride.set("status", data.status);

    var tsField = MW_STATUS_TIMESTAMP_FIELD[data.status];
    if (tsField) ride.set(tsField, new Date().toISOString());

    var isCancel = data.status === "cancelled_by_driver" || data.status === "cancelled_by_passenger";
    if (isCancel) ride.set("cancelledAt", new Date().toISOString());

    txApp.save(ride);

    var history = new Record(txApp.findCollectionByNameOrId("ride_status_history"));
    history.set("ride", rideId);
    history.set("status", data.status);
    history.set("actor", e.auth.id);
    txApp.save(history);

    // Free up the driver if a ride is cancelled after they were assigned.
    if (isCancel && ride.get("driver")) {
      try {
        var driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: ride.get("driver") });
        driver.set("isOnTrip", false);
        txApp.save(driver);
      } catch (err) {
        // driver record missing — nothing to free up
      }
    }
  });

  return e.json(200, { ok: true });
}, $apis.requireAuth());

// ---------------------------------------------------------------------------
// POST /api/michwar/rides/:id/complete — replaces callable/completeRide.ts
// ---------------------------------------------------------------------------

routerAdd("POST", "/api/michwar/rides/{id}/complete", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var rideId = e.request.pathValue("id");
  var data = new DynamicModel({ actualDistanceKm: 0, actualDurationMin: 0 });
  e.bindBody(data);

  if (data.actualDistanceKm < 0 || data.actualDurationMin < 0) {
    throw new BadRequestError("Distance and duration must be non-negative.");
  }

  var result = null;

  $app.runInTransaction((txApp) => {
    var ride = txApp.findRecordById("rides", rideId);

    if (ride.get("status") !== "ongoing") {
      throw new BadRequestError("Ride must be 'ongoing' to complete (currently '" + ride.get("status") + "').");
    }
    if (ride.get("driver") !== e.auth.id) {
      throw new ForbiddenError("Only the assigned driver can complete this ride.");
    }

    var driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: e.auth.id });

    var wallet = null;
    try {
      wallet = txApp.findFirstRecordByFilter("wallets", "driver = {:uid}", { uid: e.auth.id });
    } catch (err) {
      wallet = null;
    }

    var passenger = null;
    try {
      passenger = txApp.findRecordById("users", ride.get("passenger"));
    } catch (err) {
      passenger = null;
    }

    var baseFare = mwComputeBaseFare(data.actualDistanceKm, data.actualDurationMin, ride.get("rideTier") || "standard");
    var surchargeDzd = mwComputeSurcharge(rideId);
    var commissionRate = driver.get("commissionRate") || MICHWAR.TIER1_COMMISSION_RATE;
    var breakdown = mwComputeFareBreakdown(baseFare, surchargeDzd, commissionRate);

    var currentBalance = wallet ? (wallet.get("balance") || 0) : (driver.get("walletBalance") || 0);
    var newBalance = currentBalance - breakdown.companyRevenue;
    var lowBalance = newBalance <= MICHWAR.WALLET_LOW_BALANCE_THRESHOLD_DZD;

    var ridesCompleted = (driver.get("ridesCompleted") || 0) + 1;
    var tier = mwResolveCommissionTier(ridesCompleted, driver.get("ratingAverage") || 5.0, driver.get("commissionTier") || "tier1");

    driver.set("walletBalance", newBalance);
    driver.set("ridesCompleted", ridesCompleted);
    driver.set("commissionTier", tier.tier);
    driver.set("commissionRate", tier.commissionRate);
    driver.set("driverShareRate", tier.driverShareRate);
    driver.set("isOnTrip", false);
    txApp.save(driver);

    if (!wallet) {
      wallet = new Record(txApp.findCollectionByNameOrId("wallets"));
      wallet.set("driver", e.auth.id);
    }
    wallet.set("balance", newBalance);
    wallet.set("lowBalance", lowBalance);
    wallet.set("lastDeductionAt", new Date().toISOString());
    txApp.save(wallet);

    var ledger = new Record(txApp.findCollectionByNameOrId("wallet_transactions"));
    ledger.set("driver", e.auth.id);
    ledger.set("ride", rideId);
    ledger.set("passenger", ride.get("passenger"));
    ledger.set("type", "ride_earning");
    ledger.set("baseFare", breakdown.baseFare);
    ledger.set("surchargeRevenue", breakdown.surchargeDzd);
    ledger.set("commissionRate", breakdown.commissionRate);
    ledger.set("commissionDeducted", breakdown.commissionAmount);
    ledger.set("netPayoutToDriver", breakdown.driverPayout);
    ledger.set("companyRevenue", breakdown.companyRevenue);
    ledger.set("walletBalanceAfter", newBalance);
    txApp.save(ledger);

    var pointsAwarded = mwComputePointsAwarded(breakdown.totalFare);
    if (passenger) {
      var newPoints = (passenger.get("loyaltyPoints") || 0) + pointsAwarded;
      var newTotalRides = (passenger.get("totalRidesCompleted") || 0) + 1;
      passenger.set("loyaltyPoints", newPoints);
      passenger.set("totalRidesCompleted", newTotalRides);
      passenger.set("loyaltyTier", mwResolveLoyaltyTier(newPoints));
      txApp.save(passenger);
    }

    ride.set("status", "completed");
    ride.set("actualDistanceKm", data.actualDistanceKm);
    ride.set("actualDurationMin", data.actualDurationMin);
    ride.set("pointsAwarded", pointsAwarded);
    ride.set("fare", {
      baseFare: breakdown.baseFare,
      surchargeDzd: breakdown.surchargeDzd,
      totalFare: breakdown.totalFare,
      commissionRate: breakdown.commissionRate,
      commissionAmount: breakdown.commissionAmount,
      driverPayout: breakdown.driverPayout,
      companyRevenue: breakdown.companyRevenue,
      transactionId: ledger.id,
    });
    ride.set("completedAt", new Date().toISOString());
    txApp.save(ride);

    var history = new Record(txApp.findCollectionByNameOrId("ride_status_history"));
    history.set("ride", rideId);
    history.set("status", "completed");
    history.set("actor", e.auth.id);
    txApp.save(history);

    result = {
      baseFare: breakdown.baseFare,
      surchargeDzd: breakdown.surchargeDzd,
      totalFare: breakdown.totalFare,
      commissionRate: breakdown.commissionRate,
      commissionAmount: breakdown.commissionAmount,
      driverPayout: breakdown.driverPayout,
      companyRevenue: breakdown.companyRevenue,
      transactionId: ledger.id,
      pointsAwarded: pointsAwarded,
    };
  });

  return e.json(200, result);
}, $apis.requireAuth());

// ---------------------------------------------------------------------------
// POST /api/michwar/rides/:id/rate — replaces callable/submitRating.ts
// ---------------------------------------------------------------------------

routerAdd("POST", "/api/michwar/rides/{id}/rate", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var rideId = e.request.pathValue("id");
  var data = new DynamicModel({ stars: 0, comment: "" });
  e.bindBody(data);

  if (data.stars < 1 || data.stars > 5) {
    throw new BadRequestError("stars must be between 1 and 5.");
  }

  $app.runInTransaction((txApp) => {
    var ride = txApp.findRecordById("rides", rideId);

    if (ride.get("passenger") !== e.auth.id) throw new ForbiddenError("Only the passenger can rate this ride.");
    if (ride.get("status") !== "completed") throw new BadRequestError("Only completed rides can be rated.");
    if (ride.get("rating")) throw new BadRequestError("This ride has already been rated.");
    if (!ride.get("driver")) throw new BadRequestError("This ride has no assigned driver.");

    var rating = { stars: data.stars };
    if (data.comment) rating.comment = data.comment;
    ride.set("rating", rating);
    txApp.save(ride);

    var driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: ride.get("driver") });
    var prevCount = driver.get("ratingCount") || 0;
    var prevAverage = driver.get("ratingAverage") || 5.0;
    var newCount = prevCount + 1;
    var newAverage = (prevAverage * prevCount + data.stars) / newCount;

    var tier = mwResolveCommissionTier(driver.get("ridesCompleted") || 0, newAverage, driver.get("commissionTier") || "tier1");

    driver.set("ratingAverage", newAverage);
    driver.set("ratingCount", newCount);
    driver.set("commissionTier", tier.tier);
    driver.set("commissionRate", tier.commissionRate);
    driver.set("driverShareRate", tier.driverShareRate);
    txApp.save(driver);
  });

  return e.json(200, { ok: true });
}, $apis.requireAuth());

// ---------------------------------------------------------------------------
// POST /api/michwar/rides/:id/share — replaces callable/generateLiveShareLink.ts
// ---------------------------------------------------------------------------

routerAdd("POST", "/api/michwar/rides/{id}/share", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var rideId = e.request.pathValue("id");
  var ride = $app.findRecordById("rides", rideId);

  if (ride.get("passenger") !== e.auth.id && ride.get("driver") !== e.auth.id) {
    throw new ForbiddenError("Only ride participants can share this trip.");
  }

  var expiresAtMs = Date.now() + MICHWAR.LIVE_SHARE_LINK_VALIDITY_MS;
  var expiresAt = new Date(expiresAtMs).toISOString();

  var share = new Record($app.findCollectionByNameOrId("live_shares"));
  share.set("ride", rideId);
  share.set("createdBy", e.auth.id);
  share.set("expiresAt", expiresAt);
  $app.save(share);

  ride.set("liveShareToken", share.id);
  ride.set("liveShareExpiresAt", expiresAt);
  $app.save(ride);

  return e.json(200, { url: MICHWAR.LIVE_SHARE_BASE_URL + "/" + share.id, expiresAt: expiresAtMs });
}, $apis.requireAuth());
