/// Typed failures the UI can actually recover from.
///
/// Every repository/API error is mapped to one of these — screens never see
/// raw Dio/FormatException.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  /// Stable machine-readable code (also mirrors the server error envelope).
  String? get code => null;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// No connection / host unreachable — offer retry once network is back.
class NetworkFailure extends AppFailure {
  const NetworkFailure([
    super.message =
        'Cannot reach the server. Check your connection and that the backend is running.',
  ]);

  @override
  String get code => 'network';
}

/// Server answered, but too slowly (includes our deliberate `timeout` trigger).
class TimeoutFailure extends AppFailure {
  const TimeoutFailure([
    super.message = 'The server took too long to respond.',
  ]);

  @override
  String get code => 'timeout';
}

/// 5xx or anything unexpected on the server side.
class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;

  @override
  String get code => 'server_error';
}

/// 402 — server rejected premium options for a free user.
class PaymentRequiredFailure extends AppFailure {
  const PaymentRequiredFailure({
    required this.requiredOptions,
    String message = 'This request uses premium options.',
  }) : super(message);

  final List<String> requiredOptions;

  @override
  String get code => 'premium_required';
}

/// 422 — our request was invalid; show field-level messages.
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.fields = const []});

  /// e.g. `['prompt: String should have at least 3 characters']`
  final List<String> fields;

  @override
  String get code => 'validation';
}

/// 404 — job or resource gone.
class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'The requested item was not found.']);

  @override
  String get code => 'not_found';
}

/// Job itself failed on the server (includes the deliberate `fail` trigger).
class GenerationFailedFailure extends AppFailure {
  const GenerationFailedFailure(super.message);

  @override
  String get code => 'generation_failed';
}

/// 200 but the body is not what we expect — defensive parsing caught it.
class MalformedResponseFailure extends AppFailure {
  const MalformedResponseFailure([
    super.message = 'The server sent an unexpected response.',
  ]);

  @override
  String get code => 'malformed_response';
}

class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Something went wrong.']);

  @override
  String get code => 'unknown';
}
