/// <reference path="../pb_data/types.d.ts" />

// POST /api/michwar/heatmap/ping  { lat: number, lng: number }
// Atomic increment of the demand-heatmap cell for this location, replacing
// the direct Firestore increment() write from the client. Called by the
// passenger app whenever a ride request is made.
routerAdd("POST", "/api/michwar/heatmap/ping", (e) => {
  if (!e.auth) throw new UnauthorizedError("You must be signed in.");

  var data = new DynamicModel({ lat: 0, lng: 0 });
  e.bindBody(data);

  var geohash = mwGeohashEncode(data.lat, data.lng, MICHWAR.HEATMAP_GEOHASH_PRECISION);

  $app.runInTransaction((txApp) => {
    var cell = null;
    try {
      cell = txApp.findFirstRecordByFilter("heatmap_cells", "geohash = {:gh}", { gh: geohash });
    } catch (err) {
      cell = null;
    }

    if (!cell) {
      cell = new Record(txApp.findCollectionByNameOrId("heatmap_cells"));
      cell.set("geohash", geohash);
      cell.set("lat", data.lat);
      cell.set("lng", data.lng);
      cell.set("count", 0);
    }

    cell.set("count", (cell.get("count") || 0) + 1);
    cell.set("updatedAt", new Date().toISOString());
    txApp.save(cell);
  });

  return e.json(200, { ok: true });
}, $apis.requireAuth());
