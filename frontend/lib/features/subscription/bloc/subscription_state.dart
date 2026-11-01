import 'package:equatable/equatable.dart';

import '../../../core/errors/failures.dart';
import '../../../data/dto/api_models.dart';

enum SubscriptionSource { cache, server }

class SubscriptionState extends Equatable {
  const SubscriptionState({
    required this.tier,
    this.upgradedAt,
    this.isRefreshing = false,
    this.isUpgrading = false,
    this.source = SubscriptionSource.cache,
    this.failure,
  });

  /// Painted immediately from cache — the UI never waits for the network.
  final SubscriptionTier tier;
  final String? upgradedAt;
  final bool isRefreshing;
  final bool isUpgrading;

  /// Where the currently shown tier came from (cache = still revalidating).
  final SubscriptionSource source;
  final AppFailure? failure;

  bool get isPremium => tier == SubscriptionTier.premium;

  SubscriptionState copyWith({
    SubscriptionTier? tier,
    String? upgradedAt,
    bool? isRefreshing,
    bool? isUpgrading,
    SubscriptionSource? source,
    AppFailure? failure,
    bool clearFailure = false,
    bool clearUpgradedAt = false,
  }) => SubscriptionState(
    tier: tier ?? this.tier,
    upgradedAt: clearUpgradedAt ? null : upgradedAt ?? this.upgradedAt,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isUpgrading: isUpgrading ?? this.isUpgrading,
    source: source ?? this.source,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  @override
  List<Object?> get props => [
    tier,
    upgradedAt,
    isRefreshing,
    isUpgrading,
    source,
    failure,
  ];
}
