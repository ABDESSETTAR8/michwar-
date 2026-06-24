import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';

/// Help & Support — FAQ accordion plus direct contact channels (phone,
/// email, in-app chat placeholder) and a shortcut to safety settings.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  static const _faqs = [
    (
      'How is my fare calculated?',
      'Your fare is based on the distance and time of your trip, plus a small platform surcharge '
          '(1-4 DZD). The fare estimate shown before booking may vary slightly from the final fare, '
          'which is calculated by our servers using your actual route.',
    ),
    (
      'How do MICHWAR Points work?',
      'You earn 2 points for every 100 DZD spent on completed rides. Points unlock perks: 50 points '
          'gives you an Eco-ride discount, and 200 points unlocks Premium tier access.',
    ),
    (
      'What should I do in an emergency?',
      'Tap the red SOS button visible during any ride. This shares your live location and ride '
          'details with our safety team and your emergency contacts (set these up under '
          '"Safety & SOS contacts").',
    ),
    (
      'How do I cancel a ride?',
      'While a ride is being matched or before the driver arrives, open the active ride screen and '
          'tap "Cancel ride". Frequent cancellations may affect your account standing.',
    ),
    (
      'How do driver payouts and commission work?',
      'Drivers keep 85% of the base fare (Tier 1). Drivers who complete 100+ rides with a 4.0+ '
          'average rating are upgraded to Elite (Tier 2) and keep 93%. The 1-4 DZD platform surcharge '
          'is not shared and goes entirely to MICHWAR.',
    ),
    (
      'How does the driver wallet work?',
      'Drivers maintain a pre-paid wallet used to cover commission on completed rides. If the '
          'balance falls to or below 200 DA, new ride requests are paused until the driver tops up.',
    ),
  ];

  Future<void> _call(BuildContext context) async {
    final uri = Uri.parse('tel:+213800000000');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _email(BuildContext context) async {
    final uri = Uri.parse('mailto:support@michwar.dz?subject=MICHWAR%20Support%20Request');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent_rounded, color: Colors.white, size: 32),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Need help with a ride, payment, or your account? Browse the FAQs below or contact us directly.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ContactButton(
                  icon: Icons.call_outlined,
                  label: 'Call support',
                  onTap: () => _call(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ContactButton(
                  icon: Icons.email_outlined,
                  label: 'Email us',
                  onTap: () => _email(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.shield_outlined, color: AppColors.danger),
              title: const Text('Safety & SOS contacts'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.pushNamed(AppRoutes.sosContacts),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Frequently asked questions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          ...(_faqs.map((faq) => _FaqTile(question: faq.$1, answer: faq.$2))),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.topLeft,
        children: [
          Text(answer, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
