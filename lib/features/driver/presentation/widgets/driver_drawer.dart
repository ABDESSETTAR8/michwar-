import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';

/// Navigation drawer for Driver Mode — quick access to earnings, wallet,
/// "Heading Home" settings, safety, and support.
class DriverDrawer extends ConsumerWidget {
  const DriverDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final driver = ref.watch(driverProfileProvider).value;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile?.fullName.isNotEmpty == true ? profile!.fullName : 'MICHWAR driver',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (driver != null)
                          Row(
                            children: [
                              Icon(
                                driver.isElite ? Icons.workspace_premium_rounded : Icons.star_outline_rounded,
                                color: AppColors.secondary,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                driver.isElite ? 'Elite driver' : 'Base driver',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded, color: AppColors.primary),
              title: const Text('Earnings'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.earningsDashboard);
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet'),
              subtitle: driver != null ? Text('${driver.walletBalance.toStringAsFixed(0)} DA') : null,
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.wallet);
              },
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Heading Home'),
              onTap: () {
                Navigator.pop(context);
                context.pushNamed(AppRoutes.headingHomeSettings);
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
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Switch to Passenger Mode'),
              onTap: () {
                Navigator.pop(context);
                context.goNamed(AppRoutes.passengerHome);
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
