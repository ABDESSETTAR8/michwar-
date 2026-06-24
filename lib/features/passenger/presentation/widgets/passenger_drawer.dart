import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';

/// Navigation drawer for Passenger Mode — quick access to the profile,
/// MICHWAR Points / Loyalty Dashboard, ride history, safety settings, and
/// support, plus the ability to switch to Driver Mode if the account also
/// holds a driver profile.
class PassengerDrawer extends ConsumerWidget {
  const PassengerDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    // Avatar is stored as a direct download URL in Firestore (Firebase Storage).
    final avatarUrl = profile?.avatar?.isNotEmpty == true ? profile!.avatar : null;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, color: AppColors.primary, size: 28)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile?.fullName.isNotEmpty == true
                              ? profile!.fullName
                              : 'MICHWAR rider',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.phoneNumber ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.star_rounded, color: AppColors.secondary),
              title: const Text('MICHWAR Points'),
              subtitle: Text('${profile?.loyalty.points ?? 0} pts · ${profile?.loyalty.tier ?? 'standard'}'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.loyaltyDashboard);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Safety & SOS contacts'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.sosContacts);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('Support'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.support);
              },
            ),
            if (profile?.role.name == 'driver')
              ListTile(
                leading: const Icon(Icons.local_taxi_outlined),
                title: const Text('Switch to Driver Mode'),
                onTap: () {
                  Navigator.pop(context);
                  context.goNamed(AppRoutes.driverHome);
                },
              ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
              title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
