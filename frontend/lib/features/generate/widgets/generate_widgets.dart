import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/dto/api_models.dart';
import '../../../data/local/image_store.dart';
import '../bloc/generate_bloc.dart';

IconData styleIcon(String id) => switch (id) {
  'photorealistic' => Icons.camera_alt_outlined,
  'illustration' => Icons.brush_outlined,
  'minimal' => Icons.center_focus_weak,
  'cinematic' => Icons.movie_filter_outlined,
  'cyberpunk' => Icons.bolt_outlined,
  'watercolor' => Icons.water_drop_outlined,
  _ => Icons.auto_awesome,
};

IconData aspectIcon(String id) => switch (id) {
  '1:1' => Icons.crop_square,
  '16:9' => Icons.crop_16_9,
  '9:16' => Icons.crop_portrait,
  '21:9' => Icons.crop_3_2,
  _ => Icons.aspect_ratio,
};

String qualityLabel(String id) =>
    id == 'standard' ? 'Standard' : (id == '4k' ? '4K' : id.toUpperCase());

/// 3 sections of options: style, aspect ratio, quality.
/// Premium items show a gold PRO badge instead of a mute grey lock.
class OptionPickers extends StatelessWidget {
  const OptionPickers({super.key, required this.state});

  final GenerateState state;

  @override
  Widget build(BuildContext context) {
    final locked = !state.isPremiumUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeonSectionLabel('Style'),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.options.styles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final item = state.options.styles[i];
              final selected = state.styleId == item.id;
              return ChoiceChip(
                avatar: item.premium && locked
                    ? const Icon(
                        Icons.workspace_premium,
                        size: 15,
                        color: AppColors.gold,
                      )
                    : null,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      styleIcon(item.id),
                      size: 15,
                      color: selected ? Colors.white : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(item.label),
                  ],
                ),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) =>
                    context.read<GenerateBloc>().add(StyleChanged(item.id)),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const NeonSectionLabel('Aspect ratio'),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.options.aspectRatios.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final item = state.options.aspectRatios[i];
              final selected = state.aspectRatioId == item.id;
              return ChoiceChip(
                // Icons live in the label Row (same pattern as style chips):
                // a Row in `avatar` gets tighter internal constraints and
                // overflows inside a horizontal ListView.
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      aspectIcon(item.id),
                      size: 15,
                      color: selected ? Colors.white : AppColors.textMuted,
                    ),
                    if (item.premium && locked) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.workspace_premium,
                        size: 13,
                        color: AppColors.gold,
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(item.label.split(' ').last),
                  ],
                ),
                selected: state.aspectRatioId == item.id,
                showCheckmark: false,
                onSelected: (_) => context.read<GenerateBloc>().add(
                  AspectRatioChanged(item.id),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const NeonSectionLabel('Quality'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in state.options.qualities)
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.premium && locked) ...[
                      const Icon(
                        Icons.workspace_premium,
                        size: 13,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(qualityLabel(item.id)),
                  ],
                ),
                selected: state.qualityId == item.id,
                showCheckmark: false,
                onSelected: (_) =>
                    context.read<GenerateBloc>().add(QualityChanged(item.id)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Result area: empty state / progress / image / recoverable error.
class GenerationResult extends StatelessWidget {
  const GenerationResult({super.key, required this.state});

  final GenerateState state;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case GeneratePhase.editing:
        return const _EmptyResult();
      case GeneratePhase.submitting:
        return const _ProgressCard(label: 'Sending request…');
      case GeneratePhase.polling:
        final processing = state.remoteStatus == JobStatus.processing;
        return _ProgressCard(
          label: processing
              ? 'Generating your image…'
              : 'Queued — waiting for a worker…',
        );
      case GeneratePhase.succeeded:
        return _SuccessView(state: state);
      case GeneratePhase.failed:
        return _ErrorView(state: state);
    }
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) {
    return AuroraBlobs(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.aurora,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.indigo.withValues(alpha: 0.25),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your image will appear here',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Describe an idea, tune the options,\ntap Generate',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AuroraBlobs(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This usually takes 3–8 seconds',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.state});

  final GenerateState state;

  @override
  Widget build(BuildContext context) {
    final imageName = state.localImageName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.indigo.withValues(alpha: 0.15),
                blurRadius: 28,
                spreadRadius: -4,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: imageName != null &&
                    File(ImageStore.instance.pathOf(imageName)).existsSync()
                ? Image.file(
                    File(ImageStore.instance.pathOf(imageName)),
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 180,
                    color: AppColors.surfaceHigh,
                    alignment: Alignment.center,
                    child: const Text(
                      'Image file missing locally',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.check_circle, size: 18, color: AppColors.success),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Saved to History',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  context.read<GenerateBloc>().add(const GenerateReset()),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Create another'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.state});

  final GenerateState state;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure;
    if (failure == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Generation failed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            failure.message,
            style: const TextStyle(fontSize: 14, color: Color(0xFF991B1B)),
          ),
          if (failure.code != null) ...[
            const SizedBox(height: 6),
            Text(
              'Code: ${failure.code}',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFB91C1C),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: Color(0xFFFECACA)),
              minimumSize: const Size(0, 46),
            ),
            onPressed: () =>
                context.read<GenerateBloc>().add(const GenerateRetried()),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
