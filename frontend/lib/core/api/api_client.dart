import 'package:dio/dio.dart';

import '../../data/dto/api_models.dart';
import '../../data/local/prefs.dart';
import '../config/app_config.dart';
import '../errors/failures.dart';

/// Thin Dio wrapper: every call either returns a typed DTO or throws an
/// [AppFailure]. Never leaks Dio exceptions to the domain layer.
class ApiClient {
  ApiClient(this._prefs) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: {'Accept': 'application/json'},
      ),
    );
    _syncBaseUrl();
  }

  final Prefs _prefs;
  late final Dio _dio;

  /// Re-reads base URL from prefs — Settings can change it at runtime.
  void _syncBaseUrl() => _dio.options.baseUrl = _prefs.serverUrl;

  Future<T> _guard<T>(Future<T> Function() run) async {
    _syncBaseUrl();
    try {
      return await run();
    } on DioException catch (e) {
      throw _mapDio(e);
    } on FormatException catch (e) {
      throw MalformedResponseFailure(e.message);
    }
  }

  AppFailure _mapDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure(
          'Connection timed out. Is the server running?',
        );
      case DioExceptionType.receiveTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return NetworkFailure(
          'Cannot reach ${_prefs.serverUrl}. Start the backend and check the address in Settings.',
        );
      case DioExceptionType.badCertificate:
        return const NetworkFailure('TLS certificate rejected by the server.');
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled.');
      case DioExceptionType.badResponse:
        return _mapBadResponse(e.response);
      case DioExceptionType.unknown:
        if (e.error != null) return NetworkFailure(e.error.toString());
        return const UnknownFailure();
    }
  }

  AppFailure _mapBadResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final body = response?.data;
    ApiError? apiError;
    if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
      try {
        apiError = ApiError.fromJson(body['error'] as Map<String, dynamic>);
      } on FormatException {
        apiError = null;
      }
    }

    switch (status) {
      case 402:
        final details = apiError?.details ?? const {};
        final required =
            (details['required_options'] as List<dynamic>? ?? const [])
                .map((e) => e.toString())
                .toList();
        return PaymentRequiredFailure(
          requiredOptions: required,
          message:
              apiError?.message ??
              'Premium options requested without a subscription.',
        );
      case 404:
        return NotFoundFailure(apiError?.message ?? 'Not found.');
      case 409:
        return ServerFailure(
          apiError?.message ?? 'Image is not ready yet.',
          statusCode: 409,
        );
      case 410:
        return ServerFailure(
          apiError?.message ?? 'Image expired on the server.',
          statusCode: 410,
        );
      case 422:
        final fields =
            ((apiError?.details?['fields'] as List<dynamic>?) ?? const []).map((
              f,
            ) {
              if (f is Map<String, dynamic>) {
                return '${f['field'] ?? ''}: ${f['message'] ?? ''}';
              }
              return f.toString();
            }).toList();
        return ValidationFailure(
          apiError?.message ?? 'Invalid request.',
          fields: fields,
        );
      default:
        if (status != null && status >= 500) {
          return ServerFailure(
            apiError?.message ?? 'Server error ($status).',
            statusCode: status,
          );
        }
        if (apiError != null && apiError.code == 'generation_failed') {
          return GenerationFailedFailure(apiError.message);
        }
        return ServerFailure(
          apiError?.message ?? 'Unexpected response ($status).',
          statusCode: status,
        );
    }
  }

  // ---------------------------------------------------------------- endpoints

  Future<bool> health() => _guard(() async {
    final r = await _dio.get<dynamic>('/health');
    return r.data is Map && r.data['status'] == 'ok';
  });

  Future<OptionsCatalog> getOptions() => _guard(() async {
    final r = await _dio.get<dynamic>('${AppConfig.apiPrefix}/options');
    final data = r.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('options payload is not an object');
    }
    return OptionsCatalog.fromJson(data);
  });

  Future<GenerateAccepted> createGeneration({
    required String prompt,
    required String style,
    required String aspectRatio,
    required String quality,
  }) => _guard(() async {
    final r = await _dio.post<dynamic>(
      '${AppConfig.apiPrefix}/generations',
      data: {
        'user_id': _prefs.userId,
        'prompt': prompt,
        'style': style,
        'aspect_ratio': aspectRatio,
        'quality': quality,
      },
    );
    final data = r.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('generation payload is not an object');
    }
    return GenerateAccepted.fromJson(data);
  });

  Future<GenerationJob> getGeneration(String id) => _guard(() async {
    final r = await _dio.get<dynamic>(
      '${AppConfig.apiPrefix}/generations/$id',
      queryParameters: {'user_id': _prefs.userId},
    );
    final data = r.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('job payload is not an object');
    }
    return GenerationJob.fromJson(data);
  });

  /// Downloads raw image bytes for a job (relative `image_url` from the API).
  Future<List<int>> downloadImage(String imageUrl) => _guard(() async {
    final r = await _dio.get<List<int>>(
      imageUrl,
      queryParameters: {'user_id': _prefs.userId},
      options: Options(responseType: ResponseType.bytes),
    );
    return r.data ?? (throw const FormatException('empty image body'));
  });

  Future<List<GenerationJob>> listGenerations({int limit = 50}) =>
      _guard(() async {
        final r = await _dio.get<dynamic>(
          '${AppConfig.apiPrefix}/generations',
          queryParameters: {'user_id': _prefs.userId, 'limit': limit},
        );
        final data = r.data;
        if (data is! Map<String, dynamic> || data['items'] is! List) {
          throw const FormatException('bad generations list payload');
        }
        return (data['items'] as List)
            .map((e) => GenerationJob.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<SubscriptionInfo> getSubscription() => _guard(() async {
    final r = await _dio.get<dynamic>(
      '${AppConfig.apiPrefix}/users/${_prefs.userId}/subscription',
    );
    final data = r.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('bad subscription payload');
    }
    return SubscriptionInfo.fromJson(data);
  });

  Future<SubscriptionInfo> upgradeSubscription() => _guard(() async {
    final r = await _dio.post<dynamic>(
      '${AppConfig.apiPrefix}/users/${_prefs.userId}/subscription/upgrade',
    );
    final data = r.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('bad upgrade payload');
    }
    return SubscriptionInfo.fromJson(data);
  });
}
