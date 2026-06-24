/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "name": "heatmap_cells",
    "type": "base",
    "fields": [
      { "name": "geohash", "type": "text", "required": true, "max": 12 },
      { "name": "lat", "type": "number", "required": true },
      { "name": "lng", "type": "number", "required": true },
      { "name": "count", "type": "number", "required": true },
      { "name": "updatedAt", "type": "date" }
    ],
    "indexes": [
      "CREATE UNIQUE INDEX idx_heatmap_geohash ON heatmap_cells (geohash)",
      "CREATE INDEX idx_heatmap_updated ON heatmap_cells (updatedAt)"
    ],
    // Writes go through the /api/michwar/heatmap/ping hook (atomic
    // read-increment-write); direct client writes are disabled.
    "listRule": "@request.auth.id != ''",
    "viewRule": "@request.auth.id != ''",
    "createRule": null,
    "updateRule": null,
    "deleteRule": null
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("heatmap_cells");
  return app.delete(collection);
});
