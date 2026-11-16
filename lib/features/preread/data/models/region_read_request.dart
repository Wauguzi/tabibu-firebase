import 'dart:convert';
import 'dart:typed_data';

import 'package:tabibu/core/helpers/paste_sanitizer.dart';

/// A slide-region read request: the captured region plus the pathologist's
/// optional question. Carries pixels and short text only — never an order
/// number, name, uid or anything else that identifies the patient.
class RegionReadRequest {
  const RegionReadRequest({
    required this.imageBytes,
    this.question = '',
    this.stain = '',
  });

  /// PNG: the capture path has no JPEG encoder and no new dependency is
  /// approved. Inline PNG sits well under the 20 MB model input cap.
  static const imageMime = 'image/png';

  static const maxQuestionLength = 300;

  final Uint8List imageBytes;

  /// Cleaned at submit; '' when the pathologist asked nothing.
  final String question;
  final String stain;

  /// Trims and sanitises a typed question. The field caps length at
  /// [maxQuestionLength]; sanitising only ever shrinks.
  static String cleanQuestion(String raw) => sanitizePaste(raw.trim());

  /// The exact template input map: pixels plus short text, nothing else.
  Map<String, String> toTemplateInputs() => {
    'imageMime': imageMime,
    'imageData': base64Encode(imageBytes),
    if (question.isNotEmpty) 'question': question,
    if (stain.isNotEmpty) 'stain': stain,
  };
}
