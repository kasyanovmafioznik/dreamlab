import 'package:flutter_test/flutter_test.dart';
import 'package:test_app_ai/core/errors/failures.dart';
import 'package:test_app_ai/data/dto/api_models.dart';

void main() {
  group('GenerationJob.fromJson', () {
    test('parses a succeeded job', () {
      final job = GenerationJob.fromJson({
        'id': 'abc123',
        'status': 'succeeded',
        'prompt': 'a red fox',
        'style': 'illustration',
        'aspect_ratio': '16:9',
        'quality': 'standard',
        'image_url': '/v1/generations/abc123/image',
        'error': null,
        'created_at': '2026-01-01T00:00:00+00:00',
        'finished_at': '2026-01-01T00:00:05+00:00',
      });
      expect(job.status, JobStatus.succeeded);
      expect(job.isTerminal, isTrue);
      expect(job.imageUrl, '/v1/generations/abc123/image');
    });

    test('throws FormatException on malformed payload (defensive parsing)', () {
      expect(
        () => GenerationJob.fromJson({
          'id': 'x',
          'status': 'definitely-not-a-status',
          'prompt': 'p',
          'style': 's',
          'aspect_ratio': '1:1',
          'quality': 'standard',
          'created_at': 't',
        }),
        throwsFormatException,
      );
    });
  });

  test('ApiError carries details for the paywall', () {
    final err = ApiError.fromJson({
      'code': 'premium_required',
      'message': 'nope',
      'details': {
        'required_options': ['style:cyberpunk'],
      },
    });
    expect(err.code, 'premium_required');
    expect(err.details?['required_options'], ['style:cyberpunk']);
  });

  test('PaymentRequiredFailure exposes required options', () {
    const f = PaymentRequiredFailure(requiredOptions: ['quality:hd']);
    expect(f.requiredOptions, ['quality:hd']);
    expect(f.code, 'premium_required');
  });

  test('fallback options catalog contains premium and free items', () {
    final c = OptionsCatalog.fallback;
    expect(c.styles.where((s) => s.premium).isNotEmpty, isTrue);
    expect(c.styles.where((s) => !s.premium).isNotEmpty, isTrue);
    expect(c.qualities.map((q) => q.id), ['standard', 'hd', '4k']);
  });
}
