/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  // PocketBase >= 0.23 bootstraps a default "users" auth collection on a
  // fresh instance, which collides with the one this migration creates
  // ("Collection name must be unique (case insensitive)"). Since this is
  // the very first migration (runs before anything references "users"),
  // it's safe to drop the bootstrap collection and replace it with ours.
  try {
    const existing = app.findCollectionByNameOrId("users");
    if (existing) {
      app.delete(existing);
    }
  } catch (e) {
    // no existing "users" collection — nothing to remove
  }

  const collection = new Collection({
    "name": "users",
    "type": "auth",
    "fields": [
      { "name": "fullName", "type": "text", "required": true, "max": 120 },
      { "name": "phoneNumber", "type": "text", "required": true, "max": 20 },
      { "name": "role", "type": "select", "required": true, "maxSelect": 1, "values": ["passenger", "driver", "admin"] },
      { "name": "roleSelected", "type": "bool" },
      { "name": "avatar", "type": "file", "maxSelect": 1, "maxSize": 5242880, "mimeTypes": ["image/png", "image/jpeg", "image/webp"] },
      { "name": "loyaltyPoints", "type": "number" },
      { "name": "loyaltyTier", "type": "select", "maxSelect": 1, "values": ["standard", "eco", "premium"] },
      { "name": "totalRidesCompleted", "type": "number" },
      { "name": "savedPlaces", "type": "json", "maxSize": 200000 },
      { "name": "sosContacts", "type": "json", "maxSize": 200000 },
      { "name": "fcmTokens", "type": "json", "maxSize": 50000 }
    ],
    "passwordAuth": { "enabled": true, "identityFields": ["email"] },
    "listRule": null,
    "viewRule": "id = @request.auth.id || @request.auth.role = 'admin'",
    "createRule": "",
    "updateRule": "id = @request.auth.id",
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("users");
  return app.delete(collection);
});
