import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/firestore_paths.dart';
import '../models/user_model.dart';

/// Wraps Firebase Auth email+password auth and the `users` Firestore profile.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _fs;

  bool get isSignedIn => _auth.currentUser != null;
  String? get currentUserId => _auth.currentUser?.uid;

  /// Emits uid immediately, then on every sign-in/sign-out.
  Stream<String?> authStateChanges() =>
      _auth.authStateChanges().map((u) => u?.uid);

  /// Creates a Firebase Auth account and the matching `users` Firestore doc.
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;
    await _fs.collection(FsCollections.users).doc(uid).set({
      'email': email,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'role': 'passenger',
      'roleSelected': false,
      'loyaltyPoints': 0,
      'loyaltyTier': 'standard',
      'totalRidesCompleted': 0,
      'savedPlaces': [],
      'sosContacts': [],
      'fcmTokens': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signOut() => _auth.signOut();

  Future<void> requestPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  /// Fetches the `users/{uid}` Firestore profile once.
  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final doc =
          await _fs.collection(FsCollections.users).doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return UserModel.fromFirestore(doc.id, doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Live stream of the `users/{uid}` profile via Firestore snapshots.
  Stream<UserModel?> userProfileStream(String uid) {
    return _fs
        .collection(FsCollections.users)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists && doc.data() != null
            ? UserModel.fromFirestore(doc.id, doc.data()!)
            : null);
  }

  /// Partial update of the `users/{uid}` profile.
  Future<void> updateUserFields(String uid, Map<String, dynamic> fields) {
    return _fs.collection(FsCollections.users).doc(uid).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Role switch goes through the `switchRole` Cloud Function which also
  /// bootstraps `drivers` + `wallets` records on first activation.
  Future<void> switchRole(UserRole role) async {
    await _fs.collection(FsCollections.users).doc(currentUserId!).update({
      'role': userRoleToString(role),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
