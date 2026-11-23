import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/internet_service.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_bloc.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_event.dart';
import 'package:tabibu/features/alerts/blocs/alert_review_bloc/alert_review_state.dart';
import 'package:tabibu/features/alerts/data/datasources/alert_firebase.dart';
import 'package:tabibu/features/alerts/data/models/alert_model.dart';
import 'package:tabibu/features/alerts/data/models/alert_text_model.dart';

class _MockAlerts extends Mock implements AlertFirebase {}

class _MockInternet extends Mock implements InternetService {}

class _MockAnalytics extends Mock implements AnalyticsService {}

const _text = {
  'patient_en': AlertTextModel(
    headline: 'More malaria',
    body: 'Sleep under a net.',
  ),
  'patient_sw': AlertTextModel(
    headline: 'Patient sw',
    body: 'Patient sw body.',
  ),
  'clinician_en': AlertTextModel(
    headline: 'Malaria rise',
    body: 'Test every fever.',
  ),
  'clinician_sw': AlertTextModel(
    headline: 'Clinician sw',
    body: 'Clinician sw body.',
  ),
};

AlertModel _alert(String uid, {int draft = 3, int evidence = 7}) =>
    AlertModel.empty().copyWith(
      uid: uid,
      status: AlertStatus.draft.value,
      draftRevision: draft,
      evidenceRevision: evidence,
      machineText: _text,
    );

void main() {
  late _MockAlerts alerts;
  late _MockInternet internet;
  late _MockAnalytics analytics;

  AlertReviewBloc build() => AlertReviewBloc(
    alerts: alerts,
    internet: internet,
    analytics: analytics,
    // No real waiting between polls.
    delay: (_) async {},
  );

  void stubApprove() => when(
    () => alerts.approveAlert(
      alertUid: any(named: 'alertUid'),
      decision: any(named: 'decision'),
      draftRevision: any(named: 'draftRevision'),
      evidenceRevision: any(named: 'evidenceRevision'),
      audience: any(named: 'audience'),
      editedText: any(named: 'editedText'),
      reason: any(named: 'reason'),
    ),
  ).thenAnswer((_) async => {'status': 'ok'});

  setUpAll(() {
    registerFallbackValue(ApprovalDecision.approve);
  });

  setUp(() {
    alerts = _MockAlerts();
    internet = _MockInternet();
    analytics = _MockAnalytics();
    when(() => internet.check()).thenAnswer((_) async => true);
    when(
      () => analytics.logAlertReviewed(decision: any(named: 'decision')),
    ).thenAnswer((_) async {});
  });

  group('AlertReviewBloc', () {
    blocTest<AlertReviewBloc, AlertReviewState>(
      'loads the queue live',
      setUp: () => when(
        () => alerts.fetchAwaitingDecision(),
      ).thenAnswer((_) async => [_alert('a1')]),
      build: build,
      act: (bloc) => bloc.add(const AlertQueueRequested()),
      expect: () => [
        const AlertReviewLoadInProgress(),
        AlertReviewLoadSuccess(queue: [_alert('a1')]),
      ],
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'opening another alert never shows the previous draft while loading',
      setUp: () => when(
        () => alerts.fetchAlert('a2'),
      ).thenAnswer((_) async => _alert('a2')),
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertReviewOpened(alertUid: 'a2')),
      expect: () => [
        const AlertReviewLoadInProgress(),
        AlertReviewLoadSuccess(current: _alert('a2')),
      ],
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a missing alert is not found',
      setUp: () =>
          when(() => alerts.fetchAlert('a9')).thenAnswer((_) async => null),
      build: build,
      act: (bloc) => bloc.add(const AlertReviewOpened(alertUid: 'a9')),
      expect: () => [
        const AlertReviewLoadInProgress(),
        const AlertReviewLoadFailure(error: AppError.dataNotFound),
      ],
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'approve sends the revisions the approver saw, never fresh ones',
      setUp: () {
        stubApprove();
        when(
          () => alerts.fetchAlert('a1'),
        ).thenAnswer((_) async => _alert('a1', draft: 9, evidence: 9));
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(
        queue: [_alert('a1'), _alert('a2')],
        current: _alert('a1'),
      ),
      act: (bloc) => bloc.add(const AlertApproveRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(
          queue: [_alert('a1'), _alert('a2')],
          current: _alert('a1'),
        ),
        AlertDecisionSuccess(
          decision: ApprovalDecision.approve,
          queue: [_alert('a2')],
          current: _alert('a1', draft: 9, evidence: 9),
        ),
      ],
      verify: (_) {
        verify(
          () => alerts.approveAlert(
            alertUid: 'a1',
            decision: 'Approve',
            draftRevision: 3,
            evidenceRevision: 7,
          ),
        ).called(1);
        verify(
          () => analytics.logAlertReviewed(decision: ApprovalDecision.approve),
        ).called(1);
      },
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'an edit identical to the draft is an approval as is',
      setUp: stubApprove,
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(
        const AlertApproveRequested(alertUid: 'a1', editedText: _text),
      ),
      verify: (_) => verify(
        () => alerts.approveAlert(
          alertUid: 'a1',
          decision: 'Approve',
          draftRevision: 3,
          evidenceRevision: 7,
        ),
      ).called(1),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a real edit is sent as ApproveEdited with the edited text',
      setUp: stubApprove,
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(
        AlertApproveRequested(
          alertUid: 'a1',
          audience: AlertAudience.cliniciansOnly,
          editedText: Map.of(_text)
            ..['patient_en'] = const AlertTextModel(
              headline: 'More malaria in Embakasi',
              body: 'Sleep under a net.',
            ),
        ),
      ),
      verify: (_) {
        final call = verify(
          () => alerts.approveAlert(
            alertUid: 'a1',
            decision: 'ApproveEdited',
            draftRevision: 3,
            evidenceRevision: 7,
            audience: 'CliniciansOnly',
            editedText: captureAny(named: 'editedText'),
          ),
        )..called(1);
        final sent = call.captured.single as Map<String, dynamic>;
        expect(sent.keys, unorderedEquals(_text.keys));
        expect(
          (sent['patient_en'] as Map<String, dynamic>)['headline'],
          'More malaria in Embakasi',
        );
        verify(
          () => analytics.logAlertReviewed(
            decision: ApprovalDecision.approveEdited,
          ),
        ).called(1);
      },
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'offline, no decision is sent or queued',
      setUp: () => when(() => internet.check()).thenAnswer((_) async => false),
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertApproveRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionFailure(error: AppError.noInternet, current: _alert('a1')),
      ],
      verify: (_) {
        verifyNever(
          () => alerts.approveAlert(
            alertUid: any(named: 'alertUid'),
            decision: any(named: 'decision'),
            draftRevision: any(named: 'draftRevision'),
            evidenceRevision: any(named: 'evidenceRevision'),
          ),
        );
        verifyNever(
          () => analytics.logAlertReviewed(decision: any(named: 'decision')),
        );
      },
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a decision on an alert not under review is refused',
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertApproveRequested(alertUid: 'a2')),
      expect: () => [
        AlertDecisionFailure(
          error: AppError.dataNotFound,
          current: _alert('a1'),
        ),
      ],
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a rejection needs a reason',
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) =>
          bloc.add(const AlertRejectRequested(alertUid: 'a1', reason: '  ')),
      expect: () => [
        AlertDecisionFailure(
          error: AppError.invalidDecision,
          current: _alert('a1'),
        ),
      ],
      verify: (_) => verifyNever(
        () => analytics.logAlertReviewed(decision: any(named: 'decision')),
      ),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a rejection sends its trimmed reason',
      setUp: () {
        stubApprove();
        when(() => alerts.fetchAlert('a1')).thenAnswer((_) async => null);
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(
        const AlertRejectRequested(
          alertUid: 'a1',
          reason: ' Not enough cases ',
        ),
      ),
      verify: (_) {
        verify(
          () => alerts.approveAlert(
            alertUid: 'a1',
            decision: 'Reject',
            draftRevision: 3,
            evidenceRevision: 7,
            reason: 'Not enough cases',
          ),
        ).called(1);
        verify(
          () => analytics.logAlertReviewed(decision: ApprovalDecision.reject),
        ).called(1);
      },
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a refused decision keeps the review on screen',
      setUp: () => when(
        () => alerts.approveAlert(
          alertUid: any(named: 'alertUid'),
          decision: any(named: 'decision'),
          draftRevision: any(named: 'draftRevision'),
          evidenceRevision: any(named: 'evidenceRevision'),
          audience: any(named: 'audience'),
          editedText: any(named: 'editedText'),
          reason: any(named: 'reason'),
        ),
      ).thenThrow(AppError.permissionDenied),
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertApproveRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(current: _alert('a1')),
        AlertDecisionFailure(
          error: AppError.permissionDenied,
          current: _alert('a1'),
        ),
      ],
      verify: (_) => verifyNever(
        () => analytics.logAlertReviewed(decision: any(named: 'decision')),
      ),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'approve that lands still succeeds when the re-fetch throws',
      setUp: () {
        stubApprove();
        when(() => alerts.fetchAlert('a1')).thenThrow(AppError.unknown);
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(
        queue: [_alert('a1'), _alert('a2')],
        current: _alert('a1'),
      ),
      act: (bloc) => bloc.add(const AlertApproveRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(
          queue: [_alert('a1'), _alert('a2')],
          current: _alert('a1'),
        ),
        AlertDecisionSuccess(
          decision: ApprovalDecision.approve,
          queue: [_alert('a2')],
          current: _alert('a1').copyWith(
            status: AlertStatus.approved.value,
            decision: ApprovalDecision.approve.value,
          ),
        ),
      ],
      // The decision landed before the re-fetch fault: it still counts.
      verify: (_) => verify(
        () => analytics.logAlertReviewed(decision: ApprovalDecision.approve),
      ).called(1),
    );

    final drafting = _alert('a1').copyWith(status: AlertStatus.drafting.value);
    final redrafted = _alert('a1').copyWith(draftRevision: 2);

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a redraft calls the callable, then reloads until the new draft is in',
      setUp: () {
        when(
          () => alerts.requestAlertDraft(alertUid: 'a1'),
        ).thenAnswer((_) async => {'status': 'redrafting'});
        var reads = 0;
        when(
          () => alerts.fetchAlert('a1'),
        ).thenAnswer((_) async => reads++ == 0 ? drafting : redrafted);
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertRedraftRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(current: _alert('a1')),
        AlertReviewLoadSuccess(current: drafting),
        AlertReviewLoadSuccess(current: redrafted),
      ],
      verify: (_) {
        verify(() => alerts.requestAlertDraft(alertUid: 'a1')).called(1);
        verify(() => alerts.fetchAlert('a1')).called(2);
      },
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a draft that never arrives stops the polling after its budget',
      setUp: () {
        when(
          () => alerts.requestAlertDraft(alertUid: 'a1'),
        ).thenAnswer((_) async => {'status': 'redrafting'});
        when(() => alerts.fetchAlert('a1')).thenAnswer((_) async => drafting);
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertRedraftRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(current: _alert('a1')),
        AlertReviewLoadSuccess(current: drafting),
      ],
      verify: (_) => verify(() => alerts.fetchAlert('a1')).called(
        AlertReviewBloc.redraftPollFor.inSeconds ~/
                AlertReviewBloc.redraftPollEvery.inSeconds +
            1,
      ),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a redraft limit keeps the draft that is on screen',
      setUp: () => when(
        () => alerts.requestAlertDraft(alertUid: any(named: 'alertUid')),
      ).thenThrow(AppError.redraftLimit),
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertRedraftRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(current: _alert('a1')),
        AlertDecisionFailure(
          error: AppError.redraftLimit,
          current: _alert('a1'),
        ),
      ],
      verify: (_) => verifyNever(() => alerts.fetchAlert(any())),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'an alert that can no longer be redrafted keeps its draft',
      setUp: () => when(
        () => alerts.requestAlertDraft(alertUid: any(named: 'alertUid')),
      ).thenThrow(AppError.invalidState),
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertRedraftRequested(alertUid: 'a1')),
      expect: () => [
        AlertDecisionInProgress(current: _alert('a1')),
        AlertDecisionFailure(
          error: AppError.invalidState,
          current: _alert('a1'),
        ),
      ],
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'a second redraft while one is running does not call again',
      setUp: () {
        when(
          () => alerts.requestAlertDraft(alertUid: any(named: 'alertUid')),
        ).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return {'status': 'redrafting'};
        });
        when(
          () => alerts.fetchAlert('a1'),
        ).thenAnswer((_) async => _alert('a1'));
      },
      build: build,
      seed: () => AlertReviewLoadSuccess(current: _alert('a1')),
      act: (bloc) {
        bloc
          ..add(const AlertRedraftRequested(alertUid: 'a1'))
          ..add(const AlertRedraftRequested(alertUid: 'a1'));
      },
      verify: (_) =>
          verify(() => alerts.requestAlertDraft(alertUid: 'a1')).called(1),
    );

    blocTest<AlertReviewBloc, AlertReviewState>(
      'drops everything on reset',
      build: build,
      seed: () =>
          AlertReviewLoadSuccess(queue: [_alert('a1')], current: _alert('a1')),
      act: (bloc) => bloc.add(const AlertReviewReset()),
      expect: () => [const AlertReviewInitial()],
    );
  });
}
