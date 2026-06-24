import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/transaction_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../providers/driver_providers.dart';

/// Driver "Earnings Dashboard" — daily / weekly / all-time totals computed
/// from the `transactions` ledger (type == rideEarning), plus a recent
/// trip-by-trip breakdown showing the commission split (Section 6).
class EarningsDashboardScreen extends ConsumerWidget {
  const EarningsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: earningsAsync.when(
        data: (transactions) => _buildBody(context, transactions),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TransactionModel> transactions) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

    double todayTotal = 0;
    double weekTotal = 0;
    double allTimeTotal = 0;
    int todayRides = 0;
    int weekRides = 0;

    for (final tx in transactions) {
      allTimeTotal += tx.netPayoutToDriver;
      final created = tx.createdAt;
      if (created == null) continue;
      if (!created.isBefore(weekStart)) {
        weekTotal += tx.netPayoutToDriver;
        weekRides += 1;
      }
      if (!created.isBefore(todayStart)) {
        todayTotal += tx.netPayoutToDriver;
        todayRides += 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Today',
                amount: todayTotal,
                subtitle: '$todayRides ${todayRides == 1 ? 'ride' : 'rides'}',
                highlight: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                label: 'This week',
                amount: weekTotal,
                subtitle: '$weekRides ${weekRides == 1 ? 'ride' : 'rides'}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(label: 'All-time net earnings', amount: allTimeTotal, subtitle: '${transactions.length} completed rides'),
        const SizedBox(height: 24),
        const Text('Recent trips', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('No completed rides yet.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else
          ...transactions.map((tx) => _EarningRow(transaction: tx)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.amount, required this.subtitle, this.highlight = false});

  final String label;
  final double amount;
  final String subtitle;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: highlight ? Colors.white70 : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Formatters.currency(amount),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: highlight ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: highlight ? Colors.white70 : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EarningRow extends StatelessWidget {
  const _EarningRow({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
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
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_car_filled_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Formatters.currency(transaction.netPayoutToDriver),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Fare ${Formatters.currency(transaction.baseFare)} · commission ${(transaction.commissionRate * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (transaction.createdAt != null)
            Text(
              Formatters.dateTime(transaction.createdAt!),
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
