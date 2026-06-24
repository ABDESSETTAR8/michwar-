/**
 * TypeScript mirror of `lib/core/utils/geohash_util.dart`. Both
 * implementations MUST stay in sync so client-side cell prefixes match
 * server-side range queries.
 */

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/** Encodes lat/lng into a geohash string of `precision` characters. */
export function encodeGeohash(lat: number, lng: number, precision = 7): string {
  let latMin = -90.0;
  let latMax = 90.0;
  let lngMin = -180.0;
  let lngMax = 180.0;

  let result = "";
  let isEven = true;
  let bit = 0;
  let ch = 0;

  while (result.length < precision) {
    if (isEven) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        ch |= 1 << (4 - bit);
        lngMin = mid;
      } else {
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch |= 1 << (4 - bit);
        latMin = mid;
      } else {
        latMax = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      result += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  return result;
}

const CELL_WIDTHS_KM: Record<number, number> = {
  1: 5009.4,
  2: 1252.3,
  3: 156.5,
  4: 39.1,
  5: 4.89,
  6: 1.22,
  7: 0.153,
  8: 0.038,
  9: 0.0048,
};

export function cellSizeKm(precision: number): number {
  return CELL_WIDTHS_KM[precision] ?? 0.153;
}

function degToRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

/** Great-circle distance in kilometers (Haversine formula). */
export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const earthRadiusKm = 6371.0;
  const dLat = degToRad(lat2 - lat1);
  const dLng = degToRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(degToRad(lat1)) * Math.cos(degToRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

/** Initial bearing (degrees, 0-360) from point 1 to point 2. */
export function bearingDeg(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const phi1 = degToRad(lat1);
  const phi2 = degToRad(lat2);
  const dLambda = degToRad(lng2 - lng1);

  const y = Math.sin(dLambda) * Math.cos(phi2);
  const x = Math.cos(phi1) * Math.sin(phi2) - Math.sin(phi1) * Math.cos(phi2) * Math.cos(dLambda);
  const theta = Math.atan2(y, x);
  return ((theta * 180) / Math.PI + 360) % 360;
}

/**
 * Returns a set of geohash prefixes covering a square of side
 * `~2 * radiusKm` centered on lat/lng — used to build the OR'd range
 * queries against `drivers.location.geohash`.
 */
export function neighborsForRadius(lat: number, lng: number, radiusKm: number, precision = 7): string[] {
  let chosenPrecision = precision;
  for (let p = 1; p <= 9; p++) {
    if (cellSizeKm(p) >= radiusKm) {
      chosenPrecision = p;
    }
  }

  const centerHash = encodeGeohash(lat, lng, chosenPrecision);
  const cellKm = cellSizeKm(chosenPrecision);
  const latDelta = cellKm / 111.32;
  const cosLat = Math.min(Math.max(Math.abs(Math.cos((lat * Math.PI) / 180)), 0.01), 1);
  const lngDelta = cellKm / (111.32 * cosLat);

  const hashes = new Set<string>([centerHash]);
  for (const dLat of [-1, 0, 1]) {
    for (const dLng of [-1, 0, 1]) {
      if (dLat === 0 && dLng === 0) continue;
      const neighborLat = lat + dLat * latDelta;
      const neighborLng = lng + dLng * lngDelta;
      hashes.add(encodeGeohash(neighborLat, neighborLng, chosenPrecision));
    }
  }

  return Array.from(hashes);
}

/**
 * Given a geohash prefix, returns the `[start, end)` string range usable
 * with Firestore `where(field, '>=', start).where(field, '<', end)`
 * queries to match all geohashes sharing that prefix.
 */
export function geohashQueryBounds(prefix: string): { start: string; end: string } {
  return { start: prefix, end: prefix + "~" };
}
