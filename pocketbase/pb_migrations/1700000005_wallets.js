/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");

  const collection = new Collection({
    "name": "wallets",
    "type": "base",
    "fields": [
      { "name": "driver", "type": "relation", "required": true, "collectionId": users.id, "cascadeDelete": true, "maxSelect": 1 },
      { "name": "balance", "type": "number", "required": true },
      { "name": "lowBalance", "type": "bool" },
      { "name": "lastTopUpAt", "type": "date" },
      { "name": "lastDeductionAt", "type": "date" }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX idx_wallets_driver ON wallets (driver)"
    ],
    "listRule": "@request.auth.id = driver || @request.auth.role = 'admin'",
    "viewRule": "@request.auth.id = driver || @request.auth.role = 'admin'",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("wallets");
  return app.delete(collection);
});
