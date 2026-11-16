import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/widgets/asset_icon.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';
import 'package:tabibu/features/cases/presentation/widgets/explanation_listen_card.dart';
import 'package:tabibu/features/reports/presentation/widgets/listen_card.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

class _MockAnalytics extends Mock implements AnalyticsService {}

void main() {
  late _MockAnalytics analytics;
  late FakeAudioPlayerService player;
  late FakeSpeechClient speech;

  const settings = SpeechSettings(voice: 'TestVoice', model: 'test-model');

  setUp(() {
    analytics = _MockAnalytics();
    when(
      () => analytics.logVoicePlaybackStarted(surface: any(named: 'surface')),
    ).thenAnswer((_) async {});
    player = FakeAudioPlayerService();
    speech = FakeSpeechClient();
    addTearDown(player.dispose);
  });

  Widget card({
    String text = 'Your test found no cancer.',
    String language = 'en',
    bool online = true,
  }) {
    return ExplanationListenCard(
      text: text,
      language: language,
      online: online,
      speech: speech,
      player: player,
      analytics: analytics,
      settings: settings,
    );
  }

  Future<void> tapPlay(WidgetTester tester, AppLocalizations l10n) async {
    await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
    await tester.pumpAndSettle();
  }

  group('ExplanationListenCard', () {
    testWidgets('plays generated audio with its labels', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());

      await tapPlay(tester, l10n);

      expect(speech.requests, hasLength(1));
      expect(speech.requests.single.text, 'Your test found no cancer.');
      expect(find.text(l10n.resultDetailListenComputerVoice), findsOneWidget);
      expect(
        find.text(l10n.resultDetailListenMeta('English', '0:01')),
        findsOneWidget,
      );
      verify(
        () => analytics.logVoicePlaybackStarted(surface: 'explanation'),
      ).called(1);
    });

    testWidgets('the pause icon shows while the explanation plays', (
      tester,
    ) async {
      await tester.pumpApp(card());
      await tapPlay(tester, lookupAppLocalizations(const Locale('en')));

      expect(
        tester.widget<AssetIcon>(find.byType(AssetIcon)).asset.path,
        Assets.icons.pauseIcon.path,
      );
    });

    testWidgets('replay hits the cache, not the service', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      player.completeCurrent();
      await tester.pumpAndSettle();

      await tapPlay(tester, l10n);

      expect(speech.requests, hasLength(1));
      expect(player.playBytesCalls, hasLength(2));
    });

    testWidgets('pause then play resumes the position', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      player.seekTo(const Duration(milliseconds: 500), playing: true);
      await tester.pump();

      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPause));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
      await tester.pumpAndSettle();

      expect(player.resumeCount, 1);
      expect(speech.requests, hasLength(1));
    });

    testWidgets('a failed generation shows its error and retries', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final failing = FakeSpeechClient(error: Exception('down'));
      await tester.pumpApp(
        ExplanationListenCard(
          text: 'Your test found no cancer.',
          language: 'en',
          online: true,
          speech: failing,
          player: player,
          analytics: analytics,
          settings: settings,
        ),
      );

      await tapPlay(tester, l10n);

      expect(find.text(l10n.resultDetailListenFailed), findsOneWidget);
      expect(player.playBytesCalls, isEmpty);
    });

    testWidgets('offline without cache shows the offline line', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card(online: false));

      expect(find.text(l10n.resultDetailListenOffline), findsOneWidget);
      expect(speech.requests, isEmpty);
    });

    testWidgets('an unknown language hides the card', (tester) async {
      await tester.pumpApp(card(language: 'fr'));

      expect(find.byType(ListenCard), findsNothing);
    });

    testWidgets('disposing drops the cache', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      await tester.pumpWidget(Container());
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);

      expect(speech.requests, hasLength(2));
    });

    for (final locale in const [Locale('en'), Locale('sw')]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('fits at ${scale}x text in ${locale.languageCode}', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpApp(card(), locale: locale);
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          expect(find.text(l10n.resultDetailListenTitle), findsOneWidget);
        });
      }
    }
  });
}
