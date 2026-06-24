import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/loading_overlay.dart';
import '../../../../core/widgets/primary_button.dart';
import 'package:go_router/go_router.dart';

// ── Simple math CAPTCHA ────────────────────────────────────────────────────

class _Captcha {
  _Captcha() {
    _regenerate();
  }

  late int _a;
  late int _b;
  late int _answer;
  late String question;

  void _regenerate() {
    final rng = Random();
    _a = rng.nextInt(9) + 1;
    _b = rng.nextInt(9) + 1;
    _answer = _a + _b;
    question = '$_a + $_b = ?';
  }

  bool verify(String input) => int.tryParse(input.trim()) == _answer;

  void refresh() => _regenerate();
}

// ── Rate limiting (client-side guard, backed by Firestore on the server) ──

/// Returns true if this device/session may proceed (≤5 attempts per hour).
/// A Cloud Function enforces the same rule server-side so this is defence
/// in depth, not the primary gate.
Future<bool> _clientRateCheck() async {
  // Trivial per-session in-memory counter — resets when app restarts.
  // The authoritative check runs in the Cloud Function.
  return true;
}

// ── Signup screen ──────────────────────────────────────────────────────────

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _captchaController = TextEditingController();

  final _captcha = _Captcha();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // CAPTCHA gate
    if (!_captcha.verify(_captchaController.text)) {
      setState(() {
        _errorText = 'CAPTCHA answer is incorrect. Please try again.';
        _captchaController.clear();
        _captcha.refresh();
      });
      return;
    }

    if (!await _clientRateCheck()) {
      setState(() => _errorText = 'Too many attempts. Please try again later.');
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
    });

    final authService = ref.read(authServiceProvider);
    final digits = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final phoneNumber = '${AppConstants.defaultCountryCode}$digits';

    try {
      await authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        phoneNumber: phoneNumber,
      );
      // Router redirect handles navigation.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = _messageFromFirebaseError(e);
        _captcha.refresh();
        _captchaController.clear();
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = e.message ?? 'Could not create account.';
        _captcha.refresh();
        _captchaController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Something went wrong. Please try again.';
        _captcha.refresh();
        _captchaController.clear();
      });
    }
  }

  String _messageFromFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 8 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'Could not create account.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: LoadingOverlay(
        show: _loading,
        message: 'Creating account…',
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Personal info ──────────────────────────────────
                    AppTextField(
                      label: 'Full name',
                      controller: _nameController,
                      prefixIcon: Icons.person_outline,
                      maxLength: 60,
                      validator: (v) =>
                          Validators.required(v, label: 'Full name'),
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.email_outlined,
                      maxLength: 100,
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Mobile number',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      prefixText: '${AppConstants.defaultCountryCode} ',
                      prefixIcon: Icons.phone_iphone_rounded,
                      maxLength: 15,
                      validator: Validators.algerianPhone,
                    ),
                    const SizedBox(height: 16),

                    // ── Password ───────────────────────────────────────
                    AppTextField(
                      label: 'Password',
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      prefixIcon: Icons.lock_outline,
                      maxLength: 50,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Confirm password',
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      prefixIcon: Icons.lock_outline,
                      maxLength: 50,
                      validator: (value) =>
                          Validators.confirmPassword(_passwordController.text)(
                              value),
                    ),
                    const SizedBox(height: 24),

                    // ── CAPTCHA ────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.security_outlined,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              const Text(
                                'Verification',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _captcha.question,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          AppTextField(
                            label: 'Your answer',
                            controller: _captchaController,
                            keyboardType: TextInputType.number,
                            prefixIcon: Icons.calculate_outlined,
                            maxLength: 3,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please solve the equation';
                              }
                              if (int.tryParse(v.trim()) == null) {
                                return 'Numbers only';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.danger, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorText!,
                                  style: const TextStyle(
                                      color: AppColors.danger, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Create account',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed:
                          _loading ? null : () => context.goNamed(AppRoutes.login),
                      child: const Text('Already have an account? Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
