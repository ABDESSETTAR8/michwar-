/// <reference path="../pb_data/types.d.ts" />

// Port of lib/core/utils/geohash_util.dart / functions/src/utils/geohash.ts.
// Both client and server copies MUST stay in sync so geohash prefixes match.

var MW_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/** Encodes lat/lng into a geohash string of `precision` characters. */
function mwGeohashEncode(lat, lng, precision) {
  precision = precision || 7;

  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;

  var result = "";
  var isEven = true;
  var bit = 0;
  var ch = 0;

  while (result.length < precision) {
    if (isEven) {
      var midLng = (lngMin + lngMax) / 2;
      if (lng >= midLng) {
        ch |= (1 << (4 - bit));
        lngMin = midLng;
      } else {
        lngMax = midLng;
      }
    } else {
      var midLat = (latMin + latMax) / 2;
      if (lat >= midLat) {
        ch |= (1 << (4 - bit));
        latMin = midLat;
      } else {
        latMax = midLat;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      result += MW_BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  return result;
}

var MW_CELL_WIDTHS_KM = {
  1: 5009.4, 2: 1252.3, 3: 156.5, 4: 39.1, 5: 4.89, 6: 1.22, 7: 0.153, 8: 0.038, 9: 0.0048,
};

function mwCellSizeKm(precision) {
  return MW_CELL_WIDTHS_KM[precision] || 0.153;
}

function mwDegToRad(deg) {
  return (deg * Math.PI) / 180;
}

/** Great-circle distance in kilometers (Haversine formula). */
function mwDistanceKm(lat1, lng1, lat2, lng2) {
  var earthRadiusKm = 6371.0;
  var dLat = mwDegToRad(lat2 - lat1);
  var dLng = mwDegToRad(lng2 - lng1);
  var a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(mwDegToRad(lat1)) * Math.cos(mwDegToRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/** Initial bearing (degrees, 0-360) from point 1 to point 2. */
function mwBearingDeg(lat1, lng1, lat2, lng2) {
  var phi1 = mwDegToRad(lat1);
  var phi2 = mwDegToRad(lat2);
  var dLambda = mwDegToRad(lng2 - lng1);

  var y = Math.sin(dLambda) * Math.cos(phi2);
  var x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLambda);
  var theta = Math.atan2(y, x);
  return ((theta * 180) / Math.PI + 360) % 360;
}

/**
 * Returns geohash prefixes covering a square of side `~2 * radiusKm`
 * centered on lat/lng, used to build OR'd range queries against
 * `drivers.locationGeohash`.
 */
function mwNeighborsForRadius(lat, lng, radiusKm, precision) {
  var chosenPrecision = precision || 7;
  for (var p = 1; p <= 9; p++) {
    if (mwCellSizeKm(p) >= radiusKm) chosenPrecision = p;
  }

  var centerHash = mwGeohashEncode(lat, lng, chosenPrecision);
  var cellKm = mwCellSizeKm(chosenPrecision);
  var latDelta = cellKm / 111.32;
  var cosLat = Math.min(Math.max(Math.abs(Math.cos((lat * Math.PI) / 180)), 0.01), 1);
  var lngDelta = cellKm / (111.32 * cosLat);

  var hashes = {};
  hashes[centerHash] = true;

  var deltas = [-1, 0, 1];
  for (var i = 0; i < deltas.length; i++) {
    for (var j = 0; j < deltas.length; j++) {
      if (deltas[i] === 0 && deltas[j] === 0) continue;
      var neighborLat = lat + deltas[i] * latDelta;
      var neighborLng = lng + deltas[j] * lngDelta;
      hashes[mwGeohashEncode(neighborLat, neighborLng, chosenPrecision)] = true;
    }
  }

  return Object.keys(hashes);
}

/**
 * Given a geohash prefix, returns the `[start, end)` string range usable
 * with `field >= start && field < end` filters to match all geohashes
 * sharing that prefix (SQLite TEXT compares lexicographically).
 */
function mwGeohashBounds(prefix) {
  return { start: prefix, end: prefix + "~" };
}
