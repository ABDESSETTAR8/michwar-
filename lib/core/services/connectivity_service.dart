import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Powers the "Graceful Disconnection" requirement (Safety & Reliability):
/// caches in-flight ride state locally during a connectivity gap (e.g. a
/// tunnel) and exposes a stream other services subscribe to in order to
/// flush queued writes the instant connectivity is restored.
class ConnectivityService {
  ConnectivityService() {
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
  }

  static const String _cacheBoxName = 'michwar_offline_cache';

  late final StreamSubscription<List<ConnectivityResult>> _sub;
  final _statusController = StreamController<bool>.broadcast();
  bool _isOnline = true;

  /// Emits `true` when the device transitions from offline -> online.
  Stream<bool> get onReconnected =>
      _statusController.stream.where((online) => online);

  Stream<bool> get connectivityStream => _statusController.stream;

  bool get isOnline => _isOnline;

  static Future<Box> _box() async {
    if (!Hive.isBoxOpen(_cacheBoxName)) {
      await Hive.openBox(_cacheBoxName);
    }
    return Hive.box(_cacheBoxName);
  }

  void _onChange(List<ConnectivityResult> results) {
    final online = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      _statusController.add(online);
    }
  }

  /// Persists a pending write (e.g. "ride status changed to ongoing at
  /// T+x") so it can be replayed once connectivity returns.
  static Future<void> queuePendingWrite(
    String key,
    Map<String, dynamic> payload,
  ) async {
    final box = await _box();
    await box.put(key, payload);
  }

  static Future<Map<dynamic, dynamic>> pendingWrites() async {
    final box = await _box();
    return box.toMap();
  }

  static Future<void> clearPendingWrite(String key) async {
    final box = await _box();
    await box.delete(key);
  }

  void dispose() {
    _sub.cancel();
    _statusController.close();
  }
}
