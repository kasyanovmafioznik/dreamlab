import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/failures.dart';
import '../../../data/local/prefs.dart';
import 'settings_event.dart';
import 'settings_state.dart';

export 'settings_event.dart';
export 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required ApiClient api, required Prefs prefs})
    : _api = api,
      _prefs = prefs,
      super(SettingsState(serverUrl: prefs.serverUrl, userId: prefs.userId)) {
    on<SettingsStarted>(_onStarted);
    on<ServerUrlChanged>(_onUrlChanged);
    on<ConnectionTested>(_onTest);
    on<UserIdReset>(_onResetUser);
  }

  final ApiClient _api;
  final Prefs _prefs;

  void _onStarted(SettingsStarted event, Emitter emit) => emit(
    state.copyWith(
      serverUrl: _prefs.serverUrl,
      userId: _prefs.userId,
      clearFailure: true,
    ),
  );

  void _onUrlChanged(ServerUrlChanged event, Emitter emit) {
    final trimmed = event.url.trim();
    emit(
      state.copyWith(
        serverUrl: trimmed,
        clearConnection: true,
        clearFailure: true,
      ),
    );
    if (trimmed.isNotEmpty) _prefs.serverUrl = trimmed;
  }

  Future<void> _onTest(ConnectionTested event, Emitter emit) async {
    emit(
      state.copyWith(
        isTestingConnection: true,
        clearConnection: true,
        clearFailure: true,
      ),
    );
    try {
      final ok = await _api.health();
      emit(
        state.copyWith(
          isTestingConnection: false,
          connectionOk: ok,
          connectionMessage: ok
              ? 'Connected to ${_prefs.serverUrl}'
              : 'Server responded but status is not ok',
        ),
      );
    } on AppFailure catch (f) {
      emit(
        state.copyWith(
          isTestingConnection: false,
          connectionOk: false,
          connectionMessage: f.message,
          failure: f,
        ),
      );
    }
  }

  /// New anonymous identity = clean subscription cache (server sees a new user → free).
  Future<void> _onResetUser(UserIdReset event, Emitter emit) async {
    emit(state.copyWith(isResettingUser: true, clearFailure: true));
    _prefs.resetUserId();
    _prefs.clearSubscriptionCache();
    emit(state.copyWith(isResettingUser: false, userId: _prefs.userId));
  }
}
