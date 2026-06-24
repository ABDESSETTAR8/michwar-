import 'dart:math' as math;

/// Pure-Dart Geohash implementation used by the client to:
///  1. Tag the driver's own location before writing it to Firestore.
///  2. Compute the set of geohash prefixes ("cells") to query when looking
///     for nearby drivers — avoiding full-collection scans.
///
/// The Cloud Functions side (`functions/src/utils/geohash.ts`) implements
/// the identical algorithm so both ends agree on cell boundaries.
class GeohashUtil {
  GeohashUtil._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Encodes [lat]/[lng] into a geohash string of [precision] characters.
  /// Precision 7 ≈ 153m x 153m — the default used for driver documents
  /// (see `AppConstants.geohashPrecision`).
  static String encode(double lat, double lng, {int precision = 7}) {
    double latMin = -90.0, latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;

    final buffer = StringBuffer();
    bool isEven = true;
    int bit = 0;
    int ch = 0;

    while (buffer.length < precision) {
      if (isEven) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          ch |= (1 << (4 - bit));
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          ch |= (1 << (4 - bit));
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        buffer.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return buffer.toString();
  }

  /// Returns the lat/lng bounding box `[minLat, minLng, maxLat, maxLng]`
  /// for a given geohash.
  static List<double> decodeBounds(String geohash) {
    double latMin = -90.0, latMax = 90.0;
    double lngMin = -180.0, lngMax = 180.0;
    bool isEven = true;

    for (final char in geohash.split('')) {
      final idx = _base32.indexOf(char);
      for (int n = 4; n >= 0; n--) {
        final bit = (idx >> n) & 1;
        if (isEven) {
          final mid = (lngMin + lngMax) / 2;
          if (bit == 1) {
            lngMin = mid;
          } else {
            lngMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if (bit == 1) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isEven = !isEven;
      }
    }

    return [latMin, lngMin, latMax, lngMax];
  }

  /// Returns the approximate cell width/height in kilometers for a given
  /// geohash precision. Used to decide how many neighboring cells need to
  /// be queried to cover [radiusKm].
  static double cellSizeKm(int precision) {
    const widths = {
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
    return widths[precision] ?? 0.153;
  }

  /// Returns a list of geohash prefixes covering a square of side
  /// `~2 * radiusKm` centered on [lat]/[lng]. The matching Cloud
  /// Function / client query then runs one `where(geohash, isGreaterThan:
  /// prefix, isLessThan: prefix + '~')` range query per prefix and merges
  /// the results, finally filtering by exact great-circle distance.
  static List<String> neighborsForRadius(
    double lat,
    double lng,
    double radiusKm, {
    int precision = 7,
  }) {
    // Pick the largest precision whose cell size is >= radiusKm so a 3x3
    // grid of neighbors comfortably covers the search radius.
    int chosenPrecision = precision;
    for (int p = 1; p <= 9; p++) {
      if (cellSizeKm(p) >= radiusKm) {
        chosenPrecision = p;
      }
    }

    final centerHash = encode(lat, lng, precision: chosenPrecision);
    final cellKm = cellSizeKm(chosenPrecision);
    final latDelta = cellKm / 111.32; // ~km per degree latitude
    final lngDelta =
        cellKm / (111.32 * math.cos(lat * math.pi / 180).abs().clamp(0.01, 1));

    final hashes = <String>{centerHash};
    for (final dLat in [-1, 0, 1]) {
      for (final dLng in [-1, 0, 1]) {
        if (dLat == 0 && dLng == 0) continue;
        final neighborLat = lat + dLat * latDelta;
        final neighborLng = lng + dLng * lngDelta;
        hashes.add(encode(neighborLat, neighborLng, precision: chosenPrecision));
      }
    }

    return hashes.toList();
  }

  /// Great-circle distance in kilometers (Haversine formula).
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Initial bearing (degrees, 0-360) from point 1 to point 2.
  static double bearingDeg(double lat1, double lng1, double lat2, double lng2) {
    final phi1 = _degToRad(lat1);
    final phi2 = _degToRad(lat2);
    final dLambda = _degToRad(lng2 - lng1);

    final y = math.sin(dLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  static double _degToRad(double deg) => deg * math.pi / 180;
}
