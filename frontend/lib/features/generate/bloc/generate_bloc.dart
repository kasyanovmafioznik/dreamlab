import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../data/dto/api_models.dart';
import '../../../data/repositories/repositories.dart';
import 'generate_event.dart';
import 'generate_state.dart';

export 'generate_event.dart';
export 'generate_state.dart';

class GenerateBloc extends Bloc<GenerateEvent, GenerateState> {
  GenerateBloc(this._repository, {required bool initialPremium})
    : super(GenerateState(isPremiumUser: initialPremium)) {
    on<GenerateStarted>(_onStarted);
    on<PromptChanged>(_onPromptChanged);
    on<StyleChanged>(_onStyleChanged);
    on<AspectRatioChanged>(_onAspectRatioChanged);
    on<QualityChanged>(_onQualityChanged);
    on<GenerateSubmitted>(_onSubmitted);
    on<GenerateRetried>(_onSubmitted);
    on<GeneratePaywallDismissed>(_onPaywallDismissed);
    on<GenerateReset>(_onReset);
    on<PremiumStatusChanged>(_onPremiumStatusChanged);
  }

  final GenerationRepository _repository;

  Future<void> _onStarted(GenerateStarted event, Emitter emit) async {
    try {
      final options = await _repository.loadOptions();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          options: options,
          optionsFromServer: true,
          // keep selections valid if the server catalog differs
          styleId: _valid(options.styles, state.styleId),
          aspectRatioId: _valid(options.aspectRatios, state.aspectRatioId),
          qualityId: _valid(options.qualities, state.qualityId),
        ),
      );
    } on AppFailure {
      // Offline: keep the fallback catalog (already in state), stay usable.
    }
  }

  String _valid(List<OptionItem> items, String current) =>
      items.any((i) => i.id == current)
      ? current
      : items.isNotEmpty
      ? items.first.id
      : current;

  void _onPromptChanged(PromptChanged event, Emitter emit) =>
      emit(state.copyWith(prompt: event.prompt));

  void _onStyleChanged(StyleChanged event, Emitter emit) =>
      emit(state.copyWith(styleId: event.styleId, clearFailure: true));

  void _onAspectRatioChanged(AspectRatioChanged event, Emitter emit) => emit(
    state.copyWith(aspectRatioId: event.aspectRatioId, clearFailure: true),
  );

  void _onQualityChanged(QualityChanged event, Emitter emit) =>
      emit(state.copyWith(qualityId: event.qualityId, clearFailure: true));

  /// Paywall closed. If the user upgraded, re-run the pending generation so
  /// the flow completes without asking them to tap Generate again.
  void _onPaywallDismissed(GeneratePaywallDismissed event, Emitter emit) {
    final canResume =
        state.isPremiumUser &&
        state.needsPremium &&
        state.prompt.trim().length >= 3 &&
        state.phase == GeneratePhase.editing;
    emit(state.copyWith(showPaywall: false));
    if (canResume) add(const GenerateSubmitted());
  }

  void _onReset(GenerateReset event, Emitter emit) => emit(
    state.copyWith(
      phase: GeneratePhase.editing,
      clearFailure: true,
      clearImage: true,
      clearJob: true,
      clearRemoteStatus: true,
    ),
  );

  void _onPremiumStatusChanged(PremiumStatusChanged event, Emitter emit) =>
      emit(state.copyWith(isPremiumUser: event.isPremium));

  Future<void> _onSubmitted(GenerateEvent event, Emitter emit) async {
    if (state.isBusy) return;
    final prompt = state.prompt.trim();
    if (prompt.length < 3) {
      emit(
        state.copyWith(
          phase: GeneratePhase.failed,
          failure: const ValidationFailure(
            'Prompt must be at least 3 characters.',
          ),
        ),
      );
      return;
    }

    // Proactive gate: we know the options are premium and the user is free.
    // The server still enforces this — this is UX only.
    if (state.needsPremium && !state.isPremiumUser) {
      emit(state.copyWith(showPaywall: true));
      return;
    }

    emit(
      state.copyWith(
        phase: GeneratePhase.submitting,
        clearFailure: true,
        clearImage: true,
        clearRemoteStatus: true,
        showPaywall: false,
      ),
    );

    try {
      final accepted = await _repository.startGeneration(
        prompt: prompt,
        style: state.styleId,
        aspectRatio: state.aspectRatioId,
        quality: state.qualityId,
      );
      if (emit.isDone) return;
      emit(
        state.copyWith(
          phase: GeneratePhase.polling,
          jobId: accepted.id,
          remoteStatus: JobStatus.queued,
        ),
      );
      await _poll(emit, accepted.id);
    } on PaymentRequiredFailure catch (f) {
      // Server rejected despite our local check (stale cached tier) → paywall.
      if (emit.isDone) return;
      emit(
        state.copyWith(
          phase: GeneratePhase.editing,
          showPaywall: true,
          failure: f,
        ),
      );
    } on AppFailure catch (f) {
      if (emit.isDone) return;
      emit(state.copyWith(phase: GeneratePhase.failed, failure: f));
    }
  }

  /// Poll with backoff: 0.5s → 2s, hard cap at [AppConfig.pollOverallTimeout].
  Future<void> _poll(Emitter emit, String jobId) async {
    var delay = AppConfig.pollInitialDelay;
    final deadline = DateTime.now().add(AppConfig.pollOverallTimeout);

    while (true) {
      await Future<void>.delayed(delay);
      if (emit.isDone) return;
      if (DateTime.now().isAfter(deadline)) {
        emit(
          state.copyWith(
            phase: GeneratePhase.failed,
            failure: const TimeoutFailure(
              'Generation took too long. The server may be stuck — you can retry.',
            ),
          ),
        );
        return;
      }

      try {
        final job = await _repository.getStatus(jobId);
        if (emit.isDone) return;

        switch (job.status) {
          case JobStatus.queued:
          case JobStatus.processing:
            emit(state.copyWith(remoteStatus: job.status));
            delay = _nextDelay(delay);
          case JobStatus.succeeded:
            emit(state.copyWith(remoteStatus: JobStatus.succeeded));
            final entry = await _repository.persistResult(job);
            if (emit.isDone) return;
            emit(
              state.copyWith(
                phase: GeneratePhase.succeeded,
                localImageName: entry.localImageName,
                clearRemoteStatus: true,
              ),
            );
            return;
          case JobStatus.failed:
            if (emit.isDone) return;
            await _repository.persistResult(job);
            if (emit.isDone) return;
            emit(
              state.copyWith(
                phase: GeneratePhase.failed,
                failure: GenerationFailedFailure(
                  job.error?.message ?? 'The generation failed. Please retry.',
                ),
              ),
            );
            return;
        }
      } on AppFailure catch (f) {
        if (emit.isDone) return;
        // Transient poll error (network blip): keep polling until deadline.
        if (f is NetworkFailure || f is TimeoutFailure || f is ServerFailure) {
          delay = _nextDelay(delay);
          continue;
        }
        emit(state.copyWith(phase: GeneratePhase.failed, failure: f));
        return;
      }
    }
  }

  Duration _nextDelay(Duration current) {
    final nextMs = (current.inMilliseconds * 1.6).round();
    return Duration(
      milliseconds: min(nextMs, AppConfig.pollMaxDelay.inMilliseconds),
    );
  }
}
