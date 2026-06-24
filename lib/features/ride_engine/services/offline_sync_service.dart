import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/models/ride_model.dart';
import '../../../core/services/connectivity_service.dart';
import 'ride_repository.dart';

/// Implements "Graceful Disconnection" (Safety & Reliability): if the
/// device loses connectivity mid-trip (e.g. entering a tunnel), pending
/// ride-state changes are cached locally and replayed the instant
/// connectivity returns — without requiring the user to restart the app
/// or the ride.
///
/// Usage: instantiate once per active ride screen (passenger or driver),
/// call [cacheRideSnapshot] whenever the local ride state changes, and
/// [start] to begin listening for reconnection.
class OfflineSyncService {
  OfflineSyncService({
    required ConnectivityService connectivity,
    required RideRepository rideRepository,
  })  : _connectivity = connectivity,
        _rideRepository = rideRepository;

  static const String _boxName = 'michwar_ride_cache';

  final ConnectivityService _connectivity;
  final RideRepository _rideRepository;
  StreamSubscription<bool>? _sub;

  Future<Box> _box() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Persists the latest known ride status + a pending status transition
  /// (if any) so it survives an app restart during the connectivity gap.
  Future<void> cacheRideSnapshot({
    required String rideId,
    required RideStatus lastKnownStatus,
    RideStatus? pendingStatusChange,
    double? lastLat,
    double? lastLng,
  }) async {
    final box = await _box();
    await box.put(rideId, {
      'lastKnownStatus': rideStatusToString(lastKnownStatus),
      'pendingStatusChange': pendingStatusChange == null
          ? null
          : rideStatusToString(pendingStatusChange),
      'lastLat': lastLat,
      'lastLng': lastLng,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Begins listening for reconnection events and flushes any queued
  /// status transition for [rideId].
  void start(String rideId) {
    _sub ??= _connectivity.onReconnected.listen((_) => _flush(rideId));
  }

  Future<void> _flush(String rideId) async {
    final box = await _box();
    final cached = box.get(rideId) as Map?;
    if (cached == null) return;

    final pending = cached['pendingStatusChange'] as String?;
    if (pending != null) {
      try {
        await _rideRepository.updateStatus(rideId, rideStatusFromString(pending));
        cached['pendingStatusChange'] = null;
        await box.put(rideId, cached);
      } catch (_) {
        // Will retry on the next reconnection event.
      }
    }
  }

  /// Returns the cached snapshot for [rideId], if any — used to restore
  /// the UI immediately on app resume, before the Firestore listener
  /// re-syncs.
  Future<Map?> getCachedSnapshot(String rideId) async {
    final box = await _box();
    return box.get(rideId) as Map?;
  }

  Future<void> clear(String rideId) async {
    final box = await _box();
    await box.delete(rideId);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
