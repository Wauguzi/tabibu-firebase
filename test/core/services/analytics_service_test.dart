import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';

class _MockFirebaseAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  late _MockFirebaseAnalytics firebase;
  late AnalyticsService analytics;

  setUp(() {
    firebase = _MockFirebaseAnalytics();
    when(
      () => firebase.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
      ),
    ).thenAnswer((_) async {});
    analytics = AnalyticsService(analytics: firebase);
  });

  test('recording started carries the surface only', () async {
    await analytics.logVoiceRecordingStarted(surface: 'symptom');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'voice_recording_started',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'surface': 'symptom'});
  });

  test('recording discarded carries the surface only', () async {
    await analytics.logVoiceRecordingDiscarded(surface: 'mdt');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'voice_recording_discarded',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'surface': 'mdt'});
  });

  test('playback started carries its surface', () async {
    await analytics.logVoicePlaybackStarted(surface: 'explanation');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'voice_playback_started',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'surface': 'explanation'});
  });

  test('playback paused carries no parameters', () async {
    await analytics.logVoicePlaybackPaused();

    final captured = verify(
      () => firebase.logEvent(
        name: 'voice_playback_paused',
        parameters: captureAny(named: 'parameters'),
      ),
    ).captured.single;
    expect(captured, isNull);
  });

  test('a hybrid run carries the task and its outcome only', () async {
    await analytics.logHybridInference(
      task: 'symptom_tidy',
      outcome: 'in_cloud',
    );

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'hybrid_inference',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'task': 'symptom_tidy', 'outcome': 'in_cloud'});
  });

  test('a hybrid proposal carries the task and what was done', () async {
    await analytics.logHybridProposal(
      task: 'notes_summary',
      action: 'dismissed',
    );

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'hybrid_proposal',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'task': 'notes_summary', 'action': 'dismissed'});
  });

  test('a region read carries its outcome only', () async {
    await analytics.logRegionRead(outcome: 'shown');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'region_read',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'outcome': 'shown'});
  });

  test('a walk-in patient added carries nothing about the patient', () async {
    await analytics.logPatientAdded();

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'patient_added',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, isNull);
  });

  test('an explanation retry carries its language only', () async {
    await analytics.logExplanationRetried(language: 'sw');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'explanation_retried',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'language': 'sw'});
  });

  test('a report download carries the role only', () async {
    await analytics.logReportDownloaded(role: 'doctor');

    final captured =
        verify(
              () => firebase.logEvent(
                name: 'report_downloaded',
                parameters: captureAny(named: 'parameters'),
              ),
            ).captured.single
            as Map<String, Object?>?;
    expect(captured, {'role': 'doctor'});
  });
}
