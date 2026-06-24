import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../constants/app_constants.dart';

/// Driver activity state, used to pick the GPS polling interval.
enum GpsActivityState { idle, onlineWaiting, activeTrip }

/// Adaptive GPS tracking service (Smart Driver Tools: "Adaptive GPS").
///
/// Instead of streaming location updates at a fixed high frequency (which
/// drains battery), this service exposes a [Stream<Position>] whose
/// sampling interval changes with [setActivityState]:
///   - [GpsActivityState.idle]          -> every 30s   (driver offline)
///   - [GpsActivityState.onlineWaiting] -> every 8s    (online, no trip)
///   - [GpsActivityState.activeTrip]    -> every 3s    (trip in progress)
///
/// Internally this uses a periodic [Timer] + `getCurrentPosition` rather
/// than a raw `positionStream`, because Geolocator's distance-filter based
/// stream does not let us cheaply change frequency at runtime.
class LocationService {
  LocationService();

  Timer? _timer;
  GpsActivityState _state = GpsActivityState.idle;
  final _controller = StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _controller.stream;

  GpsActivityState get activityState => _state;

  /// Requests location permission. Returns true if granted (at least
  /// "while in use").
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    return serviceEnabled &&
        (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse);
  }

  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Starts adaptive polling. Safe to call repeatedly — restarts the timer
  /// with the interval for the current [activityState].
  void start() {
    _restartTimer();
  }

  /// Updates the activity state and immediately reschedules polling at the
  /// new frequency (battery-saving when idle, high-frequency on trips).
  void setActivityState(GpsActivityState state) {
    if (_state == state && _timer != null) return;
    _state = state;
    _restartTimer();
  }

  Duration get _intervalForState {
    switch (_state) {
      case GpsActivityState.activeTrip:
        return AppConstants.gpsIntervalActiveTrip;
      case GpsActivityState.onlineWaiting:
        return AppConstants.gpsIntervalOnlineWaiting;
      case GpsActivityState.idle:
        return AppConstants.gpsIntervalIdle;
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _emitOnce();
    _timer = Timer.periodic(_intervalForState, (_) => _emitOnce());
  }

  Future<void> _emitOnce() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: _state == GpsActivityState.activeTrip
            ? LocationAccuracy.best
            : LocationAccuracy.high,
      );
      if (!_controller.isClosed) {
        _controller.add(position);
      }
    } catch (_) {
      // Swallow transient errors (e.g. GPS momentarily unavailable in a
      // tunnel) — the Graceful Disconnection logic handles the gap.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
