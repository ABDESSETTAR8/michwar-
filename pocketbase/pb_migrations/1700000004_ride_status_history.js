/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");
  const rides = app.findCollectionByNameOrId("rides");

  const collection = new Collection({
    "name": "ride_status_history",
    "type": "base",
    "fields": [
      { "name": "ride", "type": "relation", "required": true, "collectionId": rides.id, "cascadeDelete": true, "maxSelect": 1 },
      { "name": "status", "type": "text", "required": true },
      { "name": "actor", "type": "relation", "collectionId": users.id, "maxSelect": 1 }
    ],
    "indexes": [
      "CREATE INDEX idx_rsh_ride ON ride_status_history (ride)"
    ],
    "listRule": "@request.auth.id = ride.passenger || @request.auth.id = ride.driver || @request.auth.role = 'admin'",
    "viewRule": "@request.auth.id = ride.passenger || @request.auth.id = ride.driver || @request.auth.role = 'admin'",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("ride_status_history");
  return app.delete(collection);
});
