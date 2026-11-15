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

  test('playback started carries no parameters', () async {
    await analytics.logVoicePlaybackStarted();

    final captured = verify(
      () => firebase.logEvent(
        name: 'voice_playback_started',
        parameters: captureAny(named: 'parameters'),
      ),
    ).captured.single;
    expect(captured, isNull);
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
}
