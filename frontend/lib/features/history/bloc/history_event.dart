import 'package:equatable/equatable.dart';

sealed class HistoryEvent extends Equatable {
  const HistoryEvent();
  @override
  List<Object?> get props => [];
}

/// First build: paint local history, then merge with the server.
class HistoryStarted extends HistoryEvent {
  const HistoryStarted();
}

/// Manual pull-to-refresh / sync icon / after a new generation finished.
class HistoryRefreshed extends HistoryEvent {
  const HistoryRefreshed();
}

/// Wipe the local store (Settings or the History overflow menu).
class HistoryCleared extends HistoryEvent {
  const HistoryCleared();
}
