import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../../../../core/models/driver_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/driver_providers.dart';

/// "Heading Home" settings (Smart Driver Tools). When enabled, the matching
/// engine prefers ride requests whose drop-off is roughly along the
/// driver's route home — helping drivers pick up one last ride on their
/// way back.
class HeadingHomeSettingsScreen extends ConsumerStatefulWidget {
  const HeadingHomeSettingsScreen({super.key});

  @override
  ConsumerState<HeadingHomeSettingsScreen> createState() => _HeadingHomeSettingsScreenState();
}

class _HeadingHomeSettingsScreenState extends ConsumerState<HeadingHomeSettingsScreen> {
  final _addressController = TextEditingController();
  bool _saving = false;
  bool? _localEnabled;
  double? _destinationLat;
  double? _destinationLng;
  double _tolerance = 30;
  bool _initialized = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _initFromDriver(DriverModel driver) {
    if (_initialized) return;
    _initialized = true;
    _localEnabled = driver.headingHome.enabled;
    _destinationLat = driver.headingHome.destinationLat;
    _destinationLng = driver.headingHome.destinationLng;
    _tolerance = driver.headingHome.bearingToleranceDeg;
  }

  Future<void> _useCurrentLocation() async {
    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      setState(() {
        _destinationLat = position.latitude;
        _destinationLng = position.longitude;
      });
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        _addressController.text = [p.street, p.locality].where((s) => s != null && s.isNotEmpty).join(', ');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get current location: $e')));
      }
    }
  }

  Future<void> _searchAddress() async {
    final query = _addressController.text.trim();
    if (query.isEmpty) return;
    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        setState(() {
          _destinationLat = locations.first.latitude;
          _destinationLng = locations.first.longitude;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Home location set.')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address not found.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  Future<void> _save(String driverId) async {
    setState(() => _saving = true);
    try {
      await ref.read(driverRepositoryProvider).updateHeadingHome(
            driverId,
            HeadingHomeSettings(
              enabled: _localEnabled ?? false,
              destinationLat: _destinationLat,
              destinationLng: _destinationLng,
              bearingToleranceDeg: _tolerance,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Heading Home settings saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverAsync = ref.watch(driverProfileProvider);
    final uid = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Heading Home')),
      body: driverAsync.when(
        data: (driver) {
          if (driver == null || uid == null) {
            return const Center(child: Text('Driver profile not found.'));
          }
          _initFromDriver(driver);
          final enabled = _localEnabled ?? false;
          final hasDestination = _destinationLat != null && _destinationLng != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  activeColor: AppColors.primary,
                  title: const Text('Enable Heading Home', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                    'Prioritize ride requests heading toward your home location, so you can pick up one last trip on your way.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  onChanged: (value) => setState(() => _localEnabled = value),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Home location', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  hintText: 'Enter your home address',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search_rounded),
                    onPressed: _searchAddress,
                  ),
                ),
                onSubmitted: (_) => _searchAddress(),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: 8),
              if (hasDestination)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.home_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Home set: ${_destinationLat!.toStringAsFixed(5)}, ${_destinationLng!.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                  'No home location set yet.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              const SizedBox(height: 24),
              const Text('Matching tolerance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'Only show ride requests whose drop-off is within ${_tolerance.round()}° of your direction home.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Slider(
                value: _tolerance,
                min: 10,
                max: 90,
                divisions: 16,
                activeColor: AppColors.primary,
                label: '${_tolerance.round()}°',
                onChanged: (value) => setState(() => _tolerance = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || !hasDestination ? null : () => _save(uid),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save settings'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
