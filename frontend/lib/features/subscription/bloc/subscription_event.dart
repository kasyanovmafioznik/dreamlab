import 'package:equatable/equatable.dart';

sealed class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();
  @override
  List<Object?> get props => [];
}

/// App start / identity change: revalidate the cached tier against the server.
class SubscriptionStarted extends SubscriptionEvent {
  const SubscriptionStarted();
}

/// Mock purchase — one POST, no billing.
class SubscriptionUpgradeRequested extends SubscriptionEvent {
  const SubscriptionUpgradeRequested();
}
