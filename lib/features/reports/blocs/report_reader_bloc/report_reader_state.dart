import 'package:equatable/equatable.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_text_approved_model.dart';
import 'package:tabibu/features/reports/data/models/report_text_model.dart';

/// Why a released report has no explanation draft to review. Only read when
/// there is nothing to review or approved; [none] reads as still waiting.
enum ExplanationDraftPhase { none, pending, failed, rejected }

/// A case's signed report for its reader. [explanations] are the AI drafts
/// awaiting the doctor's approval, by language (doctor only); [approved] the
/// explanations the doctor approved (what a patient may read);
/// [failedExplanations] the languages whose draft the worker refused, so each
/// can be asked for again without showing the reason or the refused text;
/// [writingLanguages] the languages still being written once another language
/// already has something to read. [explanationPhase] is the folded reason
/// there is nothing to show at all. Every state carries the last good data.
sealed class ReportReaderState extends Equatable {
  const ReportReaderState({
    this.uid = '',
    this.role,
    this.caseUid = '',
    this.report,
    this.explanations = const <String, ReportTextModel>{},
    this.approved = const <String, ReportTextApprovedModel>{},
    this.failedExplanations = const <String, ReportTextModel>{},
    this.writingLanguages = const <String>{},
    this.offline = false,
    this.explanationPhase = .none,
    this.decidingLanguage = '',
    this.retryingLanguage = '',
  });

  final String uid;
  final Role? role;
  final String caseUid;
  final PathologyReportModel? report;
  final Map<String, ReportTextModel> explanations;
  final Map<String, ReportTextApprovedModel> approved;

  /// Failed drafts by language. The reason stays on the model and off the
  /// screen.
  final Map<String, ReportTextModel> failedExplanations;

  /// `en` or `sw` still queued or running.
  final Set<String> writingLanguages;
  final bool offline;
  final ExplanationDraftPhase explanationPhase;

  /// The language whose Approve is in flight, so that button can show it.
  final String decidingLanguage;

  /// The language whose Try again is in flight.
  final String retryingLanguage;

  @override
  List<Object?> get props => [
    uid,
    role,
    caseUid,
    report,
    explanations,
    approved,
    failedExplanations,
    writingLanguages,
    offline,
    explanationPhase,
    decidingLanguage,
    retryingLanguage,
  ];
}

final class ReportReaderInitial extends ReportReaderState {
  const ReportReaderInitial();
}

final class ReportReaderLoadInProgress extends ReportReaderState {
  const ReportReaderLoadInProgress({
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });
}

final class ReportReaderLoadSuccess extends ReportReaderState {
  const ReportReaderLoadSuccess({
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });
}

final class ReportReaderWriteInProgress extends ReportReaderState {
  const ReportReaderWriteInProgress({
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });
}

final class ReportDiscussedSuccess extends ReportReaderState {
  const ReportDiscussedSuccess({
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });
}

final class ExplanationDecisionSuccess extends ReportReaderState {
  const ExplanationDecisionSuccess({
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });
}

final class ReportReaderLoadFailure extends ReportReaderState {
  const ReportReaderLoadFailure({
    required this.error,
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });

  final AppError error;

  @override
  List<Object?> get props => [...super.props, error];
}

final class ReportReaderWriteFailure extends ReportReaderState {
  const ReportReaderWriteFailure({
    required this.error,
    super.uid,
    super.role,
    super.caseUid,
    super.report,
    super.explanations,
    super.approved,
    super.failedExplanations,
    super.writingLanguages,
    super.offline,
    super.explanationPhase,
    super.decidingLanguage,
    super.retryingLanguage,
  });

  final AppError error;

  @override
  List<Object?> get props => [...super.props, error];
}
