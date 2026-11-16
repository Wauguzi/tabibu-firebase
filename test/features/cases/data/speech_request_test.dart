import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

class _Settings implements AiLogicConfig {
  _Settings(this.values);

  final Map<String, String> values;

  @override
  String? optionalString(String key) => values[key];

  @override
  bool? optionalBool(String key) => null;
}

void main() {
  group('SpeechRequest', () {
    test('maps en and sw to voice codes, nothing else', () {
      expect(SpeechRequest.languageCodeFor('en'), 'en-US');
      expect(SpeechRequest.languageCodeFor('sw'), 'sw');
      expect(SpeechRequest.languageCodeFor('fr'), isNull);
      expect(SpeechRequest.languageCodeFor(''), isNull);
    });

    test('keys the cache on text, language, voice and model', () {
      String keyOf({
        String text = 't',
        String language = 'en',
        String voice = 'v',
        String model = 'm',
      }) => SpeechRequest(
        text: text,
        language: language,
        voice: voice,
        model: model,
      ).cacheKey;

      final base = keyOf();
      expect(keyOf(), base);
      expect(keyOf(text: 'other'), isNot(base));
      expect(keyOf(language: 'sw'), isNot(base));
      expect(keyOf(voice: 'w'), isNot(base));
      expect(keyOf(model: 'n'), isNot(base));
      // Fields cannot bleed into each other across the separator.
      expect(keyOf(text: 'a\x00sw'), isNot(keyOf(text: 'a', language: 'sw')));
    });
  });

  group('SpeechSettings', () {
    test('reads voice and model, falling back to the defaults', () {
      const fallback = SpeechSettings(
        voice: SpeechSettings.defaultVoice,
        model: SpeechSettings.defaultModel,
      );

      expect(SpeechSettings.resolve(_Settings({})).voice, fallback.voice);
      expect(
        SpeechSettings.resolve(
          _Settings({'ai_tts_voice': 'Vindemiatrix'}),
        ).voice,
        'Vindemiatrix',
      );
      expect(
        SpeechSettings.resolve(_Settings({'ai_tts_model': 'custom-tts'})).model,
        'custom-tts',
      );
    });
  });
}
