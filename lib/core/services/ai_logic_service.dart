import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:tabibu/core/constants/enums.dart';

/// Model calls a bloc can use: server template calls plus narration.
/// A bloc never sees the SDK types.
abstract interface class AiLogicService {
  /// The model named in `prompts/symptom-transcribe-v1-0-0.prompt`. The
  /// template owns the model; this is only what the transcript record stores.
  static const symptomTranscribeModel = 'gemini-3.8-flash';

  static const defaultTemplateId = 'symptom-transcribe-v1-0-0';
  static const defaultLocation = 'global';

  static const templateKey = 'ai_template_symptom_transcribe';
  static const locationKey = 'ai_location';
  static const limitedUseKey = 'ai_limited_use_tokens';

  /// The model named in `prompts/slide-region-read-v1-0-0.prompt`. The
  /// template owns the model; this is only what reads record.
  static const regionReadModel = 'gemini-3.8-flash';

  static const regionTemplateKey = 'ai_template_slide_region';
  static const defaultRegionTemplateId = 'slide-region-read-v1-0-0';

  /// Transcribes [wav] in the caller's language. The bytes stay in memory
  /// for this call only.
  Future<SymptomTranscript> transcribeSymptoms(
    Uint8List wav, {
    required String mimeType,
  });

  /// Reads a slide region through the region template. Returns the template's
  /// raw JSON map; the caller validates it into a read. Pixels and short text
  /// only — never identifiers.
  Future<Map<String, Object?>> readRegion({
    required Uint8List imageBytes,
    required String imageMime,
    String question = '',
    String stain = '',
  });

  /// Speaks [text] verbatim in [languageCode] with [voice] on [model].
  /// Returns complete WAV bytes. No system instruction, no temperature: the
  /// model only reads aloud.
  Future<Uint8List> speakExplanation({
    required String text,
    required String languageCode,
    required String voice,
    required String model,
  });
}

/// Template output for a symptom recording. [language] is `en`, `sw` or
/// `other`. An unclear recording never becomes one of these.
class SymptomTranscript {
  const SymptomTranscript({required this.transcript, required this.language});

  final String transcript;
  final String language;
}

/// What one server prompt template call sends. Tests read this; the bytes
/// are not kept.
class TemplateRequest {
  const TemplateRequest({
    required this.templateId,
    required this.location,
    required this.limitedUseTokens,
    required this.inputs,
  });

  final String templateId;
  final String location;
  final bool limitedUseTokens;
  final Map<String, Object?> inputs;
}

/// Replaces the SDK call. Returns the template text, or null when empty.
typedef TemplateCaller = Future<String?> Function(TemplateRequest request);

/// What one narration sends. Tests read this; the text is not kept.
class SpeakRequest {
  const SpeakRequest({
    required this.text,
    required this.languageCode,
    required this.voice,
    required this.model,
    required this.location,
    required this.limitedUseTokens,
  });

  final String text;
  final String languageCode;
  final String voice;
  final String model;
  final String location;
  final bool limitedUseTokens;
}

/// Replaces the SDK call. Returns complete WAV bytes, or null when empty.
typedef SpeakCaller = Future<Uint8List?> Function(SpeakRequest request);

/// Null means the key has no value, so the caller keeps its default.
abstract interface class AiLogicConfig {
  String? optionalString(String key);

  bool? optionalBool(String key);
}

class RemoteConfigAiLogicConfig implements AiLogicConfig {
  RemoteConfigAiLogicConfig([FirebaseRemoteConfig? config])
    : _config = config ?? FirebaseRemoteConfig.instance;

  final FirebaseRemoteConfig _config;

  @override
  String? optionalString(String key) {
    final value = _config.getString(key).trim();
    if (value.isEmpty) return null;
    return value;
  }

  @override
  bool? optionalBool(String key) => _config.getBool(key);
}

@LazySingleton(as: AiLogicService)
class FirebaseAiLogicService implements AiLogicService {
  FirebaseAiLogicService({
    @ignoreParam AiLogicConfig? config,
    @ignoreParam TemplateCaller? transcribe,
    @ignoreParam TemplateCaller? readRegionCall,
    @ignoreParam SpeakCaller? speakCall,
    @ignoreParam Logger? logger,
  }) : _config = config ?? RemoteConfigAiLogicConfig(),
       _transcribe = transcribe ?? callTemplate,
       _readRegionCall = readRegionCall ?? callTemplate,
       _speakCall = speakCall ?? callSpeak,
       _logger = logger ?? Logger();

  final AiLogicConfig _config;
  final TemplateCaller _transcribe;
  final TemplateCaller _readRegionCall;
  final SpeakCaller _speakCall;
  final Logger _logger;

  @override
  Future<SymptomTranscript> transcribeSymptoms(
    Uint8List wav, {
    required String mimeType,
  }) async {
    if (wav.isEmpty || mimeType.trim().isEmpty) throw AppError.unknown;
    final request = TemplateRequest(
      templateId: _setting(
        _config.optionalString(AiLogicService.templateKey),
        AiLogicService.defaultTemplateId,
      ),
      location: _setting(
        _config.optionalString(AiLogicService.locationKey),
        AiLogicService.defaultLocation,
      ),
      limitedUseTokens:
          _config.optionalBool(AiLogicService.limitedUseKey) ?? false,
      inputs: {'audioMime': mimeType, 'audioData': base64Encode(wav)},
    );
    try {
      // The request dies with this call: nothing here keeps the audio.
      final text = await _transcribe(request);
      return parseSymptomTranscript(text);
    } on Object catch (error) {
      throw error is AppError ? error : aiLogicFailure(error);
    }
  }

  @override
  Future<Map<String, Object?>> readRegion({
    required Uint8List imageBytes,
    required String imageMime,
    String question = '',
    String stain = '',
  }) async {
    if (imageBytes.isEmpty || imageMime.trim().isEmpty) {
      throw AppError.unknown;
    }
    final request = TemplateRequest(
      templateId: _setting(
        _config.optionalString(AiLogicService.regionTemplateKey),
        AiLogicService.defaultRegionTemplateId,
      ),
      location: _setting(
        _config.optionalString(AiLogicService.locationKey),
        AiLogicService.defaultLocation,
      ),
      limitedUseTokens:
          _config.optionalBool(AiLogicService.limitedUseKey) ?? false,
      inputs: {
        'imageMime': imageMime,
        'imageData': base64Encode(imageBytes),
        if (question.isNotEmpty) 'question': question,
        if (stain.isNotEmpty) 'stain': stain,
      },
    );
    try {
      // The request dies with this call: nothing here keeps the pixels.
      final text = await _readRegionCall(request);
      return parseRegionJson(text);
    } on Object catch (error) {
      throw error is AppError ? error : aiLogicFailure(error);
    }
  }

  @override
  Future<Uint8List> speakExplanation({
    required String text,
    required String languageCode,
    required String voice,
    required String model,
  }) async {
    if (text.trim().isEmpty ||
        languageCode.trim().isEmpty ||
        voice.trim().isEmpty ||
        model.trim().isEmpty) {
      throw AppError.unknown;
    }
    final request = SpeakRequest(
      text: text,
      languageCode: languageCode,
      voice: voice,
      model: model,
      location: _setting(
        _config.optionalString(AiLogicService.locationKey),
        AiLogicService.defaultLocation,
      ),
      limitedUseTokens:
          _config.optionalBool(AiLogicService.limitedUseKey) ?? false,
    );
    try {
      // The request dies with this call: nothing here keeps the text.
      final bytes = await _speakCall(request);
      if (bytes == null || bytes.isEmpty) throw AppError.unknown;
      // The player is told WAV: anything else fails here, named, instead
      // of failing silently downstream.
      if (!isWavAudio(bytes)) {
        if (kDebugMode) {
          _logger.e(
            'Listen speak failed: non-WAV response (${bytes.length} bytes)',
          );
        }
        throw AppError.unknown;
      }
      return bytes;
    } on Object catch (error) {
      if (kDebugMode) {
        _logger.e(
          'Listen speak failed: ${error.runtimeType} (language $languageCode, '
          'voice $voice, model $model, text ${text.length} chars)',
        );
      }
      throw error is AppError ? error : aiLogicFailure(error);
    }
  }
}

String _setting(String? raw, String fallback) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return fallback;
  return value;
}

/// The SDK boundary. Not called from tests.
Future<String?> callTemplate(TemplateRequest request) async {
  final backend = FirebaseAI.agentPlatform(
    location: request.location,
    useLimitedUseAppCheckTokens: request.limitedUseTokens,
  );
  // Server templates are still preview in this SDK.
  // ignore: experimental_member_use
  final model = backend.templateGenerativeModel();
  // The call is the same preview API.
  // ignore: experimental_member_use
  final response = await model.generateContent(
    request.templateId,
    inputs: request.inputs,
  );
  return response.text;
}

/// True when [bytes] open with the RIFF magic: the container every TTS
/// response arrives in, and the only one the player names correctly.
bool isWavAudio(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x52 && // R
    bytes[1] == 0x49 && // I
    bytes[2] == 0x46 && // F
    bytes[3] == 0x46; // F

/// The SDK boundary. Not called from tests. A plain audio call: no system
/// instruction, no temperature, so the model only reads the text aloud.
Future<Uint8List?> callSpeak(SpeakRequest request) async {
  final backend = FirebaseAI.agentPlatform(
    location: request.location,
    useLimitedUseAppCheckTokens: request.limitedUseTokens,
  );
  final model = backend.generativeModel(
    model: request.model,
    generationConfig: GenerationConfig(
      responseModalities: [ResponseModalities.audio],
      speechConfig: SpeechConfig(
        voiceName: request.voice,
        languageCode: request.languageCode,
      ),
    ),
  );
  final response = await model.generateContent([Content.text(request.text)]);
  final parts = response.inlineDataParts;
  if (parts.isEmpty) return null;
  final bytes = parts.first.bytes;
  return bytes.isEmpty ? null : bytes;
}

/// Parses the template's JSON. Unknown keys are ignored. Empty text, bad
/// JSON, a blank transcript and an unclear recording fail closed, with no
/// text left on the error.
SymptomTranscript parseSymptomTranscript(String? raw) {
  if (raw == null || raw.trim().isEmpty) throw AppError.unknown;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw AppError.unknown;
  }
  if (decoded is! Map) throw AppError.unknown;
  final transcript = decoded['transcript'];
  final language = decoded['language'];
  final unclear = decoded['unclear'];
  if (transcript is! String || language is! String || unclear is! bool) {
    throw AppError.unknown;
  }
  // A partial transcript with unclear set is still a half-heard note.
  if (unclear) throw AppError.unknown;
  final text = transcript.trim();
  if (text.isEmpty) throw AppError.unknown;
  return SymptomTranscript(
    transcript: text,
    language: symptomLanguage(language),
  );
}

/// The callable accepts only these three. Anything else is recorded as other
/// so a recognised language label cannot drop the patient's words.
String symptomLanguage(String raw) => switch (raw.trim().toLowerCase()) {
  'en' || 'english' => 'en',
  'sw' || 'swahili' || 'kiswahili' => 'sw',
  'other' => 'other',
  _ => 'other',
};

/// Decodes template JSON to a map. Empty text, bad JSON and a non-map fail
/// closed, with nothing left on the error. Schema validation is the caller's.
Map<String, Object?> parseRegionJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) throw AppError.unknown;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw AppError.unknown;
  }
  if (decoded is! Map) throw AppError.unknown;
  return Map<String, Object?>.from(decoded);
}

/// Drops the SDK message: it can carry the transcript.
AppError aiLogicFailure(Object error) {
  if (error is AppError) return error;
  if (error is SocketException || error is TimeoutException) {
    return .noInternet;
  }
  if (error is FirebaseException) return AppError.fromFirebaseCode(error.code);
  if (error is FirebaseAIException || error is FirebaseAISdkException) {
    return .serviceUnavailable;
  }
  // A release build obfuscates package type names, so the HTTP client's
  // exception cannot be recognised here. The controls show unknown as a
  // failed transcription. Socket and timeout stay offline: those types are
  // in the SDK and keep their names.
  return .unknown;
}

/// In-memory stand-in. Tests set results or [error] before the call.
class FakeAiLogicService implements AiLogicService {
  FakeAiLogicService({this.result, this.error});

  SymptomTranscript? result;
  Exception? error;

  /// Each call's mime type and byte length. The bytes themselves are not kept.
  final List<({int byteLength, String mimeType})> calls = [];

  /// Region reads to return, and what each call asked without identifiers.
  Map<String, Object?>? regionResult;
  final List<Map<String, Object?>> regionCalls = [];

  /// Narration bytes to return, and what each call asked without the text.
  Uint8List? speechResult;
  final List<({String languageCode, String voice, String model})> speechCalls =
      [];

  @override
  Future<SymptomTranscript> transcribeSymptoms(
    Uint8List wav, {
    required String mimeType,
  }) async {
    calls.add((byteLength: wav.length, mimeType: mimeType));
    final thrown = error;
    if (thrown != null) throw thrown;
    return result ?? const SymptomTranscript(transcript: '', language: 'en');
  }

  @override
  Future<Map<String, Object?>> readRegion({
    required Uint8List imageBytes,
    required String imageMime,
    String question = '',
    String stain = '',
  }) async {
    regionCalls.add({
      'byteLength': imageBytes.length,
      'imageMime': imageMime,
      'hasQuestion': question.isNotEmpty,
      'hasStain': stain.isNotEmpty,
    });
    final thrown = error;
    if (thrown != null) throw thrown;
    return regionResult ?? {};
  }

  @override
  Future<Uint8List> speakExplanation({
    required String text,
    required String languageCode,
    required String voice,
    required String model,
  }) async {
    speechCalls.add((languageCode: languageCode, voice: voice, model: model));
    final thrown = error;
    if (thrown != null) throw thrown;
    return speechResult ?? Uint8List(0);
  }
}
