import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../bloc/generate_bloc.dart';
import '../widgets/generate_widgets.dart';
import 'paywall_sheet.dart';

class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _promptController = TextEditingController();
  bool _promptFocused = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GenerateBloc, GenerateState>(
      listener: (context, state) {
        // Server said 402 → paywall, never a raw error.
        if (state.showPaywall) {
          _showPaywall(context);
        }
        if (state.phase == GeneratePhase.succeeded) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Image generated and saved to History'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
      },
      buildWhen: (prev, next) =>
          prev.showPaywall != next.showPaywall ||
          prev.phase != next.phase ||
          prev.options != next.options ||
          prev.isPremiumUser != next.isPremiumUser ||
          prev.prompt != next.prompt ||
          prev.failure != next.failure ||
          prev.remoteStatus != next.remoteStatus ||
          prev.localImageName != next.localImageName ||
          prev.styleId != next.styleId ||
          prev.aspectRatioId != next.aspectRatioId ||
          prev.qualityId != next.qualityId,
      builder: (context, state) {
        final bloc = context.read<GenerateBloc>();
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, color: AppColors.indigo),
                const SizedBox(width: 10),
                const Text('Create'),
              ],
            ),
            actions: [
              if (state.isPremiumUser)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                // Prompt — glow on focus, aurora spark prefix.
                Focus(
                  onFocusChange: (f) => setState(() => _promptFocused = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _promptFocused
                          ? [
                              BoxShadow(
                                color: AppColors.indigo.withValues(alpha: 0.18),
                                blurRadius: 16,
                              ),
                            ]
                          : null,
                    ),
                    child: TextField(
                      controller: _promptController,
                      enabled: !state.isBusy,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AppColors.text,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText:
                            'Describe the image you want…\ne.g. "a red fox in snowy forest at dawn"',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(
                            left: 14,
                            right: 10,
                            top: 14,
                          ),
                          child: const Icon(
                            Icons.edit_note,
                            color: AppColors.indigo,
                            size: 22,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                      ),
                      onChanged: (v) => bloc.add(PromptChanged(v)),
                    ),
                  ),
                ),
                if (!state.optionsFromServer) ...[
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 15,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Offline — showing default options',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                OptionPickers(state: state),
                const SizedBox(height: 26),
                GradientButton(
                  onPressed: state.canGenerate
                      ? () => bloc.add(const GenerateSubmitted())
                      : null,
                  child: state.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              state.phase == GeneratePhase.failed
                                  ? Icons.refresh
                                  : Icons.auto_awesome,
                              size: 19,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              state.isBusy ? 'Generating…' : 'Generate',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                ),
                if (state.needsPremium && !state.isPremiumUser) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => showPaywallSheet(context),
                      icon: const Icon(
                        Icons.workspace_premium,
                        size: 17,
                        color: AppColors.gold,
                      ),
                      label: const Text(
                        'Selected options require PRO',
                        style: TextStyle(color: AppColors.gold),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                GenerationResult(state: state),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPaywall(BuildContext context) async {
    // Let the bloc state settle, then present the sheet.
    await showPaywallSheet(context);
    if (context.mounted) {
      context.read<GenerateBloc>().add(const GeneratePaywallDismissed());
    }
  }
}
