import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/user_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/loading_overlay.dart';

/// Shown exactly once, right after a brand-new user signs up. Lets them
/// choose whether MICHWAR should open in Passenger or Driver mode by
/// default (Section: "Role Selection/Detection").
///
/// Selecting "Driver" calls `POST /api/michwar/role`
/// (`pocketbase/pb_hooks/11_drivers.pb.js`), which sets `users.role` and
/// lazily creates the companion `drivers` and `wallets` records (with the
/// welcome credit). The router then redirects to the Document Upload
/// portal, since new drivers must pass compliance verification before
/// going online.
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  bool _loading = false;

  Future<void> _selectRole(UserRole role) async {
    final uid = ref.read(authStateProvider).value;
    if (uid == null) return;

    setState(() => _loading = true);

    final authService = ref.read(authServiceProvider);
    if (role == UserRole.driver) {
      // Sets role='driver', roleSelected=true, and bootstraps the
      // drivers/wallets records server-side.
      await authService.switchRole(role);
    } else {
      // Already 'passenger' by default — just mark selection as done.
      await authService.updateUserFields(uid, {'roleSelected': true});
    }
    // Router redirect handles navigation once userProfileProvider emits the
    // updated role/roleSelected.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoadingOverlay(
        show: _loading,
        message: 'Setting up your account…',
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                const Text(
                  'How will you use MICHWAR?',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can change this later from Settings.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                _RoleCard(
                  title: 'I need a ride',
                  subtitle: 'Book trips, track drivers in real time, and '
                      'earn MICHWAR Points.',
                  icon: Icons.person_pin_circle_rounded,
                  color: AppColors.primary,
                  onTap: _loading ? null : () => _selectRole(UserRole.passenger),
                ),
                const SizedBox(height: 16),
                _RoleCard(
                  title: 'I want to drive',
                  subtitle: 'Earn money on your schedule. Requires document '
                      'verification (license, Carte Grise, insurance...).',
                  icon: Icons.local_taxi_rounded,
                  color: AppColors.secondary,
                  onTap: _loading ? null : () => _selectRole(UserRole.driver),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
