/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const rides = app.findCollectionByNameOrId("rides");

  const collection = new Collection({
    "name": "live_shares",
    "type": "base",
    "fields": [
      { "name": "ride", "type": "relation", "required": true, "collectionId": rides.id, "maxSelect": 1 },
      { "name": "createdBy", "type": "relation", "required": true, "collectionId": users.id, "maxSelect": 1 },
      { "name": "expiresAt", "type": "date", "required": true }
    ],
    "indexes": [],
    // Public (unauthenticated) read while the share hasn't expired yet —
    // used by the "Live Trip Sharing" tracking page.
    "listRule": null,
    "viewRule": "@now < expiresAt",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("live_shares");
  return app.delete(collection);
});
