import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';

// ── Demo account presets (same list as login_screen.dart) ─────────────────

class _DemoAccount {
  const _DemoAccount(this.label, this.icon, this.email, this.password);
  final String label;
  final IconData icon;
  final String email;
  final String password;
}

const _demoAccounts = [
  _DemoAccount(
    'Passenger',
    Icons.directions_walk_rounded,
    'demo.passenger@michwar.dz',
    'Demo@1234',
  ),
  _DemoAccount(
    'Driver',
    Icons.local_taxi_rounded,
    'demo.driver@michwar.dz',
    'Demo@1234',
  ),
];

// ── Welcome screen ─────────────────────────────────────────────────────────

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  bool _demoLoading = false;
  String? _demoError;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.7));
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _signInDemo(_DemoAccount demo) async {
    setState(() {
      _demoLoading = true;
      _demoError = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(
            email: demo.email,
            password: demo.password,
          );
      // GoRouter redirect will navigate automatically on auth state change.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _demoLoading = false;
        _demoError = e.code == 'user-not-found' || e.code == 'invalid-credential'
            ? 'Demo accounts not seeded yet. Run scripts/seed_demo_accounts.js first.'
            : (e.message ?? 'Sign-in failed.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _demoLoading = false;
        _demoError = 'Something went wrong. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Background gradient ────────────────────────────────────
          Container(
            width: size.width,
            height: size.height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.55, 1],
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                  Color(0xFF0E7A60),
                ],
              ),
            ),
          ),

          // ── Decorative circles ─────────────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            bottom: size.height * 0.3,
            left: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: SizedBox(
                    height: size.height -
                        MediaQuery.paddingOf(context).top -
                        MediaQuery.paddingOf(context).bottom,
                    child: Column(
                      children: [
                        const Spacer(flex: 2),

                        // Logo
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_car_filled_rounded,
                            size: 58,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'MICHWAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Fast, safe and affordable rides\nacross Algeria — as a passenger or a driver.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            height: 1.55,
                          ),
                        ),

                        const Spacer(flex: 2),

                        // ── Feature pills ──────────────────────────
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: const [
                            _FeaturePill(Icons.bolt_rounded, 'Fast matching'),
                            _FeaturePill(Icons.shield_outlined, 'Safe rides'),
                            _FeaturePill(Icons.star_border_rounded, 'Loyalty rewards'),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // ── Demo accounts section ──────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.play_circle_outline,
                                      size: 16, color: Colors.white70),
                                  SizedBox(width: 6),
                                  Text(
                                    'Try a demo account — one tap',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_demoLoading)
                                const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: _demoAccounts.map((demo) {
                                    return ActionChip(
                                      avatar: Icon(demo.icon,
                                          size: 16, color: AppColors.primary),
                                      label: Text(
                                        demo.label,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      backgroundColor: Colors.white,
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      onPressed: () => _signInDemo(demo),
                                    );
                                  }).toList(),
                                ),
                              if (_demoError != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _demoError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── CTA buttons ────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1_rounded,
                                size: 20),
                            label: const Text(
                              'Create an account',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            onPressed: _demoLoading
                                ? null
                                : () => context.goNamed(AppRoutes.signup),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                  color: Colors.white54, width: 1),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _demoLoading
                                ? null
                                : () => context.goNamed(AppRoutes.login),
                            child: const Text(
                              'I already have an account',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Text(
                          'By continuing you agree to MICHWAR\'s Terms of Service and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
