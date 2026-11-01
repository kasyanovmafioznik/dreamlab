import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Primary CTA with an indigo gradient (used for Generate and Upgrade).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.colors = const [AppColors.indigo, AppColors.violet],
  });

  final VoidCallback? onPressed;
  final Widget child;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Container(
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: colors) : null,
        color: enabled ? null : AppColors.surfaceHighest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: AppColors.textMuted,
          shadowColor: Colors.transparent,
          elevation: 0,
        ),
        onPressed: onPressed,
        child: child,
      ),
    );
  }
}

/// Small uppercase section label with a gradient tick — option group headers.
class NeonSectionLabel extends StatelessWidget {
  const NeonSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.indigo, AppColors.violet],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Soft pastel washes behind hero cards (empty state, progress) —
/// radial gradients fade out naturally, no blur filter needed.
class AuroraBlobs extends StatelessWidget {
  const AuroraBlobs({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // Blobs are painted first (behind the content).
          Positioned(
            top: -60,
            left: -40,
            child: _blob(220, AppColors.indigo.withValues(alpha: 0.10)),
          ),
          Positioned(
            bottom: -80,
            right: -50,
            child: _blob(260, AppColors.cyan.withValues(alpha: 0.08)),
          ),
          Positioned(
            top: 40,
            right: -30,
            child: _blob(140, AppColors.pink.withValues(alpha: 0.07)),
          ),
          // Non-positioned child defines the Stack size (unbounded ListView
          // context would break an all-positioned Stack).
          child,
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );
}
