import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';

void main() {
  Map<String, Object?> valid() => {
    'impression': 'Calm lymphocytes.',
    'features': ['Even spacing', 'Round nuclei'],
    'uncertainty': 'medium',
    'caveat': 'One region, not a diagnosis.',
  };

  group('RegionReadResult.tryParse', () {
    test('parses a valid read', () {
      final result = RegionReadResult.tryParse(valid());

      expect(result?.impression, 'Calm lymphocytes.');
      expect(result?.features, ['Even spacing', 'Round nuclei']);
      expect(result?.uncertainty, RegionUncertainty.medium);
      expect(result?.caveat, 'One region, not a diagnosis.');
    });

    test('accepts an empty feature list and ignores extra keys', () {
      final result = RegionReadResult.tryParse({
        ...valid(),
        'features': <String>[],
        'diagnosis': 'ignored',
      });

      expect(result?.features, isEmpty);
    });

    test('rejects a bad read', () {
      expect(RegionReadResult.tryParse(null), isNull);
      expect(RegionReadResult.tryParse('nope'), isNull);
      expect(RegionReadResult.tryParse({}), isNull);
      expect(
        RegionReadResult.tryParse({...valid(), 'impression': '  '}),
        isNull,
      );
      expect(RegionReadResult.tryParse({...valid(), 'caveat': ''}), isNull);
      expect(
        RegionReadResult.tryParse({...valid(), 'uncertainty': 'certain'}),
        isNull,
      );
      expect(
        RegionReadResult.tryParse({...valid(), 'uncertainty': 'MEDIUM'}),
        isNull,
      );
      expect(
        RegionReadResult.tryParse({...valid(), 'features': 'Even spacing'}),
        isNull,
      );
      expect(
        RegionReadResult.tryParse({
          ...valid(),
          'features': ['ok', 42],
        }),
        isNull,
      );
    });

    test('uncertainty matches its three wire words only', () {
      expect(RegionUncertainty.fromWire('low'), RegionUncertainty.low);
      expect(RegionUncertainty.fromWire('medium'), RegionUncertainty.medium);
      expect(RegionUncertainty.fromWire('high'), RegionUncertainty.high);
      expect(RegionUncertainty.fromWire(''), isNull);
      expect(RegionUncertainty.fromWire(null), isNull);
      expect(RegionUncertainty.fromWire('Low'), isNull);
    });
  });
}
