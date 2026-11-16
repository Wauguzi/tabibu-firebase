import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/core/services/audio_service_contract.dart';
import 'package:tabibu/core/widgets/asset_icon.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';
import 'package:tabibu/features/cases/presentation/widgets/explanation_listen_card.dart';
import 'package:tabibu/features/reports/presentation/widgets/listen_card.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

class _MockAnalytics extends Mock implements AnalyticsService {}

/// Holds speak open until the gated answer completes.
class _GatedSpeechClient implements SpeechClient {
  _GatedSpeechClient(this._answer);

  final Future<Uint8List> _answer;

  @override
  Future<Uint8List> speak(SpeechRequest request) => _answer;
}

/// Holds playBytes open on the gate, delegating the rest to the fake.
class _GatedPlayer implements AudioPlayerService {
  _GatedPlayer(this._player, this._gate);

  final FakeAudioPlayerService _player;
  final Future<void> _gate;

  @override
  Stream<AudioPlayback> get playback => _player.playback;

  @override
  Future<void> playBytes(Uint8List bytes, {required String id}) async {
    await _gate;
    await _player.playBytes(bytes, id: id);
  }

  @override
  Future<void> playUrl(Uri url, {required String id}) =>
      _player.playUrl(url, id: id);

  @override
  Future<bool> resume(String id) => _player.resume(id);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Fails the first speak, then answers.
class _FailOnceSpeechClient implements SpeechClient {
  _FailOnceSpeechClient([Uint8List? audio])
    : audio = audio ?? Uint8List.fromList([9]);

  final Uint8List audio;
  var _calls = 0;

  @override
  Future<Uint8List> speak(SpeechRequest request) async {
    if (_calls++ == 0) throw Exception('down');
    return audio;
  }
}

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
    when(() => analytics.logVoicePlaybackPaused()).thenAnswer((_) async {});
    player = FakeAudioPlayerService();
    speech = FakeSpeechClient();
    addTearDown(player.dispose);
  });

  Widget card({
    String text = 'Your test found no cancer.',
    String language = 'en',
    bool online = true,
    SpeechClient? speechClient,
    AudioPlayerService? audioPlayer,
  }) {
    return ExplanationListenCard(
      text: text,
      language: language,
      online: online,
      speech: speechClient ?? speech,
      player: audioPlayer ?? player,
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

    testWidgets('a failed play returns to play with its error', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      final ownId = speech.requests.single.cacheKey;

      // Another clip's failure is not this card's.
      player.failClip('another-clip');
      await tester.pump();
      expect(find.text(l10n.resultDetailListenFailed), findsNothing);

      player.failClip(ownId);
      await tester.pump();

      expect(find.text(l10n.resultDetailListenFailed), findsOneWidget);
      expect(
        tester.widget<AssetIcon>(find.byType(AssetIcon)).asset.path,
        Assets.icons.playIcon.path,
      );
    });

    testWidgets('unmounting while playing stops the player', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      await tester.pumpWidget(Container());

      expect(player.stopCount, 1);
    });

    testWidgets('changing the text stops a playing clip', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      await tester.pumpApp(card(text: 'Your scan looks clear.'));

      expect(player.stopCount, 1);
    });

    testWidgets('a superseded load never plays', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gate = Completer<Uint8List>();
      Widget gated(String text) => ExplanationListenCard(
        text: text,
        language: 'en',
        online: true,
        speech: _GatedSpeechClient(gate.future),
        player: player,
        analytics: analytics,
        settings: settings,
      );
      await tester.pumpApp(gated('Your test found no cancer.'));
      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
      await tester.pump();

      // New words arrive mid-load.
      await tester.pumpApp(gated('Your scan looks clear.'));
      gate.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();

      expect(player.playBytesCalls, isEmpty);
    });

    testWidgets('covering the route stops playback, and popping shows play', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);
      final navigator = Navigator.of(
        tester.element(find.byType(ExplanationListenCard)),
      )..push(MaterialPageRoute<void>(builder: (_) => const Text('over')));
      await tester.pumpAndSettle();

      expect(player.stopCount, 1);

      navigator.pop();
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(l10n.resultDetailListenPlay),
        findsOneWidget,
      );
      expect(player.playBytesCalls, hasLength(1));
    });

    testWidgets('a speak reply that lands while covered never plays', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gate = Completer<Uint8List>();
      await tester.pumpApp(card(speechClient: _GatedSpeechClient(gate.future)));
      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
      await tester.pump();
      Navigator.of(
        tester.element(find.byType(ExplanationListenCard)),
      ).push(MaterialPageRoute<void>(builder: (_) => const Text('over')));
      await tester.pumpAndSettle();
      gate.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();

      expect(player.playBytesCalls, isEmpty);
    });

    testWidgets('a play that starts after dispose is stopped', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gate = Completer<void>();
      await tester.pumpApp(
        card(audioPlayer: _GatedPlayer(player, gate.future)),
      );
      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
      await tester.pump();

      await tester.pumpWidget(Container());
      gate.complete();
      await tester.pumpAndSettle();

      expect(player.stopCount, 1);
    });

    testWidgets('a play that starts after a text change is stopped', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final gate = Completer<void>();
      final gatedPlayer = _GatedPlayer(player, gate.future);
      await tester.pumpApp(card(audioPlayer: gatedPlayer));
      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPlay));
      await tester.pump();

      await tester.pumpApp(
        card(text: 'Your scan looks clear.', audioPlayer: gatedPlayer),
      );
      gate.complete();
      await tester.pumpAndSettle();

      expect(player.stopCount, 1);
    });

    testWidgets('pausing logs it', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(card());
      await tapPlay(tester, l10n);

      await tester.tap(find.bySemanticsLabel(l10n.resultDetailListenPause));
      await tester.pumpAndSettle();

      verify(() => analytics.logVoicePlaybackPaused()).called(1);
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
      await tester.pumpApp(
        ExplanationListenCard(
          text: 'Your test found no cancer.',
          language: 'en',
          online: true,
          speech: _FailOnceSpeechClient(),
          player: player,
          analytics: analytics,
          settings: settings,
        ),
      );

      await tapPlay(tester, l10n);

      expect(find.text(l10n.resultDetailListenFailed), findsOneWidget);
      expect(player.playBytesCalls, isEmpty);

      await tapPlay(tester, l10n);

      expect(find.text(l10n.resultDetailListenFailed), findsNothing);
      expect(player.playBytesCalls, hasLength(1));
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
