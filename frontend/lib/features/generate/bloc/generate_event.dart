import 'package:equatable/equatable.dart';

sealed class GenerateEvent extends Equatable {
  const GenerateEvent();
  @override
  List<Object?> get props => [];
}

class GenerateStarted extends GenerateEvent {
  const GenerateStarted();
}

class PromptChanged extends GenerateEvent {
  const PromptChanged(this.prompt);
  final String prompt;
  @override
  List<Object?> get props => [prompt];
}

class StyleChanged extends GenerateEvent {
  const StyleChanged(this.styleId);
  final String styleId;
  @override
  List<Object?> get props => [styleId];
}

class AspectRatioChanged extends GenerateEvent {
  const AspectRatioChanged(this.aspectRatioId);
  final String aspectRatioId;
  @override
  List<Object?> get props => [aspectRatioId];
}

class QualityChanged extends GenerateEvent {
  const QualityChanged(this.qualityId);
  final String qualityId;
  @override
  List<Object?> get props => [qualityId];
}

class GenerateSubmitted extends GenerateEvent {
  const GenerateSubmitted();
}

class GenerateRetried extends GenerateEvent {
  const GenerateRetried();
}

class GeneratePaywallDismissed extends GenerateEvent {
  const GeneratePaywallDismissed();
}

/// Success → "make another": back to editing, prompt and options kept.
class GenerateReset extends GenerateEvent {
  const GenerateReset();
}

class PremiumStatusChanged extends GenerateEvent {
  const PremiumStatusChanged(this.isPremium);
  final bool isPremium;
  @override
  List<Object?> get props => [isPremium];
}
