import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/models/driver_model.dart';
import '../../../core/models/ride_model.dart';
import '../../../core/providers/app_providers.dart';
import '../services/geohash_service.dart';
import '../services/maps_service.dart';
import '../services/offline_sync_service.dart';
import '../services/pricing_service.dart';
import '../services/ride_repository.dart';

final geohashServiceProvider = Provider<GeohashService>(
  (ref) => GeohashService(firestore: ref.watch(firestoreProvider)),
);

final mapsServiceProvider = Provider<MapsService>((ref) => MapsService());

final pricingServiceProvider = Provider<PricingService>(
  (ref) => const PricingService(),
);

final rideRepositoryProvider = Provider<RideRepository>((ref) {
  return RideRepository(firestore: ref.watch(firestoreProvider));
});

final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final service = OfflineSyncService(
    connectivity: ref.watch(connectivityServiceProvider),
    rideRepository: ref.watch(rideRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Live stream of a single ride — shared by Passenger's ActiveRideScreen
/// and Driver's DriverActiveRideScreen.
final rideStreamProvider =
    StreamProvider.family<RideModel?, String>((ref, rideId) {
  return ref.watch(rideRepositoryProvider).watchRide(rideId);
});

/// Stream of incoming ride requests for the signed-in driver.
final incomingRequestsProvider = StreamProvider<List<RideModel>>((ref) {
  final uid = ref.watch(authStateProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(rideRepositoryProvider).watchIncomingRequests(uid);
});

/// Live stream of any driver's `drivers` record — used by the passenger's
/// ActiveRideScreen to show the assigned driver's vehicle, rating, and live
/// location. [driverId] is the assigned driver's user uid.
final driverByIdProvider =
    StreamProvider.family<DriverModel?, String>((ref, driverId) {
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection(FsCollections.drivers)
      .where('userId', isEqualTo: driverId)
      .limit(1)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return DriverModel.fromFirestore(doc.id, doc.data());
  });
});
