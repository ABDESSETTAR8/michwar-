import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/transaction_model.dart';
import '../../../core/providers/app_providers.dart';
import '../../ride_engine/providers/ride_engine_providers.dart';
import '../services/driver_repository.dart';

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => DriverRepository(
    fs: ref.watch(firestoreProvider),
  ),
);

/// Demand-heatmap cells for the Driver Map Home overlay (Smart Driver
/// Tools: "Demand Heatmaps").
final heatmapProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(geohashServiceProvider).heatmapStream();
});

/// The signed-in driver's full wallet transaction ledger.
final walletTransactionsProvider = StreamProvider<List<TransactionModel>>((ref) {
  final uid = ref.watch(authStateProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(driverRepositoryProvider).watchWalletTransactions(uid);
});

/// The signed-in driver's ride-earning transactions (Earnings Dashboard).
final earningsProvider = StreamProvider<List<TransactionModel>>((ref) {
  final uid = ref.watch(authStateProvider).value;
  if (uid == null) return Stream.value(const []);
  return ref.watch(driverRepositoryProvider).watchEarnings(uid);
});
