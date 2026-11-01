import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/failures.dart';
import '../../../data/repositories/repositories.dart';
import 'history_event.dart';
import 'history_state.dart';

export 'history_event.dart';
export 'history_state.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc(this._repository) : super(const HistoryState()) {
    on<HistoryStarted>(_onLoad);
    on<HistoryRefreshed>(_onLoad);
    on<HistoryCleared>(_onCleared);
  }

  final GenerationRepository _repository;

  Future<void> _onLoad(HistoryEvent event, Emitter emit) async {
    if (state.isLoading) return;
    emit(
      state.copyWith(
        isLoading: state.entries.isEmpty,
        isSyncing: true,
        clearFailure: true,
      ),
    );
    try {
      // 1) local-first paint, 2) best-effort server merge.
      final local = await _repository.localHistory();
      if (emit.isDone) return;
      emit(state.copyWith(entries: local, isLoading: false));
      final merged = await _repository.syncWithServer();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          entries: merged,
          isSyncing: false,
          serverUnavailable: false,
        ),
      );
    } on AppFailure catch (f) {
      if (emit.isDone) return;
      final local = await _repository.localHistory();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          entries: local,
          isLoading: false,
          isSyncing: false,
          serverUnavailable: true,
          failure: f,
        ),
      );
    }
  }

  Future<void> _onCleared(HistoryCleared event, Emitter emit) async {
    try {
      await _repository.clearHistory();
    } on AppFailure catch (f) {
      emit(state.copyWith(failure: f));
      return;
    }
    emit(const HistoryState());
  }
}
