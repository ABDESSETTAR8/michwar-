/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const users = app.findCollectionByNameOrId("users");

  const collection = new Collection({
    "name": "drivers",
    "type": "base",
    "fields": [
      { "name": "user", "type": "relation", "required": true, "collectionId": users.id, "cascadeDelete": true, "minSelect": 1, "maxSelect": 1 },
      { "name": "vehicleMake", "type": "text" },
      { "name": "vehicleModel", "type": "text" },
      { "name": "vehiclePlate", "type": "text" },
      { "name": "vehicleColor", "type": "text" },
      { "name": "vehicleCategory", "type": "select", "maxSelect": 1, "values": ["standard", "eco", "premium"] },
      { "name": "verificationStatus", "type": "select", "maxSelect": 1, "values": ["pending", "under_review", "approved", "rejected"] },
      { "name": "documents", "type": "file", "maxSelect": 6, "maxSize": 10485760, "mimeTypes": ["image/png", "image/jpeg"] },
      { "name": "documentsMeta", "type": "json", "maxSize": 200000 },
      { "name": "commissionTier", "type": "select", "maxSelect": 1, "values": ["tier1", "tier2"] },
      { "name": "commissionRate", "type": "number" },
      { "name": "driverShareRate", "type": "number" },
      { "name": "ridesCompleted", "type": "number" },
      { "name": "ratingAverage", "type": "number" },
      { "name": "ratingCount", "type": "number" },
      { "name": "isOnline", "type": "bool" },
      { "name": "isOnTrip", "type": "bool" },
      { "name": "headingHomeEnabled", "type": "bool" },
      { "name": "headingHomeDestLat", "type": "number" },
      { "name": "headingHomeDestLng", "type": "number" },
      { "name": "headingHomeBearingTolerance", "type": "number" },
      { "name": "locationLat", "type": "number" },
      { "name": "locationLng", "type": "number" },
      { "name": "locationGeohash", "type": "text", "max": 12 },
      { "name": "locationHeading", "type": "number" },
      { "name": "locationSpeed", "type": "number" },
      { "name": "locationUpdatedAt", "type": "date" },
      { "name": "walletBalance", "type": "number" }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX idx_drivers_user ON drivers (user)",
      "CREATE INDEX idx_drivers_geo ON drivers (isOnline, isOnTrip, locationGeohash)"
    ],
    "listRule": "@request.auth.id != ''",
    "viewRule": "@request.auth.id != ''",
    "createRule": "@request.auth.id = user",
    "updateRule": "@request.auth.id = user || @request.auth.role = 'admin'",
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("drivers");
  return app.delete(collection);
});
