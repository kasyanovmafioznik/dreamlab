import 'package:equatable/equatable.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => [];
}

class SettingsStarted extends SettingsEvent {
  const SettingsStarted();
}

class ServerUrlChanged extends SettingsEvent {
  const ServerUrlChanged(this.url);
  final String url;
  @override
  List<Object?> get props => [url];
}

class ConnectionTested extends SettingsEvent {
  const ConnectionTested();
}

/// Rotates the anonymous userId and drops the subscription cache.
class UserIdReset extends SettingsEvent {
  const UserIdReset();
}
