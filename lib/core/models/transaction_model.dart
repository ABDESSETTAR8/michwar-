DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final str = value.toString();
  if (str.isEmpty) return null;
  return DateTime.tryParse(str);
}

/// Transaction category — distinguishes ride payouts from wallet top-ups
/// and SOS/admin adjustments.
enum TransactionType { rideEarning, walletTopUp, walletDeduction, adjustment }

TransactionType transactionTypeFromString(String? value) {
  switch (value) {
    case 'wallet_top_up':
      return TransactionType.walletTopUp;
    case 'wallet_deduction':
      return TransactionType.walletDeduction;
    case 'adjustment':
      return TransactionType.adjustment;
    default:
      return TransactionType.rideEarning;
  }
}

String transactionTypeToString(TransactionType type) {
  switch (type) {
    case TransactionType.walletTopUp:
      return 'wallet_top_up';
    case TransactionType.walletDeduction:
      return 'wallet_deduction';
    case TransactionType.adjustment:
      return 'adjustment';
    case TransactionType.rideEarning:
      return 'ride_earning';
  }
}

/// Maps to a record in the PocketBase `wallet_transactions` collection
/// (`pocketbase/pb_migrations/1700000006_wallet_transactions.js`). This is
/// the canonical financial ledger entry, written by the `/api/michwar/...`
/// hook routes (ride completion, wallet top-up). It clearly separates
/// `fareRevenue` (shared between driver & company) from `surchargeRevenue`
/// (100% company).
///
/// ```jsonc
/// wallet_transactions/{id} {
///   driver: relation -> users,
///   ride: relation -> rides | null,
///   passenger: relation -> users | null,
///   type: TransactionType,
///   baseFare: number,            // = fareRevenue (shared pool)
///   surchargeRevenue: number,    // 100% company
///   commissionRate: number,
///   commissionDeducted: number,  // commissionRate * baseFare
///   netPayoutToDriver: number,   // baseFare - commissionDeducted
///   companyRevenue: number,      // commissionDeducted + surchargeRevenue
///   walletBalanceAfter: number,
///   created, updated: ISO8601 string
/// }
/// ```
class TransactionModel {
  final String transactionId;
  final String? rideId;
  final String driverId;
  final String? passengerId;
  final TransactionType type;
  final double baseFare; // Fare_Revenue
  final double surchargeRevenue; // Surcharge_Revenue
  final double commissionRate;
  final double commissionDeducted;
  final double netPayoutToDriver;
  final double companyRevenue;
  final double walletBalanceAfter;
  final DateTime? createdAt;

  const TransactionModel({
    required this.transactionId,
    required this.driverId,
    required this.type,
    this.rideId,
    this.passengerId,
    this.baseFare = 0,
    this.surchargeRevenue = 0,
    this.commissionRate = 0,
    this.commissionDeducted = 0,
    this.netPayoutToDriver = 0,
    this.companyRevenue = 0,
    this.walletBalanceAfter = 0,
    this.createdAt,
  });

  factory TransactionModel.fromMap(String id, Map<String, dynamic> map) {
    final ride = map['ride'] as String?;
    final passenger = map['passenger'] as String?;
    return TransactionModel(
      transactionId: id,
      rideId: (ride == null || ride.isEmpty) ? null : ride,
      driverId: map['driver'] as String? ?? '',
      passengerId: (passenger == null || passenger.isEmpty) ? null : passenger,
      type: transactionTypeFromString(map['type'] as String?),
      baseFare: (map['baseFare'] as num?)?.toDouble() ?? 0,
      surchargeRevenue: (map['surchargeRevenue'] as num?)?.toDouble() ?? 0,
      commissionRate: (map['commissionRate'] as num?)?.toDouble() ?? 0,
      commissionDeducted: (map['commissionDeducted'] as num?)?.toDouble() ?? 0,
      netPayoutToDriver: (map['netPayoutToDriver'] as num?)?.toDouble() ?? 0,
      companyRevenue: (map['companyRevenue'] as num?)?.toDouble() ?? 0,
      walletBalanceAfter: (map['walletBalanceAfter'] as num?)?.toDouble() ?? 0,
      createdAt: _parseDate(map['created']),
    );
  }
}
