import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/models/driver_model.dart';
import '../../../core/utils/geohash_util.dart';

/// A driver returned by a proximity search, annotated with its distance
/// from the search origin.
class NearbyDriver {
  final DriverModel driver;
  final double distanceKm;

  const NearbyDriver({required this.driver, required this.distanceKm});
}

/// Implements "fast and direct" proximity-based driver discovery using
/// Geohash range queries against Firestore — avoiding full-collection scans
/// (Section: Technical Constraints / Real-time Engine).
///
/// Strategy:
///  1. Compute the set of geohash cell-prefixes covering a square around
///     the search point ([GeohashUtil.neighborsForRadius]).
///  2. Run one Firestore query per prefix covering the range
///     `locationGeohash >= prefix && locationGeohash < prefix + '~'`
///     against the `drivers` collection.
///  3. Merge results, compute exact Haversine distance, and filter to
///     [radiusKm]. Expands the radius up to
///     [AppConstants.maxDriverSearchRadiusKm] if nothing is found.
class GeohashService {
  GeohashService({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  Future<List<NearbyDriver>> findNearbyOnlineDrivers({
    required double lat,
    required double lng,
    double radiusKm = AppConstants.defaultDriverSearchRadiusKm,
    String? rideTier,
    bool excludeOnTrip = true,
  }) async {
    double currentRadius = radiusKm;
    List<NearbyDriver> results = [];

    while (results.isEmpty && currentRadius <= AppConstants.maxDriverSearchRadiusKm) {
      results = await _queryRadius(
        lat: lat,
        lng: lng,
        radiusKm: currentRadius,
        rideTier: rideTier,
        excludeOnTrip: excludeOnTrip,
      );
      if (results.isNotEmpty) break;
      currentRadius *= 2;
    }

    results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return results;
  }

  Future<List<NearbyDriver>> _queryRadius({
    required double lat,
    required double lng,
    required double radiusKm,
    String? rideTier,
    required bool excludeOnTrip,
  }) async {
    final prefixes = GeohashUtil.neighborsForRadius(
      lat,
      lng,
      radiusKm,
      precision: AppConstants.geohashPrecision,
    );

    if (prefixes.isEmpty) return [];

    // Run one query per geohash prefix (Firestore doesn't support OR range).
    final futures = prefixes.map((prefix) {
      Query<Map<String, dynamic>> q = _fs
          .collection(FsCollections.drivers)
          .where('isOnline', isEqualTo: true)
          .where('verificationStatus', isEqualTo: 'approved')
          .where('locationGeohash', isGreaterThanOrEqualTo: prefix)
          .where('locationGeohash', isLessThanOrEqualTo: '$prefix~');

      if (rideTier != null) {
        q = q.where('vehicleCategory', isEqualTo: rideTier);
      }

      return q.get();
    }).toList();

    final snapshots = await Future.wait(futures);

    final seen = <String>{};
    final results = <NearbyDriver>[];

    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue; // deduplicate across prefix queries

        final driver = DriverModel.fromFirestore(doc.id, doc.data());
        if (excludeOnTrip && driver.isOnTrip) continue;
        if (!driver.canReceiveRides) continue;
        if (driver.location == null) continue;

        final distance = GeohashUtil.distanceKm(
          lat,
          lng,
          driver.location!.lat,
          driver.location!.lng,
        );
        if (distance <= radiusKm) {
          results.add(NearbyDriver(driver: driver, distanceKm: distance));
        }
      }
    }

    return results;
  }

  /// Updates the calling driver's live location + geohash on their
  /// `drivers` document. [driverId] is the user's uid. Called from
  /// [LocationService]'s position stream while the driver is online.
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0,
    double speed = 0,
  }) async {
    final geohash = GeohashUtil.encode(
      lat,
      lng,
      precision: AppConstants.geohashPrecision,
    );

    final snap = await _fs
        .collection(FsCollections.drivers)
        .where('userId', isEqualTo: driverId)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return;

    await snap.docs.first.reference.update({
      'locationLat': lat,
      'locationLng': lng,
      'locationGeohash': geohash,
      'locationHeading': heading,
      'locationSpeed': speed,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Streams recent demand heatmap cells for the Driver Map Home overlay.
  Stream<List<Map<String, dynamic>>> heatmapStream({int limit = 200}) {
    return _fs
        .collection(FsCollections.heatmapCells)
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }
}
