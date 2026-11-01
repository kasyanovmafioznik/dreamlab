import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/dto/api_models.dart';
import '../../subscription/bloc/subscription_bloc.dart';

/// Mock purchase flow: no billing, one POST to the server.
/// Dismisses itself once the server confirms premium.
Future<void> showPaywallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const PaywallSheet(),
  );
}

class PaywallSheet extends StatelessWidget {
  const PaywallSheet({super.key});

  static const _benefits = [
    (Icons.movie_filter, 'Cinematic, Cyberpunk & Watercolor styles'),
    (Icons.aspect_ratio, 'Cinema 21:9 aspect ratio'),
    (Icons.high_quality, 'HD (2048px) and 4K (4096px) quality'),
    (Icons.all_inclusive, 'Unlimited generations'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SubscriptionBloc>().state;

    // Server confirmed premium → close; the generate flow re-runs automatically
    // because the pending options are still selected.
    if (state.tier == SubscriptionTier.premium && !state.isUpgrading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 28,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Amber PRO badge.
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.25),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 34,
                color: AppColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Unlock DreamLab Pro',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Premium options are validated on the server\nand require an active subscription.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 24),
          for (final (icon, text) in _benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 17, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (state.failure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                state.failure!.message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.danger),
              ),
            ),
          GradientButton(
            colors: AppColors.goldGradient.colors,
            onPressed: state.isUpgrading
                ? null
                : () => context.read<SubscriptionBloc>().add(
                    const SubscriptionUpgradeRequested(),
                  ),
            child: state.isUpgrading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF78350F),
                    ),
                  )
                : const Text(
                    'Upgrade — \$4.99 / month',
                    style: TextStyle(color: Color(0xFF78350F)),
                  ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: state.isUpgrading
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Maybe later'),
          ),
          const SizedBox(height: 2),
          const Text(
            'Mock purchase: no real payment is processed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
