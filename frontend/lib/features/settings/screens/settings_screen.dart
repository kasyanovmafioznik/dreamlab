import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../generate/screens/paywall_sheet.dart';
import '../../history/bloc/history_bloc.dart';
import '../../subscription/bloc/subscription_bloc.dart';
import '../bloc/settings_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late String _userIdSnapshot;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<SettingsBloc>();
    _urlController = TextEditingController(text: bloc.state.serverUrl);
    _userIdSnapshot = bloc.state.userId;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocConsumer<SettingsBloc, SettingsState>(
        listener: (context, state) {
          if (state.connectionOk == true && !state.isTestingConnection) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(state.connectionMessage ?? 'Connected')),
              );
          }
          if (state.userId != _userIdSnapshot) {
            _userIdSnapshot = state.userId;
            // New identity → revalidate subscription + drop history view state.
            context.read<SubscriptionBloc>().add(const SubscriptionStarted());
            context.read<HistoryBloc>().add(const HistoryRefreshed());
          }
        },
        builder: (context, settings) {
          final sub = context.watch<SubscriptionBloc>().state;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SectionHeader('Connection'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Server URL', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: 'http://127.0.0.1:8000',
                          prefixIcon: Icon(Icons.dns_outlined, size: 20),
                        ),
                        onChanged: (v) => context.read<SettingsBloc>().add(
                          ServerUrlChanged(v),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: settings.isTestingConnection
                                  ? null
                                  : () => context.read<SettingsBloc>().add(
                                      const ConnectionTested(),
                                    ),
                              icon: settings.isTestingConnection
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.wifi_tethering, size: 18),
                              label: const Text('Test connection'),
                            ),
                          ),
                          if (settings.connectionOk != null) ...[
                            const SizedBox(width: 10),
                            Icon(
                              settings.connectionOk!
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: settings.connectionOk!
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                              size: 22,
                            ),
                          ],
                        ],
                      ),
                      if (settings.connectionOk == false &&
                          settings.connectionMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          settings.connectionMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'iOS Simulator reaches your Mac at 127.0.0.1. '
                        'For a real device use your Mac\'s LAN IP.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _SectionHeader('Subscription'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            sub.isPremium
                                ? Icons.workspace_premium_outlined
                                : Icons.star_outline,
                            color: sub.isPremium
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sub.isPremium ? 'Pro (premium)' : 'Free plan',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  sub.isRefreshing
                                      ? 'Syncing with server…'
                                      : sub.source == SubscriptionSource.server
                                      ? 'Confirmed by server'
                                      : 'Cached value — will sync shortly',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (sub.isRefreshing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!sub.isPremium)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: () => showPaywallSheet(context),
                            icon: const Icon(Icons.upgrade, size: 18),
                            label: const Text('Upgrade to Pro'),
                          ),
                        )
                      else
                        Text(
                          'Premium options are validated on the server.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _SectionHeader('Identity'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Anonymous user ID',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              settings.userId,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy ID',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: settings.userId),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('ID copied')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Generated on first launch. Used to attach history and '
                        'subscription to this device — no account, no login.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: settings.isResettingUser
                            ? null
                            : () => _confirmReset(context),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset identity & subscription'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _SectionHeader('Storage'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Clear local history'),
                      subtitle: const Text(
                        'Removes saved images from this device',
                      ),
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear history?'),
                            content: const Text(
                              'All generated images stored on this device will be deleted. '
                              'Server copies are not affected.',
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
                          context.read<HistoryBloc>().add(
                            const HistoryCleared(),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Local history cleared'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _SectionHeader('About'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DreamLab', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'v1.0.0 · Flutter demo of a server-side AI generation flow.\n'
                        'Images are placeholders generated by the backend.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Reproduce a server error:',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      _CodeLine(text: 'prompt containing "fail"   → job fails'),
                      _CodeLine(
                        text:
                            'prompt containing "timeout" → hangs (client timeout)',
                      ),
                      _CodeLine(
                        text: 'FLAKY_RATE=0.2 backend      → random failures',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset identity?'),
        content: const Text(
          'A new anonymous ID will be generated. The server will treat this '
          'device as a new free user (premium is lost). History on this device stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<SettingsBloc>().add(const UserIdReset());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New identity created — subscription reset to free'),
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
