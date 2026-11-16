import 'dart:convert';

// Transitive only; the brief adds no dependency. Resolved by pubspec.lock.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';

/// What one explanation narration sends: the approved text plus the voice it
/// speaks in. Carries display text only — never an order number, name, uid or
/// anything else that identifies the patient.
class SpeechRequest {
  const SpeechRequest({
    required this.text,
    required this.language,
    required this.voice,
    required this.model,
  });

  final String text;

  /// `en` or `sw`; anything else never reaches the model (see below).
  final String language;
  final String voice;
  final String model;

  /// BCP-47 voice language, or null when the language is unknown. English
  /// uses the documented sample default; Swahili is unproven until a live call.
  static String? languageCodeFor(String language) => switch (language) {
    'en' => 'en-US',
    'sw' => 'sw',
    _ => null,
  };

  /// Cache key: sha256 over the four inputs, so a changed voice, model,
  /// language or word re-generates.
  String get cacheKey {
    final bytes = utf8.encode('$text\x00$language\x00$voice\x00$model');
    return sha256.convert(bytes).toString();
  }
}

/// The narration voice and model, from Remote Config with documented
/// fallbacks. Defaults live in the defaults file; a missing key keeps the
/// in-app value.
class SpeechSettings {
  const SpeechSettings({required this.voice, required this.model});

  factory SpeechSettings.resolve(AiLogicConfig config) => SpeechSettings(
    voice: config.optionalString(voiceKey) ?? defaultVoice,
    model: config.optionalString(modelKey) ?? defaultModel,
  );

  static const voiceKey = 'ai_tts_voice';
  static const modelKey = 'ai_tts_model';

  static const defaultVoice = 'Achernar';
  static const defaultModel = 'gemini-3.8-flash-tts';

  final String voice;
  final String model;
}
