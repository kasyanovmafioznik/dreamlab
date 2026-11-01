import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../data/dto/api_models.dart';
import '../../../data/local/image_store.dart';
import '../../../data/repositories/repositories.dart';
import '../../generate/bloc/generate_bloc.dart';
import '../../generate/screens/paywall_sheet.dart';

class GenerationDetailScreen extends StatelessWidget {
  const GenerationDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<GenerationRepository>();

    return FutureBuilder<HistoryEntry?>(
      future: repo.historyById(entryId),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Generation')),
          body:
              !snapshot.hasData &&
                  snapshot.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : entry == null
              ? Center(
                  child: Text(
                    'This generation no longer exists.',
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : _DetailBody(entry: entry),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = entry.status == JobStatus.failed;
    final date = DateTime.tryParse(entry.createdAt);
    // Resolve the absolute path from the stored file name — the container path
    // changes on reinstall, a stored absolute path would be stale.
    final imageName = entry.localImageName;
    final imagePath = imageName == null
        ? null
        : ImageStore.instance.pathOf(imageName);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // Image or failure state.
        if (failed)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  entry.errorMessage ?? 'Generation failed',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (entry.errorCode != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Code: ${entry.errorCode}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          )
        else if (imagePath != null && File(imagePath).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(imagePath), fit: BoxFit.cover),
          )
        else
          Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 36,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 8),
                Text(
                  'Image not stored on this device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // Prompt card with copy.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prompt',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy prompt',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: entry.prompt),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Prompt copied')),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(entry.prompt, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Metadata grid.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _MetaRow(label: 'Style', value: entry.style),
                _MetaRow(label: 'Aspect ratio', value: entry.aspectRatio),
                _MetaRow(label: 'Quality', value: entry.quality),
                _MetaRow(label: 'Status', value: entry.status.name),
                if (date != null)
                  _MetaRow(
                    label: 'Created',
                    value: DateFormat(
                      'MMM d, yyyy · HH:mm',
                    ).format(date.toLocal()),
                  ),
                if (entry.finishedAt != null)
                  _MetaRow(
                    label: 'Finished',
                    value: DateFormat(
                      'MMM d, yyyy · HH:mm',
                    ).format(DateTime.parse(entry.finishedAt!).toLocal()),
                    last: true,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Reuse prompt → Create tab, prompt pre-filled, ready to go.
        FilledButton.icon(
          onPressed: () {
            final generate = context.read<GenerateBloc>();
            generate.add(PromptChanged(entry.prompt));
            generate.add(StyleChanged(entry.style));
            generate.add(AspectRatioChanged(entry.aspectRatio));
            generate.add(QualityChanged(entry.quality));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Options loaded into Create tab')),
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Use these settings in Create'),
        ),
        const SizedBox(height: 8),
        if (entry.status == JobStatus.succeeded)
          OutlinedButton.icon(
            onPressed: () => showPaywallSheet(context),
            icon: const Icon(Icons.workspace_premium, size: 18),
            label: const Text('Unlock more styles & quality'),
          ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
