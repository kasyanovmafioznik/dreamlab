import 'package:equatable/equatable.dart';

import '../../../core/errors/failures.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.serverUrl,
    required this.userId,
    this.isTestingConnection = false,
    this.connectionOk,
    this.connectionMessage,
    this.isResettingUser = false,
    this.failure,
  });

  final String serverUrl;
  final String userId;
  final bool isTestingConnection;

  /// null = never tested.
  final bool? connectionOk;
  final String? connectionMessage;
  final bool isResettingUser;
  final AppFailure? failure;

  SettingsState copyWith({
    String? serverUrl,
    String? userId,
    bool? isTestingConnection,
    bool? connectionOk,
    String? connectionMessage,
    bool? isResettingUser,
    AppFailure? failure,
    bool clearFailure = false,
    bool clearConnection = false,
  }) => SettingsState(
    serverUrl: serverUrl ?? this.serverUrl,
    userId: userId ?? this.userId,
    isTestingConnection: isTestingConnection ?? this.isTestingConnection,
    connectionOk: clearConnection ? null : connectionOk ?? this.connectionOk,
    connectionMessage: clearConnection
        ? null
        : connectionMessage ?? this.connectionMessage,
    isResettingUser: isResettingUser ?? this.isResettingUser,
    failure: clearFailure ? null : failure ?? this.failure,
  );

  @override
  List<Object?> get props => [
    serverUrl,
    userId,
    isTestingConnection,
    connectionOk,
    connectionMessage,
    isResettingUser,
    failure,
  ];
}
