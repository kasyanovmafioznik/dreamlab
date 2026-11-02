import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'data/dto/api_models.dart';
import 'di/app_container.dart';
import 'features/generate/bloc/generate_bloc.dart';
import 'features/history/bloc/history_bloc.dart';
import 'features/settings/bloc/settings_bloc.dart';
import 'features/subscription/bloc/subscription_bloc.dart';
import 'router/app_router.dart';

class DreamLabApp extends StatefulWidget {
  const DreamLabApp({super.key, required this.container});

  final AppContainer container;

  @override
  State<DreamLabApp> createState() => _DreamLabAppState();
}

class _DreamLabAppState extends State<DreamLabApp> {
  late final SubscriptionBloc _subscriptionBloc;
  late final GenerateBloc _generateBloc;
  late final HistoryBloc _historyBloc;
  late final SettingsBloc _settingsBloc;
  late final _router = createRouter(prefs: widget.container.prefs);

  @override
  void initState() {
    super.initState();
    final repos = widget.container;
    _subscriptionBloc = SubscriptionBloc(repos.subscriptionRepository)
      ..add(const SubscriptionStarted());
    _generateBloc = GenerateBloc(
      repos.generationRepository,
      initialPremium:
          repos.subscriptionRepository.cachedTier == SubscriptionTier.premium,
    )..add(const GenerateStarted());
    _historyBloc = HistoryBloc(repos.generationRepository)
      ..add(const HistoryStarted());
    _settingsBloc = SettingsBloc(api: repos.api, prefs: repos.prefs);
  }

  @override
  void dispose() {
    _subscriptionBloc.close();
    _generateBloc.close();
    _historyBloc.close();
    _settingsBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _subscriptionBloc),
        BlocProvider.value(value: _generateBloc),
        BlocProvider.value(value: _historyBloc),
        BlocProvider.value(value: _settingsBloc),
      ],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(
            value: widget.container.generationRepository,
          ),
          RepositoryProvider.value(
            value: widget.container.subscriptionRepository,
          ),
        ],
        child: MultiBlocListener(
          listeners: [
            // Server is the source of truth for premium: once the tier changes,
            // the Generate bloc unlocks premium chips immediately.
            BlocListener<SubscriptionBloc, SubscriptionState>(
              listenWhen: (prev, next) => prev.tier != next.tier,
              listener: (context, state) {
                _generateBloc.add(PremiumStatusChanged(state.isPremium));
              },
            ),
            // A finished generation should show up in History without a manual pull.
            BlocListener<GenerateBloc, GenerateState>(
              listenWhen: (prev, next) =>
                  prev.phase != GeneratePhase.succeeded &&
                  next.phase == GeneratePhase.succeeded,
              listener: (context, state) =>
                  _historyBloc.add(const HistoryRefreshed()),
            ),
          ],
          child: MaterialApp.router(
            title: 'DreamLab',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            // Deep links are enabled by default: dreamlab:///history opens
            // the History tab directly.
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
