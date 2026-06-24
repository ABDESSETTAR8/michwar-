import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/map_placeholder.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/ride_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import '../../../shared/presentation/widgets/sos_button.dart';
import '../../providers/driver_providers.dart';
import '../widgets/driver_drawer.dart';

/// "Main Map Home" for Driver Mode: a "Go Online/Offline" toggle, the
/// Demand Heatmap overlay (Smart Driver Tools), live wallet-balance status,
/// and an incoming-ride bottom sheet when a new request is matched to this
/// driver via Geohash proximity search.
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  double _currentLat = 36.7525; // Algiers fallback
  double _currentLng = 3.0420;
  StreamSubscription? _positionSub;
  bool _togglingOnline = false;
  String? _shownRequestId;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final granted = await locationService.requestPermission();
    if (granted) {
      final position = await locationService.getCurrentPosition();
      setState(() { _currentLat = position.latitude; _currentLng = position.longitude; });
    }
  }

  Future<void> _toggleOnline(bool goOnline, String driverId) async {
    setState(() => _togglingOnline = true);
    final locationService = ref.read(locationServiceProvider);

    try {
      if (goOnline) {
        final granted = await locationService.requestPermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required to go online.')),
            );
          }
          return;
        }

        await ref.read(driverRepositoryProvider).setOnlineStatus(driverId, true);

        locationService.setActivityState(GpsActivityState.onlineWaiting);
        locationService.start();
        _positionSub ??= locationService.positionStream.listen((position) {
          ref.read(geohashServiceProvider).updateDriverLocation(
                driverId: driverId,
                lat: position.latitude,
                lng: position.longitude,
                heading: position.heading,
                speed: position.speed,
              );
          if (mounted) {
            setState(() { _currentLat = position.latitude; _currentLng = position.longitude; });
          }
        });
      } else {
        await ref.read(driverRepositoryProvider).setOnlineStatus(driverId, false);
        locationService.setActivityState(GpsActivityState.idle);
        _positionSub?.cancel();
        _positionSub = null;
        locationService.stop();
      }
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  Future<void> _acceptRide(RideModel ride, String driverId) async {
    try {
      await ref.read(rideRepositoryProvider).acceptRide(ride.id, driverId);
      if (mounted) {
        Navigator.of(context).maybePop(); // close the incoming-ride sheet
        context.pushNamed(AppRoutes.driverActiveRide, pathParameters: {'rideId': ride.id});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept ride: $e')),
        );
      }
    }
  }

  void _maybeShowIncomingRide(RideModel ride, String driverId) {
    if (_shownRequestId == ride.id) return;
    _shownRequestId = ride.id;

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _IncomingRideSheet(
        ride: ride,
        onAccept: () => _acceptRide(ride, driverId),
        onDecline: () => Navigator.of(ctx).pop(),
      ),
    ).whenComplete(() {
      if (_shownRequestId == ride.id) _shownRequestId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final driverAsync = ref.watch(driverProfileProvider);
    final driver = driverAsync.value;
    final uid = ref.watch(authStateProvider).value;
    // heatmap data is fetched but map display is disabled (Maps API unavailable).
    ref.watch(heatmapProvider);

    ref.listen(incomingRequestsProvider, (prev, next) {
      if (uid == null || driver == null || !driver.isOnline || driver.isOnTrip) return;
      final rides = next.value ?? const [];
      if (rides.isNotEmpty) {
        _maybeShowIncomingRide(rides.first, uid);
      }
    });

    final isOnline = driver?.isOnline ?? false;
    final lowBalance = driver != null &&
        driver.walletBalance <= AppConstants.walletLowBalanceThresholdDzd;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const DriverDrawer(),
      body: Stack(
        children: [
          const MapPlaceholder(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const SizedBox(width: 12),
                  if (lowBalance)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.pushNamed(AppRoutes.wallet),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Low wallet balance — top up to keep receiving rides',
                                  style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  const SosButton(compact: true),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? AppColors.online : AppColors.offline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? "You're online" : "You're offline",
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (driver != null)
                              Text(
                                'Wallet: ${Formatters.currency(driver.walletBalance)} · ${driver.isElite ? 'Elite' : 'Base'} tier',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                      _togglingOnline
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch(
                              value: isOnline,
                              activeColor: AppColors.online,
                              onChanged: uid == null ? null : (value) => _toggleOnline(value, uid),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _heatColor(int count) {
    if (count >= 10) return AppColors.heatmapGradient[3];
    if (count >= 5) return AppColors.heatmapGradient[2];
    if (count >= 2) return AppColors.heatmapGradient[1];
    return AppColors.heatmapGradient[0];
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Bottom sheet shown to a driver when a new ride request is matched to
/// them (Driver Mode: "Ride Request (Incoming)"). Auto-dismisses (declines)
/// after a short countdown if the driver doesn't respond.
class _IncomingRideSheet extends StatefulWidget {
  const _IncomingRideSheet({required this.ride, required this.onAccept, required this.onDecline});

  final RideModel ride;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<_IncomingRideSheet> createState() => _IncomingRideSheetState();
}

class _IncomingRideSheetState extends State<_IncomingRideSheet> {
  late int _secondsLeft = 15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        widget.onDecline();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('New ride request', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              Text('${_secondsLeft}s', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: 16),
          _RideAddressRow(icon: Icons.my_location_rounded, color: AppColors.primary, address: ride.pickup.address ?? 'Pickup location'),
          const SizedBox(height: 8),
          _RideAddressRow(icon: Icons.flag_rounded, color: AppColors.danger, address: ride.dropoff.address ?? 'Destination'),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.route_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(Formatters.distanceKm(ride.estimate.distanceKm)),
              const SizedBox(width: 16),
              const Icon(Icons.payments_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(Formatters.currency(ride.estimate.fareEstimate)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(48)),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: widget.onAccept,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RideAddressRow extends StatelessWidget {
  const _RideAddressRow({required this.icon, required this.color, required this.address});

  final IconData icon;
  final Color color;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
