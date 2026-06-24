/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const rides = app.findCollectionByNameOrId("rides");

  const collection = new Collection({
    "name": "sos_alerts",
    "type": "base",
    "fields": [
      { "name": "ride", "type": "relation", "required": true, "collectionId": rides.id, "maxSelect": 1 },
      { "name": "reportedBy", "type": "select", "required": true, "maxSelect": 1, "values": ["passenger", "driver"] },
      { "name": "user", "type": "relation", "required": true, "collectionId": users.id, "maxSelect": 1 },
      { "name": "locationLat", "type": "number" },
      { "name": "locationLng", "type": "number" },
      { "name": "rideStatus", "type": "text" },
      { "name": "passenger", "type": "relation", "collectionId": users.id, "maxSelect": 1 },
      { "name": "driver", "type": "relation", "collectionId": users.id, "maxSelect": 1 },
      { "name": "status", "type": "text" },
      { "name": "notifiedContacts", "type": "json" }
    ],
    "indexes": [],
    "listRule": "@request.auth.id = user || @request.auth.role = 'admin'",
    "viewRule": "@request.auth.id = user || @request.auth.role = 'admin'",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("sos_alerts");
  return app.delete(collection);
});
