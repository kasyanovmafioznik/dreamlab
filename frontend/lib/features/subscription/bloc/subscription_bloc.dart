import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/failures.dart';
import '../../../data/repositories/repositories.dart';
import 'subscription_event.dart';
import 'subscription_state.dart';

export 'subscription_event.dart';
export 'subscription_state.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  SubscriptionBloc(this._repository)
    : super(
        SubscriptionState(
          tier: _repository.cachedTier,
          upgradedAt: _repository.cachedUpgradedAt,
        ),
      ) {
    on<SubscriptionStarted>(_onStarted);
    on<SubscriptionUpgradeRequested>(_onUpgrade);
  }

  final SubscriptionRepository _repository;

  /// Revalidates the cached tier against the server. Failure keeps the cache:
  /// the screen stays usable, we just don't know if it's stale.
  Future<void> _onStarted(SubscriptionStarted event, Emitter emit) async {
    if (state.isRefreshing) return;
    emit(state.copyWith(isRefreshing: true, clearFailure: true));
    try {
      final info = await _repository.refresh();
      emit(
        state.copyWith(
          tier: info.tier,
          upgradedAt: info.upgradedAt,
          isRefreshing: false,
          source: SubscriptionSource.server,
          clearUpgradedAt: info.upgradedAt == null,
        ),
      );
    } on AppFailure catch (f) {
      emit(
        state.copyWith(
          isRefreshing: false,
          failure: f,
          source: SubscriptionSource.cache,
        ),
      );
    }
  }

  Future<void> _onUpgrade(
    SubscriptionUpgradeRequested event,
    Emitter emit,
  ) async {
    emit(state.copyWith(isUpgrading: true, clearFailure: true));
    try {
      final info = await _repository.upgrade();
      emit(
        state.copyWith(
          tier: info.tier,
          upgradedAt: info.upgradedAt,
          isUpgrading: false,
          source: SubscriptionSource.server,
        ),
      );
    } on AppFailure catch (f) {
      emit(state.copyWith(isUpgrading: false, failure: f));
    }
  }
}
