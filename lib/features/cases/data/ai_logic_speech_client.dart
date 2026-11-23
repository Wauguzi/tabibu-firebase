import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

/// Narrates through [AiLogicService]. An unknown language fails closed
/// rather than mispronouncing.
class AiLogicSpeechClient implements SpeechClient {
  AiLogicSpeechClient(this._service, {Logger? logger})
    : _logger = logger ?? Logger();

  final AiLogicService _service;
  final Logger _logger;

  @override
  Future<Uint8List> speak(SpeechRequest request) async {
    final code = SpeechRequest.languageCodeFor(request.language);
    if (code == null) {
      if (kDebugMode) {
        _logger.e('Listen speak refused: unknown language ${request.language}');
      }
      throw AppError.unknown;
    }
    try {
      return await _service.speakExplanation(
        text: request.text,
        languageCode: code,
        voice: request.voice,
        model: request.model,
      );
    } on Object catch (error) {
      if (kDebugMode) {
        _logger.e('Listen speak failed: ${error.runtimeType} (language $code)');
      }
      rethrow;
    }
  }
}
