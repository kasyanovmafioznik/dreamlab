// Server API payloads — explicit `fromJson`, no codegen (small surface, easy to read).

import 'package:flutter/foundation.dart';

enum JobStatus { queued, processing, succeeded, failed }

enum SubscriptionTier { free, premium }

class ApiError {
  const ApiError({required this.code, required this.message, this.details});

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  factory ApiError.fromJson(Map<String, dynamic> json) {
    final details = json['details'];
    return ApiError(
      code: json['code'] as String? ?? 'unknown',
      message: json['message'] as String? ?? 'Unknown error',
      details: details is Map<String, dynamic> ? details : null,
    );
  }
}

class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.status,
    required this.prompt,
    required this.style,
    required this.aspectRatio,
    required this.quality,
    this.imageUrl,
    this.error,
    required this.createdAt,
    this.finishedAt,
  });

  final String id;
  final JobStatus status;
  final String prompt;
  final String style;
  final String aspectRatio;
  final String quality;
  final String? imageUrl;
  final ApiError? error;
  final String createdAt;
  final String? finishedAt;

  bool get isTerminal =>
      status == JobStatus.succeeded || status == JobStatus.failed;

  factory GenerationJob.fromJson(Map<String, dynamic> json) {
    try {
      return GenerationJob(
        id: json['id'] as String,
        status: JobStatus.values.byName(json['status'] as String),
        prompt: json['prompt'] as String,
        style: json['style'] as String,
        aspectRatio: json['aspect_ratio'] as String,
        quality: json['quality'] as String,
        imageUrl: json['image_url'] as String?,
        error: json['error'] == null
            ? null
            : ApiError.fromJson(json['error'] as Map<String, dynamic>),
        createdAt: json['created_at'] as String,
        finishedAt: json['finished_at'] as String?,
      );
    } on TypeError catch (e) {
      throw FormatException('Bad GenerationJob payload: $e');
    } on ArgumentError catch (e) {
      // `EnumByName.byName` throws ArgumentError for unknown values.
      throw FormatException('Bad GenerationJob payload: $e');
    }
  }
}

class GenerateAccepted {
  const GenerateAccepted({required this.id, required this.pollUrl});

  final String id;
  final String pollUrl;

  factory GenerateAccepted.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final pollUrl = json['poll_url'];
    if (id is! String || pollUrl is! String) {
      throw const FormatException('Bad GenerateAccepted payload');
    }
    return GenerateAccepted(id: id, pollUrl: pollUrl);
  }
}

class OptionItem {
  const OptionItem({
    required this.id,
    required this.label,
    required this.premium,
  });

  final String id;
  final String label;
  final bool premium;

  factory OptionItem.fromJson(Map<String, dynamic> json) => OptionItem(
    id: json['id'] as String,
    label: json['label'] as String,
    premium: json['premium'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'premium': premium,
  };
}

class OptionsCatalog {
  const OptionsCatalog({
    required this.styles,
    required this.aspectRatios,
    required this.qualities,
  });

  final List<OptionItem> styles;
  final List<OptionItem> aspectRatios;
  final List<OptionItem> qualities;

  factory OptionsCatalog.fromJson(Map<String, dynamic> json) {
    List<OptionItem> parse(String key) => (json[key] as List<dynamic>)
        .map((e) => OptionItem.fromJson(e as Map<String, dynamic>))
        .toList();
    try {
      return OptionsCatalog(
        styles: parse('styles'),
        aspectRatios: parse('aspect_ratios'),
        qualities: parse('qualities'),
      );
    } on TypeError catch (e) {
      throw FormatException('Bad OptionsCatalog payload: $e');
    } on ArgumentError catch (e) {
      throw FormatException('Bad OptionsCatalog payload: $e');
    }
  }

  Map<String, dynamic> toJson() => {
    'styles': styles.map((e) => e.toJson()).toList(),
    'aspect_ratios': aspectRatios.map((e) => e.toJson()).toList(),
    'qualities': qualities.map((e) => e.toJson()).toList(),
  };

  /// Used as a fallback when server options are unreachable (offline start).
  static const fallback = OptionsCatalog(
    styles: [
      OptionItem(id: 'photorealistic', label: 'Photorealistic', premium: false),
      OptionItem(id: 'illustration', label: 'Illustration', premium: false),
      OptionItem(id: 'minimal', label: 'Minimal', premium: false),
      OptionItem(id: 'cinematic', label: 'Cinematic', premium: true),
      OptionItem(id: 'cyberpunk', label: 'Cyberpunk', premium: true),
      OptionItem(id: 'watercolor', label: 'Watercolor', premium: true),
    ],
    aspectRatios: [
      OptionItem(id: '1:1', label: 'Square 1:1', premium: false),
      OptionItem(id: '16:9', label: 'Wide 16:9', premium: false),
      OptionItem(id: '9:16', label: 'Portrait 9:16', premium: false),
      OptionItem(id: '21:9', label: 'Cinema 21:9', premium: true),
    ],
    qualities: [
      OptionItem(id: 'standard', label: 'Standard (1024px)', premium: false),
      OptionItem(id: 'hd', label: 'HD (2048px)', premium: true),
      OptionItem(id: '4k', label: '4K (4096px)', premium: true),
    ],
  );
}

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.userId,
    required this.tier,
    this.upgradedAt,
  });

  final String userId;
  final SubscriptionTier tier;
  final String? upgradedAt;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final tier = json['tier'];
    if (tier is! String ||
        !SubscriptionTier.values.any((t) => t.name == tier)) {
      throw const FormatException('Bad SubscriptionInfo payload');
    }
    return SubscriptionInfo(
      userId: json['user_id'] as String,
      tier: SubscriptionTier.values.byName(tier),
      upgradedAt: json['upgraded_at'] as String?,
    );
  }
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.prompt,
    required this.style,
    required this.aspectRatio,
    required this.quality,
    required this.status,
    this.localImageName,
    this.errorCode,
    this.errorMessage,
    required this.createdAt,
    this.finishedAt,
  });

  final String id;
  final String prompt;
  final String style;
  final String aspectRatio;
  final String quality;
  final JobStatus status;

  /// *File name* of the image inside the app's image store (not an absolute
  /// path — the container UUID changes on reinstall). Resolved against the
  /// live [ImageStore] when rendering.
  final String? localImageName;
  final String? errorCode;
  final String? errorMessage;
  final String createdAt;
  final String? finishedAt;

  Map<String, dynamic> toDb() => {
    'id': id,
    'prompt': prompt,
    'style': style,
    'aspect_ratio': aspectRatio,
    'quality': quality,
    'status': status.name,
    'local_image_name': localImageName,
    'error_code': errorCode,
    'error_message': errorMessage,
    'created_at': createdAt,
    'finished_at': finishedAt,
  };

  factory HistoryEntry.fromDb(Map<String, dynamic> row) => HistoryEntry(
    id: row['id'] as String,
    prompt: row['prompt'] as String,
    style: row['style'] as String,
    aspectRatio: row['aspect_ratio'] as String,
    quality: row['quality'] as String,
    status: JobStatus.values.byName(row['status'] as String),
    localImageName: row['local_image_name'] as String?,
    errorCode: row['error_code'] as String?,
    errorMessage: row['error_message'] as String?,
    createdAt: row['created_at'] as String,
    finishedAt: row['finished_at'] as String?,
  );

  factory HistoryEntry.fromJob(GenerationJob job, {String? localImageName}) =>
      HistoryEntry(
        id: job.id,
        prompt: job.prompt,
        style: job.style,
        aspectRatio: job.aspectRatio,
        quality: job.quality,
        status: job.status,
        localImageName: localImageName,
        errorCode: job.error?.code,
        errorMessage: job.error?.message,
        createdAt: job.createdAt,
        finishedAt: job.finishedAt,
      );
}
