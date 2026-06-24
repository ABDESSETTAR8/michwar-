DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
}

/// Maps to a record in the PocketBase `wallets` collection
/// (`pocketbase/pb_migrations/1700000005_wallets.js`). This is the
/// **pre-paid commission wallet** described in Section 6.C — only the
/// hook routes in `pocketbase/pb_hooks/` may mutate `balance` (the
/// `wallets` API rules are write-locked for clients).
///
/// ```jsonc
/// wallets/{id} {
///   driver: relation -> users,   // the driver's user id
///   balance: number,
///   lowBalance: boolean,         // balance <= walletLowBalanceThresholdDzd
///   lastTopUpAt: string | null,  // ISO8601
///   lastDeductionAt: string | null,
///   created, updated: ISO8601 string
/// }
/// ```
class WalletModel {
  final String driverId;
  final double balance;
  final bool lowBalance;
  final DateTime? lastTopUpAt;
  final DateTime? lastDeductionAt;

  const WalletModel({
    required this.driverId,
    required this.balance,
    this.lowBalance = false,
    this.lastTopUpAt,
    this.lastDeductionAt,
  });

  factory WalletModel.fromMap(String driverId, Map<String, dynamic> map) {
    return WalletModel(
      driverId: map['driverId'] as String? ?? driverId,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      lowBalance: map['lowBalance'] as bool? ?? false,
      lastTopUpAt: _parseDate(map['lastTopUpAt']),
      lastDeductionAt: _parseDate(map['lastDeductionAt']),
    );
  }

  factory WalletModel.fromFirestore(String id, Map<String, dynamic> map) =>
      WalletModel.fromMap(id, map);
}
