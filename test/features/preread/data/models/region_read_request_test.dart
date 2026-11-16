import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';

void main() {
  group('RegionReadRequest', () {
    test('builds the exact template input map', () {
      final request = RegionReadRequest(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        question: 'What is this?',
        stain: 'H&E',
      );

      expect(request.toTemplateInputs(), {
        'imageMime': 'image/png',
        // cspell:disable-next-line
        'imageData': 'AQID',
        'question': 'What is this?',
        'stain': 'H&E',
      });
    });

    test('omits an empty question and stain', () {
      final request = RegionReadRequest(imageBytes: Uint8List.fromList([1]));

      expect(
        request.toTemplateInputs().keys,
        containsAll(['imageMime', 'imageData']),
      );
      expect(request.toTemplateInputs().containsKey('question'), isFalse);
      expect(request.toTemplateInputs().containsKey('stain'), isFalse);
    });

    test('carries no identifier, only pixels and short text', () {
      final request = RegionReadRequest(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        question: 'q',
        stain: 's',
      );

      expect(request.toTemplateInputs().keys.toSet(), {
        'imageMime',
        'imageData',
        'question',
        'stain',
      });
    });

    test('cleans a typed question', () {
      expect(RegionReadRequest.cleanQuestion('  What?  '), 'What?');
      expect(RegionReadRequest.cleanQuestion('What?\u200b'), 'What?');
      expect(RegionReadRequest.cleanQuestion('   '), isEmpty);
      expect(
        RegionReadRequest.cleanQuestion('x' * 300).length,
        lessThanOrEqualTo(RegionReadRequest.maxQuestionLength),
      );
    });
  });
}
