import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/internet_service.dart';
import 'package:tabibu/features/reports/blocs/report_reader_bloc/report_reader_event.dart';
import 'package:tabibu/features/reports/blocs/report_reader_bloc/report_reader_state.dart';
import 'package:tabibu/features/reports/data/cache/report_cache_helper.dart';
import 'package:tabibu/features/reports/data/datasources/report_firebase.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_text_approved_model.dart';
import 'package:tabibu/features/reports/data/models/report_text_model.dart';
import 'package:tabibu/features/reports/data/report_for_case.dart';
import 'package:tabibu/features/reports/data/report_text_id.dart';

/// A case's signed report for its reader. The doctor marks it
/// discussed, which releases it to the patient and queues the AI
/// explanations, then approves, edits or rejects each draft. The patient
/// reads only what the doctor approved. Every write needs the server; the
/// drafts are read live and never cached.
class ReportReaderBloc extends Bloc<ReportReaderEvent, ReportReaderState> {
  ReportReaderBloc({
    ReportCacheHelper? reports,
    ReportFirebase? remote,
    InternetService? internet,
    AnalyticsService? analytics,
    Future<void> Function(Duration)? delay,
  }) : _reports = reports ?? getIt<ReportCacheHelper>(),
       _remote = remote ?? getIt<ReportFirebase>(),
       _internet = internet ?? getIt<InternetService>(),
       _analytics = analytics ?? getIt<AnalyticsService>(),
       _delay = delay ?? Future<void>.delayed,
       super(const ReportReaderInitial()) {
    // The last report opened is the one on screen.
    on<ReportReaderOpened>(_onOpened, transformer: restartable());
    // One decision at a time; a double tap must not repeat a release.
    on<ReportDiscussedRequested>(_onDiscussed, transformer: droppable());
    on<ExplanationDecisionRequested>(_onDecision, transformer: droppable());
    // One retry at a time; a second tap must not queue the language twice.
    on<ExplanationRetryRequested>(_onRetry, transformer: droppable());
    on<ReportReaderReset>((_, emit) => emit(const ReportReaderInitial()));
  }

  final ReportCacheHelper _reports;
  final ReportFirebase _remote;
  final InternetService _internet;
  final AnalyticsService _analytics;
  final Future<void> Function(Duration) _delay;

  /// After Mark as discussed the explanation drafts are written by a worker a
  /// few seconds later; the screen looks for them this often, for this long.
  static const pollEvery = Duration(seconds: 3);
  static const pollFor = Duration(seconds: 90);

  static const _languages = ['en', 'sw'];
  static const _offline = <AppError>{
    .noInternet,
    .serviceUnavailable,
    .requestTimeout,
  };

  AppError _toAppError(Object e) => e is AppError ? e : .unknown;

  Future<void> _onOpened(
    ReportReaderOpened event,
    Emitter<ReportReaderState> emit,
  ) async {
    // Never show another case's report while this one loads.
    final same = state.caseUid == event.caseUid;
    emit(
      ReportReaderLoadInProgress(
        uid: event.uid,
        role: event.role,
        caseUid: event.caseUid,
        report: same ? state.report : null,
        explanations: same ? state.explanations : const {},
        approved: same ? state.approved : const {},
        failedExplanations: same ? state.failedExplanations : const {},
        writingLanguages: same ? state.writingLanguages : const {},
        explanationPhase: same ? state.explanationPhase : .none,
        decidingLanguage: same ? state.decidingLanguage : '',
        retryingLanguage: same ? state.retryingLanguage : '',
      ),
    );
    try {
      var offline = false;
      List<PathologyReportModel> all;
      try {
        all = await _reports.syncReports(event.uid, role: event.role);
      } on AppError catch (e) {
        if (!_offline.contains(e)) rethrow;
        offline = true;
        all = await _reports.getReports(event.uid, role: event.role);
      }
      // Patient: last released version while an update waits; clinician:
      // current.
      final report = reportForCase(
        reports: all,
        caseUid: event.caseUid,
        role: event.role,
      );

      final explanations = <String, ReportTextModel>{};
      final approved = <String, ReportTextApprovedModel>{};
      final failed = <String, ReportTextModel>{};
      final writing = <String>{};
      final statuses = <ReportTextStatus>[];
      if (report != null && report.releasedToPatient) {
        for (final language in _languages) {
          final id = reportTextId(report.uid, .explanation, language);
          if (event.role == .doctor && !offline) {
            ReportTextModel? draft;
            try {
              draft = await _remote.fetchReportText(
                caseUid: event.caseUid,
                textUid: id,
              );
            } on Object catch (_) {
              // The signed report still opens: no draft to read.
            }
            _collect(
              draft,
              language,
              missingIsQueued: false,
              statuses: statuses,
              ready: explanations,
              failed: failed,
              writing: writing,
            );
          }
          final text = offline
              ? await _reports.getApprovedText(event.caseUid, id)
              : await _reports.syncApprovedText(
                  caseUid: event.caseUid,
                  textUid: id,
                );
          if (text != null) approved[language] = text;
        }
      }

      emit(
        ReportReaderLoadSuccess(
          uid: event.uid,
          role: event.role,
          caseUid: event.caseUid,
          report: report,
          explanations: explanations,
          approved: approved,
          failedExplanations: failed,
          writingLanguages: writing,
          offline: offline,
          explanationPhase: _phaseOf(statuses),
        ),
      );
    } on Object catch (e) {
      emit(_failure(e, load: true));
    }
  }

  Future<void> _onDiscussed(
    ReportDiscussedRequested event,
    Emitter<ReportReaderState> emit,
  ) async {
    final report = state.report;
    // In progress first, so a repeated failure is a new state and shows.
    emit(_copy(ReportReaderWriteInProgress.new));
    if (state.role != .doctor || report == null) {
      emit(_failure(AppError.dataNotFound));
      return;
    }
    if (!await _internet.check()) {
      emit(_failure(AppError.noInternet));
      return;
    }
    try {
      await _remote.markDiscussed(
        caseUid: state.caseUid,
        reportUid: report.uid,
      );
      unawaited(_analytics.logReportDiscussed());
      emit(
        _copy(
          ReportDiscussedSuccess.new,
          report: report.copyWith(releasedToPatient: true),
        ),
      );
    } on Object catch (e) {
      emit(_failure(e));
      return;
    }
    await _awaitDrafts(emit, report.uid);
  }

  /// Looks for the explanation drafts until each language is Ready, Failed or
  /// [pollFor] has passed, so they appear without the doctor asking. A failed
  /// read is retried at the next tick. A Ready text is the draft; a Failed
  /// one is recorded on its own so the other language can still be read.
  Future<void> _awaitDrafts(
    Emitter<ReportReaderState> emit,
    String reportUid,
  ) async {
    final caseUid = state.caseUid;
    final ticks = pollFor.inMilliseconds ~/ pollEvery.inMilliseconds;
    for (var tick = 0; tick <= ticks; tick++) {
      if (tick > 0) await _delay(pollEvery);
      if (emit.isDone || state.caseUid != caseUid || state.role != .doctor) {
        return;
      }
      final ready = <String, ReportTextModel>{};
      final failed = <String, ReportTextModel>{};
      final writing = <String>{};
      final statuses = <ReportTextStatus>[];
      for (final language in _languages) {
        final id = reportTextId(reportUid, .explanation, language);
        ReportTextModel? text;
        try {
          text = await _remote.fetchReportText(caseUid: caseUid, textUid: id);
        } on Object catch (_) {
          text = null;
        }
        _collect(
          text,
          language,
          missingIsQueued: true,
          statuses: statuses,
          ready: ready,
          failed: failed,
          writing: writing,
        );
      }
      if (emit.isDone || state.caseUid != caseUid) return;
      final changed =
          ready.isNotEmpty &&
          !const MapEquality<String, ReportTextModel>().equals(
            ready,
            state.explanations,
          );
      final failedChanged = !const MapEquality<String, ReportTextModel>()
          .equals(failed, state.failedExplanations);
      final writingChanged = !const SetEquality<String>().equals(
        writing,
        state.writingLanguages,
      );
      final phase = _phaseOf(statuses);
      if (changed ||
          failedChanged ||
          writingChanged ||
          phase != state.explanationPhase) {
        emit(
          _copy(
            ReportReaderLoadSuccess.new,
            explanations: changed ? ready : null,
            failedExplanations: failed,
            writingLanguages: writing,
            explanationPhase: phase,
            decidingLanguage: '',
            retryingLanguage: '',
          ),
        );
      }
      if (writing.isNotEmpty) continue;
      return;
    }
  }

  Future<void> _onDecision(
    ExplanationDecisionRequested event,
    Emitter<ReportReaderState> emit,
  ) async {
    final draft = state.explanations[event.language];
    emit(
      _copy(ReportReaderWriteInProgress.new, decidingLanguage: event.language),
    );
    if (state.role != .doctor || draft == null) {
      emit(_failure(AppError.dataNotFound));
      return;
    }
    if (!await _internet.check()) {
      emit(_failure(AppError.noInternet));
      return;
    }
    // An "edit" identical to the draft is an approval as is, so the
    // accepted-unchanged metric stays honest.
    final edited = event.editedText;
    final unchanged =
        edited == null ||
        const MapEquality<String, String>().equals(edited, draft.machineText);
    final decision = event.reject
        ? 'Reject'
        : unchanged
        ? 'Approve'
        : 'ApproveEdited';
    try {
      await _remote.approveReportText(
        caseUid: state.caseUid,
        textUid: draft.uid,
        decision: decision,
        approvedText: decision == 'ApproveEdited' ? edited : null,
      );
      final approved = Map.of(state.approved);
      final explanations = Map.of(state.explanations)..remove(event.language);
      if (!event.reject) {
        final text = await _reports.syncApprovedText(
          caseUid: state.caseUid,
          textUid: draft.uid,
        );
        if (text != null) approved[event.language] = text;
      }
      unawaited(_analytics.logExplanationReviewed(approved: !event.reject));
      emit(
        _copy(
          ExplanationDecisionSuccess.new,
          explanations: explanations,
          approved: approved,
          explanationPhase: event.reject && explanations.isEmpty
              ? .rejected
              : null,
          decidingLanguage: '',
        ),
      );
    } on Object catch (e) {
      emit(_failure(e));
    }
  }

  /// Asks for one failed explanation again, then waits for that language the
  /// same way a fresh draft is waited for. A refusal leaves the failure in
  /// place and surfaces the error.
  Future<void> _onRetry(
    ExplanationRetryRequested event,
    Emitter<ReportReaderState> emit,
  ) async {
    final report = state.report;
    final caseUid = state.caseUid;
    final failed = state.failedExplanations[event.language];
    emit(
      _copy(ReportReaderWriteInProgress.new, retryingLanguage: event.language),
    );
    if (state.role != .doctor || report == null || failed == null) {
      emit(_failure(AppError.dataNotFound));
      return;
    }
    if (!await _internet.check()) {
      emit(_failure(AppError.noInternet));
      return;
    }
    try {
      await _remote.requestReportText(
        caseUid: caseUid,
        reportUid: report.uid,
        kind: ReportTextKind.explanation.value,
        language: event.language,
      );
    } on Object catch (e) {
      emit(_failure(e));
      return;
    }
    if (emit.isDone || state.caseUid != caseUid) return;
    final remaining = Map<String, ReportTextModel>.of(state.failedExplanations)
      ..remove(event.language);
    emit(
      _copy(
        ReportReaderLoadSuccess.new,
        failedExplanations: remaining,
        writingLanguages: {...state.writingLanguages, event.language},
        retryingLanguage: '',
        explanationPhase: .pending,
      ),
    );
    await _awaitDrafts(emit, report.uid);
  }

  /// Sorts one language into the draft, the failure, or still being written.
  /// A missing row counts as queued only while waiting after a request;
  /// opening a report leaves a missing row out.
  void _collect(
    ReportTextModel? text,
    String language, {
    required bool missingIsQueued,
    required List<ReportTextStatus> statuses,
    required Map<String, ReportTextModel> ready,
    required Map<String, ReportTextModel> failed,
    required Set<String> writing,
  }) {
    if (text == null) {
      if (!missingIsQueued) return;
      statuses.add(.queued);
      writing.add(language);
      return;
    }
    final status = text.statusValue;
    statuses.add(status);
    switch (status) {
      case .ready:
        ready[language] = text;
      case .failed:
        failed[language] = text;
      case .queued:
      case .running:
        writing.add(language);
      case .approved:
      case .rejected:
        break;
    }
  }

  /// Why there may be no draft to review: still being written, failed, or
  /// set aside by the doctor. A Ready or Approved text says nothing.
  ExplanationDraftPhase _phaseOf(Iterable<ReportTextStatus> statuses) {
    if (statuses.any((s) => s == .queued || s == .running)) return .pending;
    if (statuses.any((s) => s == .failed)) return .failed;
    if (statuses.any((s) => s == .rejected)) return .rejected;
    return .none;
  }

  ReportReaderState _copy(
    ReportReaderState Function({
      String uid,
      Role? role,
      String caseUid,
      PathologyReportModel? report,
      Map<String, ReportTextModel> explanations,
      Map<String, ReportTextApprovedModel> approved,
      Map<String, ReportTextModel> failedExplanations,
      Set<String> writingLanguages,
      bool offline,
      ExplanationDraftPhase explanationPhase,
      String decidingLanguage,
      String retryingLanguage,
    })
    build, {
    PathologyReportModel? report,
    Map<String, ReportTextModel>? explanations,
    Map<String, ReportTextApprovedModel>? approved,
    Map<String, ReportTextModel>? failedExplanations,
    Set<String>? writingLanguages,
    ExplanationDraftPhase? explanationPhase,
    String? decidingLanguage,
    String? retryingLanguage,
  }) => build(
    uid: state.uid,
    role: state.role,
    caseUid: state.caseUid,
    report: report ?? state.report,
    explanations: explanations ?? state.explanations,
    approved: approved ?? state.approved,
    failedExplanations: failedExplanations ?? state.failedExplanations,
    writingLanguages: writingLanguages ?? state.writingLanguages,
    offline: state.offline,
    explanationPhase: explanationPhase ?? state.explanationPhase,
    decidingLanguage: decidingLanguage ?? state.decidingLanguage,
    retryingLanguage: retryingLanguage ?? state.retryingLanguage,
  );

  ReportReaderState _failure(Object e, {bool load = false}) {
    final error = _toAppError(e);
    return load
        ? ReportReaderLoadFailure(
            error: error,
            uid: state.uid,
            role: state.role,
            caseUid: state.caseUid,
            report: state.report,
            explanations: state.explanations,
            approved: state.approved,
            failedExplanations: state.failedExplanations,
            writingLanguages: state.writingLanguages,
            offline: state.offline,
            explanationPhase: state.explanationPhase,
            decidingLanguage: state.decidingLanguage,
            retryingLanguage: state.retryingLanguage,
          )
        : ReportReaderWriteFailure(
            error: error,
            uid: state.uid,
            role: state.role,
            caseUid: state.caseUid,
            report: state.report,
            explanations: state.explanations,
            approved: state.approved,
            failedExplanations: state.failedExplanations,
            writingLanguages: state.writingLanguages,
            offline: state.offline,
            explanationPhase: state.explanationPhase,
            decidingLanguage: state.decidingLanguage,
            retryingLanguage: state.retryingLanguage,
          );
  }
}
