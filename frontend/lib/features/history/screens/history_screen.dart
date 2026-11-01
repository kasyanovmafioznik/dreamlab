import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../data/dto/api_models.dart';
import '../../../data/local/image_store.dart';
import '../bloc/history_bloc.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          BlocBuilder<HistoryBloc, HistoryState>(
            buildWhen: (p, n) =>
                p.entries.length != n.entries.length ||
                p.serverUnavailable != n.serverUnavailable ||
                p.isSyncing != n.isSyncing,
            builder: (context, state) => IconButton(
              tooltip: 'Refresh from server',
              icon: state.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              onPressed: () =>
                  context.read<HistoryBloc>().add(const HistoryRefreshed()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear history?'),
                    content: const Text(
                      'All generated images stored on this device will be deleted.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  context.read<HistoryBloc>().add(const HistoryCleared());
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 10),
                    Text('Clear all'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: BlocBuilder<HistoryBloc, HistoryState>(
        builder: (context, state) {
          if (state.isLoading && state.entries.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.entries.isEmpty) {
            return const _EmptyHistory();
          }
          return RefreshIndicator(
            onRefresh: () async =>
                context.read<HistoryBloc>().add(const HistoryRefreshed()),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (state.serverUnavailable)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Server unavailable — showing saved history',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final entry in state.entries) _HistoryTile(entry: entry),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.tryParse(entry.createdAt);
    final failed = entry.status == JobStatus.failed;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/generation/${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail: local file first, placeholder otherwise.
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _Thumbnail(entry: entry),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MetaChip(text: entry.style),
                        _MetaChip(text: entry.aspectRatio),
                        _MetaChip(text: entry.quality),
                        if (failed)
                          _MetaChip(
                            text: 'failed',
                            color: theme.colorScheme.error,
                            bg: theme.colorScheme.errorContainer,
                          ),
                      ],
                    ),
                    if (date != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('MMM d, HH:mm').format(date.toLocal()),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.broken_image_outlined,
      size: 22,
      color: Theme.of(context).colorScheme.outline,
    ),
  );
}

/// Thumbnail for a history entry.
///
/// The path is resolved from the stored *file name* at render time — the app
/// container path changes on reinstall, so a stored absolute path would be
/// stale and the image would never show up.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final name = entry.localImageName;
    if (name == null) return const _ThumbPlaceholder();
    final file = File(ImageStore.instance.pathOf(name));
    return Image.file(
      file,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.text, this.color, this.bg});

  final String text;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.aurora,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.indigo.withValues(alpha: 0.25),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: const Icon(Icons.history, size: 34, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'No generations yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Images you create will be saved here\nand stay available offline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 22),
            GradientButton(
              onPressed: () => context.go('/generate'),
              child: const Text('Create your first image'),
            ),
          ],
        ),
      ),
    );
  }
}
