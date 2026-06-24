/// <reference path="../pb_data/types.d.ts" />

// POST /api/michwar/wallet/topup  { amountDzd: number }
// Replaces callable/topUpWallet.ts. In production this would normally be
// called from a payment-provider webhook after a successful charge, not
// directly by the client — but for a self-hosted MVP without a payment
// gateway, the driver app calls this directly to simulate a top-up.
routerAdd("POST", "/api/michwar/wallet/topup", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var data = new DynamicModel({ amountDzd: 0 });
  e.bindBody(data);

  if (data.amountDzd == null || data.amountDzd <= 0) {
    throw new BadRequestError("amountDzd must be a positive number.");
  }

  var result = null;

  $app.runInTransaction((txApp) => {
    var driver = txApp.findFirstRecordByFilter("drivers", "user = {:uid}", { uid: e.auth.id });

    var wallet = null;
    try {
      wallet = txApp.findFirstRecordByFilter("wallets", "driver = {:uid}", { uid: e.auth.id });
    } catch (err) {
      wallet = null;
    }

    var currentBalance = wallet ? (wallet.get("balance") || 0) : (driver.get("walletBalance") || 0);
    var updatedBalance = currentBalance + data.amountDzd;
    var lowBalance = updatedBalance <= MICHWAR.WALLET_LOW_BALANCE_THRESHOLD_DZD;

    driver.set("walletBalance", updatedBalance);
    txApp.save(driver);

    if (!wallet) {
      wallet = new Record(txApp.findCollectionByNameOrId("wallets"));
      wallet.set("driver", e.auth.id);
    }
    wallet.set("balance", updatedBalance);
    wallet.set("lowBalance", lowBalance);
    wallet.set("lastTopUpAt", new Date().toISOString());
    txApp.save(wallet);

    var ledger = new Record(txApp.findCollectionByNameOrId("wallet_transactions"));
    ledger.set("driver", e.auth.id);
    ledger.set("type", "wallet_top_up");
    ledger.set("baseFare", 0);
    ledger.set("surchargeRevenue", 0);
    ledger.set("commissionRate", 0);
    ledger.set("commissionDeducted", 0);
    ledger.set("netPayoutToDriver", data.amountDzd);
    ledger.set("companyRevenue", 0);
    ledger.set("walletBalanceAfter", updatedBalance);
    txApp.save(ledger);

    result = { newBalance: updatedBalance, transactionId: ledger.id };
  });

  return e.json(200, result);
}, $apis.requireAuth());
