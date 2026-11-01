import 'package:equatable/equatable.dart';

import '../../../core/errors/failures.dart';
import '../../../data/dto/api_models.dart';

class HistoryState extends Equatable {
  const HistoryState({
    this.entries = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.serverUnavailable = false,
    this.failure,
  });

  final List<HistoryEntry> entries;
  final bool isLoading;

  /// Background merge with the server is running.
  final bool isSyncing;

  /// Last sync failed (server down) — shown as a subtle offline banner,
  /// local history still renders.
  final bool serverUnavailable;
  final AppFailure? failure;

  bool get isEmpty => entries.isEmpty;

  HistoryState copyWith({
    List<HistoryEntry>? entries,
    bool? isLoading,
    bool? isSyncing,
    bool? serverUnavailable,
    AppFailure? failure,
    bool clearFailure = false,
  }) => HistoryState(
    entries: entries ?? this.entries,
    isLoading: isLoading ?? this.isLoading,
    isSyncing: isSyncing ?? this.isSyncing,
    serverUnavailable: serverUnavailable ?? this.serverUnavailable,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  @override
  List<Object?> get props => [
    entries,
    isLoading,
    isSyncing,
    serverUnavailable,
    failure,
  ];
}
