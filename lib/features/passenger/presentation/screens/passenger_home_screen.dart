import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/map_placeholder.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ride_engine/providers/ride_engine_providers.dart';
import '../../../shared/presentation/widgets/sos_button.dart';
import '../widgets/passenger_drawer.dart';

/// "Main Map Home" for Passenger Mode: interactive map centered on the
/// user's location, showing nearby available drivers, with a "Where to?"
/// search bar that starts the Ride Request Flow.
class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Algiers coordinates used for geohash driver queries even without live map.
  double _currentLat = 36.7525;
  double _currentLng = 3.0420;
  int _nearbyCount = 0;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final locationService = ref.read(locationServiceProvider);
    final granted = await locationService.requestPermission();
    if (granted) {
      final position = await locationService.getCurrentPosition();
      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
        _locating = false;
      });
      _loadNearbyDrivers();
    } else {
      setState(() => _locating = false);
    }
  }

  Future<void> _loadNearbyDrivers() async {
    final nearby = await ref.read(geohashServiceProvider).findNearbyOnlineDrivers(
          lat: _currentLat,
          lng: _currentLng,
        );
    if (!mounted) return;
    setState(() => _nearbyCount = nearby.length);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const PassengerDrawer(),
      body: Stack(
        children: [
          const MapPlaceholder(),
          if (_locating)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.menu_rounded,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const Spacer(),
                  Text(
                    'Hi, ${profile?.fullName.split(' ').first ?? 'there'} 👋',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      backgroundColor: AppColors.surface,
                    ),
                  ),
                  const Spacer(),
                  const SosButton(compact: true),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _WhereToCard(
              onTap: () => context.pushNamed(AppRoutes.destinationSearch),
            ),
          ),
        ],
      ),
    );
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

class _WhereToCard extends StatelessWidget {
  const _WhereToCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.primary),
              SizedBox(width: 12),
              Text(
                'Where to?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
