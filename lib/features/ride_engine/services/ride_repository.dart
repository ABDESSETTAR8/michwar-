import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/models/ride_model.dart';

/// Central gateway for all ride lifecycle operations against Firestore and
/// Cloud Functions.
///
/// Reads are realtime Firestore snapshots. Every write that affects money,
/// ratings, or authoritative ride status goes through a Cloud Function
/// callable so the server can validate the transition and — for `complete` —
/// perform the financial split described in Section 6.
class RideRepository {
  RideRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _fs;
  final FirebaseFunctions _fn;

  CollectionReference<Map<String, dynamic>> get _rides =>
      _fs.collection(FsCollections.rides);

  HttpsCallable _call(String name) => _fn.httpsCallable(name);

  // ── Write operations ──────────────────────────────────────────────────────

  /// Creates a new ride request with `status: searching`. The Cloud Function
  /// trigger `onRideRequestCreated` sets driver-matching fields server-side.
  ///
  /// Also pings the heatmap via the `pingHeatmap` callable.
  Future<String> requestRide({
    required String passengerId,
    required GeoPoint2 pickup,
    required GeoPoint2 dropoff,
    required RideEstimate estimate,
    String rideTier = 'standard',
  }) async {
    final ref = await _rides.add({
      'passenger': passengerId,
      'driver': null,
      'status': 'searching',
      'rideTier': rideTier,
      'pickup': pickup.toMap(),
      'dropoff': dropoff.toMap(),
      'estimate': estimate.toMap(),
      'requestedAt': FieldValue.serverTimestamp(),
    });

    try {
      await _call(FsFunctions.pingHeatmap).call({
        'lat': pickup.lat,
        'lng': pickup.lng,
      });
    } catch (_) {
      // Heatmap telemetry is best-effort.
    }

    return ref.id;
  }

  /// Driver accepts a ride. Cloud Function validates atomically that the ride
  /// is still `searching` and unassigned — prevents double-accept.
  Future<void> acceptRide(String rideId, String driverId) async {
    await _call(FsFunctions.acceptRide).call({'rideId': rideId});
  }

  /// Driver/passenger-initiated status transitions:
  /// `arrived`, `ongoing`, `cancelled_by_driver`, `cancelled_by_passenger`.
  /// Validated server-side — only legal transitions by the assigned party.
  Future<void> updateStatus(String rideId, RideStatus status) async {
    await _call(FsFunctions.updateRideStatus).call({
      'rideId': rideId,
      'status': rideStatusToString(status),
    });
  }

  /// THE financial trigger (Section 6). Pass the trip's actual tracked
  /// distance/duration. The Cloud Function:
  ///  1. Computes the base fare from distance/time.
  ///  2. Adds the platform surcharge.
  ///  3. Applies the driver's commission tier.
  ///  4. Deducts (commission + surcharge) from the driver's wallet.
  ///  5. Writes a `wallet_transactions/{id}` ledger entry.
  ///  6. Awards MICHWAR Points to the passenger.
  ///  7. Re-checks Elite tier promotion.
  ///  8. Sets `rides/{rideId}.status = completed` with the `fare` JSON.
  Future<RideFare> completeRide({
    required String rideId,
    required double actualDistanceKm,
    required double actualDurationMin,
  }) async {
    final result = await _call(FsFunctions.completeRide).call({
      'rideId': rideId,
      'actualDistanceKm': actualDistanceKm,
      'actualDurationMin': actualDurationMin,
    });

    return RideFare.fromMap(Map<String, dynamic>.from(result.data as Map));
  }

  /// Passenger rates the driver after a completed ride.
  Future<void> submitRating({
    required String rideId,
    required int stars,
    String? comment,
  }) async {
    await _call(FsFunctions.rateRide).call({
      'rideId': rideId,
      'stars': stars,
      if (comment != null) 'comment': comment,
    });
  }

  Future<void> cancelRide(String rideId, {required bool byDriver}) {
    return updateStatus(
      rideId,
      byDriver ? RideStatus.cancelledByDriver : RideStatus.cancelledByPassenger,
    );
  }

  /// Generates a temporary secure link for Live Trip Sharing.
  Future<String> generateLiveShareLink(String rideId) async {
    final result = await _call(FsFunctions.shareRide).call({'rideId': rideId});
    return (result.data as Map)['url'] as String;
  }

  /// In-app SOS — sends rider/driver's live coordinates + ride context to
  /// the admin team.
  Future<void> triggerSos({
    required String rideId,
    required double lat,
    required double lng,
  }) async {
    await _call(FsFunctions.triggerSos).call({
      'rideId': rideId,
      'lat': lat,
      'lng': lng,
    });
  }

  // ── Read / stream operations ──────────────────────────────────────────────

  /// Live stream of a single ride record.
  Stream<RideModel?> watchRide(String rideId) {
    return _rides.doc(rideId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _fromDoc(snap);
    });
  }

  /// Stream of incoming ride requests for a driver — rides in `searching`
  /// status where this driver is in `candidateDriverIds`.
  Stream<List<RideModel>> watchIncomingRequests(String driverId) {
    return _rides
        .where('status', isEqualTo: 'searching')
        .where('candidateDriverIds', arrayContains: driverId)
        .orderBy('requestedAt', descending: true)
        .limit(5)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  /// Stream of past rides for a user (ride history / wallet history).
  Stream<List<RideModel>> watchRideHistory(String userId,
      {required bool isDriver}) {
    final field = isDriver ? 'driver' : 'passenger';
    return _rides
        .where(field, isEqualTo: userId)
        .where('status', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(_fromDoc).toList());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  RideModel _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    // Normalize Firestore Timestamps → ISO strings for RideModel.fromMap.
    final normalized = data.map(
      (k, v) => MapEntry(k, v is Timestamp ? v.toDate().toIso8601String() : v),
    );
    return RideModel.fromMap(doc.id, normalized);
  }
}
