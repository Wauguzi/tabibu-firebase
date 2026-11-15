import 'package:equatable/equatable.dart';

sealed class HybridAssistEvent extends Equatable {
  const HybridAssistEvent();

  @override
  List<Object?> get props => [];
}

/// Locale, connectivity and the current field. The text is an argument
/// only: it is not part of [props] or [toString], because notes may
/// identify the patient.
final class HybridAssistContextChanged extends HybridAssistEvent {
  const HybridAssistContextChanged({
    required this.text,
    required this.englishLocale,
    required this.online,
  });

  final String text;
  final bool englishLocale;
  final bool online;

  @override
  List<Object?> get props => [englishLocale, online];
}

/// The app came back to the foreground: read the model's status again.
final class HybridAssistStatusRefreshed extends HybridAssistEvent {
  const HybridAssistStatusRefreshed();
}

final class HybridAssistGenerateRequested extends HybridAssistEvent {
  const HybridAssistGenerateRequested();
}

/// The proposal closes; [applied] when a tidy was written into the field.
final class HybridAssistProposalDismissed extends HybridAssistEvent {
  const HybridAssistProposalDismissed({this.applied = false});

  final bool applied;

  @override
  List<Object?> get props => [applied];
}
