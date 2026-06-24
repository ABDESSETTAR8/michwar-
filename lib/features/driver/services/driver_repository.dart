import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/models/driver_model.dart';
import '../../../core/models/transaction_model.dart';

/// Driver-specific Firestore operations: going online/offline, Heading Home
/// toggle, and the pre-paid wallet.
class DriverRepository {
  DriverRepository({FirebaseFirestore? fs, FirebaseFunctions? functions})
      : _fs = fs ?? FirebaseFirestore.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _fs;
  final FirebaseFunctions _fn;

  CollectionReference get _drivers =>
      _fs.collection(FsCollections.drivers);
  CollectionReference get _walletTx =>
      _fs.collection(FsCollections.walletTransactions);

  /// Returns the `drivers` doc id for this user.
  Future<String> _driverDocId(String userId) async {
    final snap = await _drivers
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) throw Exception('No driver record for user $userId');
    return snap.docs.first.id;
  }

  Future<void> setOnlineStatus(String userId, bool isOnline) async {
    final dId = await _driverDocId(userId);
    await _drivers.doc(dId).update({'isOnline': isOnline});
  }

  Future<void> updateHeadingHome(
      String userId, HeadingHomeSettings settings) async {
    final dId = await _driverDocId(userId);
    await _drivers.doc(dId).update(settings.toMap());
  }

  Future<double> topUpWallet({required double amountDzd}) async {
    final result = await _fn
        .httpsCallable(FsFunctions.topUpWallet)
        .call({'amountDzd': amountDzd});
    return (result.data['newBalance'] as num).toDouble();
  }

  /// Live stream of wallet transactions, most recent first.
  Stream<List<TransactionModel>> watchWalletTransactions(String userId,
      {int limit = 50}) {
    return _walletTx
        .where('driverId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) =>
                TransactionModel.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList());
  }

  Stream<List<TransactionModel>> watchEarnings(String userId,
      {int limit = 100}) {
    return _walletTx
        .where('driverId', isEqualTo: userId)
        .where('type', isEqualTo: 'ride_earning')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) =>
                TransactionModel.fromMap(d.id, d.data() as Map<String, dynamic>))
            .toList());
  }
}
