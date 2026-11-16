import 'dart:typed_data';

import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/cases/data/speech_client.dart';
import 'package:tabibu/features/cases/data/speech_request.dart';

/// Narrates through [AiLogicService]. An unknown language fails closed
/// rather than mispronouncing.
class AiLogicSpeechClient implements SpeechClient {
  AiLogicSpeechClient(this._service);

  final AiLogicService _service;

  @override
  Future<Uint8List> speak(SpeechRequest request) {
    final code = SpeechRequest.languageCodeFor(request.language);
    if (code == null) return Future.error(AppError.unknown);
    return _service.speakExplanation(
      text: request.text,
      languageCode: code,
      voice: request.voice,
      model: request.model,
    );
  }
}
