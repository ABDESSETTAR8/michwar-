/// <reference path="../pb_data/types.d.ts" />

// Fields that are financial/performance/verification state and must never be
// changed by a normal client PATCH — only by the hook routes below (which
// write via $app.save() directly and so bypass this request hook) or by an
// admin.
var MW_DRIVER_PROTECTED_FIELDS = [
  "verificationStatus", "commissionTier", "commissionRate", "driverShareRate",
  "ridesCompleted", "ratingAverage", "ratingCount", "isOnTrip", "walletBalance",
];

onRecordCreateRequest((e) => {
  // Defaults for a newly-created `drivers` record (normally created via the
  // /api/michwar/role route, but keep sane defaults if created directly).
  if (!e.record.get("verificationStatus")) e.record.set("verificationStatus", "pending");
  if (!e.record.get("commissionTier")) e.record.set("commissionTier", "tier1");
  if (e.record.get("commissionRate") == null) e.record.set("commissionRate", MICHWAR.TIER1_COMMISSION_RATE);
  if (e.record.get("driverShareRate") == null) e.record.set("driverShareRate", MICHWAR.TIER1_DRIVER_RATE);
  if (e.record.get("ridesCompleted") == null) e.record.set("ridesCompleted", 0);
  if (e.record.get("ratingAverage") == null) e.record.set("ratingAverage", 5.0);
  if (e.record.get("ratingCount") == null) e.record.set("ratingCount", 0);
  if (e.record.get("isOnline") == null) e.record.set("isOnline", false);
  if (e.record.get("isOnTrip") == null) e.record.set("isOnTrip", false);
  if (e.record.get("walletBalance") == null) e.record.set("walletBalance", MICHWAR.WALLET_WELCOME_CREDIT_DZD);
  e.next();
}, "drivers");

onRecordUpdateRequest((e) => {
  var isAdmin = e.auth && e.auth.get("role") === "admin";
  if (!isAdmin) {
    var original = $app.findRecordById("drivers", e.record.id);
    for (var i = 0; i < MW_DRIVER_PROTECTED_FIELDS.length; i++) {
      var field = MW_DRIVER_PROTECTED_FIELDS[i];
      e.record.set(field, original.get(field));
    }

    // Driver Verification Workflow (Section 4): once a driver has uploaded
    // every required document, automatically flip pending -> under_review
    // so an admin can begin reviewing. This is the one exception to the
    // "verificationStatus is protected" rule above — it only ever moves
    // pending -> under_review, never grants approval.
    if (original.get("verificationStatus") === "pending") {
      var meta = e.record.get("documentsMeta") || {};
      var allUploaded = MICHWAR.REQUIRED_DRIVER_DOCUMENTS.every((type) => !!meta[type]);
      if (allUploaded) {
        e.record.set("verificationStatus", "under_review");
      }
    }
  }
  e.next();
}, "drivers");

/**
 * POST /api/michwar/role  { role: "passenger" | "driver" }
 *
 * Replaces the client-side "switchRole" Firestore write. Switching to
 * "driver" lazily creates the `drivers` profile (pending verification,
 * tier1 commission) and the `wallets` record pre-loaded with the
 * WALLET_WELCOME_CREDIT_DZD welcome credit (+ a matching ledger entry),
 * mirroring AuthService.switchRole.
 */
routerAdd("POST", "/api/michwar/role", (e) => {
  if (!e.auth) {
    throw new UnauthorizedError("You must be signed in.");
  }

  var data = new DynamicModel({ role: "" });
  e.bindBody(data);

  if (data.role !== "passenger" && data.role !== "driver") {
    throw new BadRequestError("role must be 'passenger' or 'driver'.");
  }

  $app.runInTransaction((txApp) => {
    var user = txApp.findRecordById("users", e.auth.id);
    user.set("role", data.role);
    user.set("roleSelected", true);
    txApp.save(user);

    if (data.role === "driver") {
      var driver = null;
      try {
        driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: e.auth.id });
      } catch (err) {
        driver = null;
      }

      if (!driver) {
        driver = new Record(txApp.findCollectionByNameOrId("drivers"));
        driver.set("user", e.auth.id);
        driver.set("verificationStatus", "pending");
        driver.set("commissionTier", "tier1");
        driver.set("commissionRate", MICHWAR.TIER1_COMMISSION_RATE);
        driver.set("driverShareRate", MICHWAR.TIER1_DRIVER_RATE);
        driver.set("ridesCompleted", 0);
        driver.set("ratingAverage", 5.0);
        driver.set("ratingCount", 0);
        driver.set("isOnline", false);
        driver.set("isOnTrip", false);
        driver.set("walletBalance", MICHWAR.WALLET_WELCOME_CREDIT_DZD);
        txApp.save(driver);
      }

      var wallet = null;
      try {
        wallet = txApp.findFirstRecordByFilter("wallets", "driver = {:uid}", { uid: e.auth.id });
      } catch (err) {
        wallet = null;
      }

      if (!wallet) {
        wallet = new Record(txApp.findCollectionByNameOrId("wallets"));
        wallet.set("driver", e.auth.id);
        wallet.set("balance", MICHWAR.WALLET_WELCOME_CREDIT_DZD);
        wallet.set("lowBalance", false);
        txApp.save(wallet);

        var ledger = new Record(txApp.findCollectionByNameOrId("wallet_transactions"));
        ledger.set("driver", e.auth.id);
        ledger.set("type", "wallet_top_up");
        ledger.set("baseFare", 0);
        ledger.set("surchargeRevenue", 0);
        ledger.set("commissionRate", 0);
        ledger.set("commissionDeducted", 0);
        ledger.set("netPayoutToDriver", MICHWAR.WALLET_WELCOME_CREDIT_DZD);
        ledger.set("companyRevenue", 0);
        ledger.set("walletBalanceAfter", MICHWAR.WALLET_WELCOME_CREDIT_DZD);
        txApp.save(ledger);
      }
    }
  });

  return e.json(200, { ok: true });
}, $apis.requireAuth());
