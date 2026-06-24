import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/transaction_model.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../providers/driver_providers.dart';

/// Driver "Wallet" screen — shows the pre-paid commission wallet balance
/// (Section 6.C), lets the driver top up, and lists the transaction
/// ledger (top-ups, ride-earning deductions, adjustments).
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _toppingUp = false;

  Future<void> _topUp(double amount) async {
    setState(() => _toppingUp = true);
    try {
      await ref.read(driverRepositoryProvider).topUpWallet(amountDzd: amount);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallet topped up by ${Formatters.currency(amount)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Top-up failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }

  void _showTopUpSheet() {
    const amounts = [500.0, 1000.0, 2000.0, 5000.0];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Top up wallet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'In production this opens a payment provider (e.g. CIB/Edahabia card or Baridimob). '
              'For testing, tapping an amount credits your wallet immediately via the topUpWallet Cloud Function.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ...amounts.map(
              (amount) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _topUp(amount);
                  },
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text('+ ${Formatters.currency(amount)}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(driverProfileProvider).value;
    final transactionsAsync = ref.watch(walletTransactionsProvider);
    final balance = driver?.walletBalance ?? 0;
    final lowBalance = balance <= AppConstants.walletLowBalanceThresholdDzd;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Wallet balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  Formatters.currency(balance),
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                if (lowBalance) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Balance is low — top up to keep receiving ride requests.',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _toppingUp ? null : _showTopUpSheet,
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primaryDark),
                    child: _toppingUp
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Top up'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: const [
                Text('Transaction history', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: transactionsAsync.when(
              data: (transactions) {
                if (transactions.isEmpty) {
                  return const Center(
                    child: Text('No transactions yet.', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) => _TransactionRow(transaction: transactions[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.type == TransactionType.walletTopUp;
    final isDeduction = transaction.type == TransactionType.walletDeduction ||
        transaction.type == TransactionType.rideEarning;

    final double amount = switch (transaction.type) {
      TransactionType.walletTopUp => transaction.walletBalanceAfter == 0 ? 0 : transaction.netPayoutToDriver,
      TransactionType.rideEarning => transaction.netPayoutToDriver,
      TransactionType.walletDeduction => transaction.commissionDeducted,
      TransactionType.adjustment => transaction.netPayoutToDriver,
    };

    final (label, icon, color) = switch (transaction.type) {
      TransactionType.walletTopUp => ('Wallet top-up', Icons.add_circle_outline_rounded, AppColors.success),
      TransactionType.rideEarning => ('Ride earning', Icons.directions_car_filled_rounded, AppColors.primary),
      TransactionType.walletDeduction => ('Commission deduction', Icons.remove_circle_outline_rounded, AppColors.danger),
      TransactionType.adjustment => ('Adjustment', Icons.tune_rounded, AppColors.textSecondary),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (transaction.createdAt != null)
                  Text(
                    Formatters.dateTime(transaction.createdAt!),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : isDeduction ? '-' : ''}${Formatters.currency(amount.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isCredit ? AppColors.success : (isDeduction ? AppColors.danger : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
