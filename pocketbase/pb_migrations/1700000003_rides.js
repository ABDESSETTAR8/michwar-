/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");

  const collection = new Collection({
    "name": "rides",
    "type": "base",
    "fields": [
      { "name": "passenger", "type": "relation", "required": true, "collectionId": users.id, "maxSelect": 1 },
      { "name": "driver", "type": "relation", "collectionId": users.id, "maxSelect": 1 },
      { "name": "status", "type": "select", "required": true, "maxSelect": 1, "values": ["searching", "accepted", "arrived", "ongoing", "completed", "cancelled_by_passenger", "cancelled_by_driver", "no_drivers_found"] },
      { "name": "rideTier", "type": "select", "required": true, "maxSelect": 1, "values": ["standard", "eco", "premium"] },
      { "name": "pickup", "type": "json", "required": true },
      { "name": "dropoff", "type": "json", "required": true },
      { "name": "pickupGeohash", "type": "text", "max": 12 },
      { "name": "estimate", "type": "json" },
      { "name": "fare", "type": "json" },
      { "name": "pointsAwarded", "type": "number" },
      { "name": "rating", "type": "json" },
      { "name": "liveShareToken", "type": "text" },
      { "name": "liveShareExpiresAt", "type": "date" },
      { "name": "candidateDriverIds", "type": "json" },
      { "name": "actualDistanceKm", "type": "number" },
      { "name": "actualDurationMin", "type": "number" },
      { "name": "requestedAt", "type": "date" },
      { "name": "acceptedAt", "type": "date" },
      { "name": "arrivedAt", "type": "date" },
      { "name": "startedAt", "type": "date" },
      { "name": "completedAt", "type": "date" },
      { "name": "cancelledAt", "type": "date" }
    ],
    "indexes": [
      "CREATE INDEX idx_rides_status ON rides (status)",
      "CREATE INDEX idx_rides_passenger ON rides (passenger, status)",
      "CREATE INDEX idx_rides_driver ON rides (driver, status)",
      "CREATE INDEX idx_rides_pickup_geohash ON rides (pickupGeohash)"
    ],
    "listRule": "@request.auth.id = passenger || @request.auth.id = driver || @request.auth.role = 'admin'",
    "viewRule": "@request.auth.id = passenger || @request.auth.id = driver || @request.auth.role = 'admin'",
    "createRule": "@request.auth.id = passenger && status = 'searching'",
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("rides");
  return app.delete(collection);
});
