/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const rides = app.findCollectionByNameOrId("rides");

  const collection = new Collection({
    "name": "wallet_transactions",
    "type": "base",
    "fields": [
      { "name": "driver", "type": "relation", "required": true, "collectionId": users.id, "maxSelect": 1 },
      { "name": "ride", "type": "relation", "collectionId": rides.id, "maxSelect": 1 },
      { "name": "passenger", "type": "relation", "collectionId": users.id, "maxSelect": 1 },
      { "name": "type", "type": "select", "required": true, "maxSelect": 1, "values": ["ride_earning", "wallet_top_up", "wallet_deduction", "adjustment"] },
      { "name": "baseFare", "type": "number" },
      { "name": "surchargeRevenue", "type": "number" },
      { "name": "commissionRate", "type": "number" },
      { "name": "commissionDeducted", "type": "number" },
      { "name": "netPayoutToDriver", "type": "number" },
      { "name": "companyRevenue", "type": "number" },
      { "name": "walletBalanceAfter", "type": "number" }
    ],
    "indexes": [
      "CREATE INDEX idx_wtx_driver ON wallet_transactions (driver, created)",
      "CREATE INDEX idx_wtx_type ON wallet_transactions (driver, type, created)"
    ],
    "listRule": "@request.auth.id = driver || @request.auth.role = 'admin'",
    "viewRule": "@request.auth.id = driver || @request.auth.role = 'admin'",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("wallet_transactions");
  return app.delete(collection);
});
