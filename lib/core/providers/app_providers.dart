import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/firestore_paths.dart';
import '../models/driver_model.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';

// ── Singleton Firebase instances ──────────────────────────────────────────

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (_) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (_) => FirebaseFirestore.instance,
);

// ── Service providers ─────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
  );
});

final notificationServiceProvider =
    Provider<NotificationService>((ref) => const NotificationService());

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.dispose);
  return service;
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

// ── Auth / profile streams ────────────────────────────────────────────────

/// The signed-in user's uid, or `null` when signed out.
final authStateProvider = StreamProvider<String?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// Live `users/{uid}` profile from Firestore.
final userProfileProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull;
  if (uid == null) return Stream.value(null);
  return ref.watch(authServiceProvider).userProfileStream(uid);
});

/// Live `drivers` doc where `userId == uid`.
final driverProfileProvider = StreamProvider<DriverModel?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull;
  if (uid == null) return Stream.value(null);
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection(FsCollections.drivers)
      .where('userId', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return DriverModel.fromFirestore(doc.id, doc.data());
  });
});

/// Live `wallets` doc where `driverId == uid`.
final walletProvider = StreamProvider<WalletModel?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull;
  if (uid == null) return Stream.value(null);
  final fs = ref.watch(firestoreProvider);
  return fs
      .collection(FsCollections.wallets)
      .where('driverId', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return WalletModel.fromFirestore(doc.id, doc.data());
  });
});

/// Active role — defaults to passenger until profile loads.
final activeRoleProvider = Provider<UserRole>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return profile?.role ?? UserRole.passenger;
});

// ── Connectivity ──────────────────────────────────────────────────────────
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.connectivityStream;
});
