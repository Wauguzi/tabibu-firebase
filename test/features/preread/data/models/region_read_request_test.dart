import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';

void main() {
  group('RegionReadRequest', () {
    test('cleans a typed question', () {
      expect(RegionReadRequest.cleanQuestion('  What?  '), 'What?');
      expect(RegionReadRequest.cleanQuestion('What?\u200b'), 'What?');
      expect(RegionReadRequest.cleanQuestion('   '), isEmpty);
      expect(
        RegionReadRequest.cleanQuestion('x' * 300).length,
        lessThanOrEqualTo(RegionReadRequest.maxQuestionLength),
      );
    });

    test('sends PNG, the only encoder on this path', () {
      expect(RegionReadRequest.imageMime, 'image/png');
    });
  });
}
