import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../core/errors/failures.dart';
import '../../../data/dto/api_models.dart';

enum GeneratePhase { editing, submitting, polling, succeeded, failed }

@immutable
class GenerateState extends Equatable {
  const GenerateState({
    this.options = OptionsCatalog.fallback,
    this.phase = GeneratePhase.editing,
    this.prompt = '',
    this.styleId = 'photorealistic',
    this.aspectRatioId = '1:1',
    this.qualityId = 'standard',
    this.jobId,
    this.remoteStatus,
    this.localImageName,
    this.failure,
    this.isPremiumUser = false,
    this.showPaywall = false,
    this.optionsFromServer = false,
  });

  final OptionsCatalog options;
  final GeneratePhase phase;
  final String prompt;
  final String styleId;
  final String aspectRatioId;
  final String qualityId;
  final String? jobId;

  /// Last known remote status while polling (queued/processing).
  final JobStatus? remoteStatus;
  final String? localImageName;
  final AppFailure? failure;

  /// Mirrors SubscriptionBloc — lets us lock premium chips immediately.
  final bool isPremiumUser;
  final bool showPaywall;
  final bool optionsFromServer;

  bool get isBusy =>
      phase == GeneratePhase.submitting || phase == GeneratePhase.polling;

  bool get canGenerate => prompt.trim().length >= 3 && !isBusy;

  /// Option ids that require premium according to the catalog.
  List<String> get premiumOptionsUsed {
    final used = <String>[];
    void check(List<OptionItem> items, String selected, String group) {
      for (final item in items) {
        if (item.id == selected && item.premium) used.add('$group:${item.id}');
      }
    }

    check(options.styles, styleId, 'style');
    check(options.aspectRatios, aspectRatioId, 'aspect_ratio');
    check(options.qualities, qualityId, 'quality');
    return used;
  }

  bool get needsPremium => premiumOptionsUsed.isNotEmpty;

  GenerateState copyWith({
    OptionsCatalog? options,
    GeneratePhase? phase,
    String? prompt,
    String? styleId,
    String? aspectRatioId,
    String? qualityId,
    String? jobId,
    JobStatus? remoteStatus,
    String? localImageName,
    AppFailure? failure,
    bool clearFailure = false,
    bool? isPremiumUser,
    bool? showPaywall,
    bool? optionsFromServer,
    bool clearJob = false,
    bool clearImage = false,
    bool clearRemoteStatus = false,
  }) => GenerateState(
    options: options ?? this.options,
    phase: phase ?? this.phase,
    prompt: prompt ?? this.prompt,
    styleId: styleId ?? this.styleId,
    aspectRatioId: aspectRatioId ?? this.aspectRatioId,
    qualityId: qualityId ?? this.qualityId,
    jobId: clearJob ? null : jobId ?? this.jobId,
    remoteStatus: clearRemoteStatus ? null : remoteStatus ?? this.remoteStatus,
    localImageName: clearImage ? null : localImageName ?? this.localImageName,
    failure: clearFailure ? null : failure ?? this.failure,
    isPremiumUser: isPremiumUser ?? this.isPremiumUser,
    showPaywall: showPaywall ?? this.showPaywall,
    optionsFromServer: optionsFromServer ?? this.optionsFromServer,
  );

  @override
  List<Object?> get props => [
    options,
    phase,
    prompt,
    styleId,
    aspectRatioId,
    qualityId,
    jobId,
    remoteStatus,
    localImageName,
    failure,
    isPremiumUser,
    showPaywall,
    optionsFromServer,
  ];
}
