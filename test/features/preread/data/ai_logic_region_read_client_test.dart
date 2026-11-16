import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/preread/data/ai_logic_region_read_client.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';

void main() {
  group('AiLogicRegionReadClient', () {
    test('validates the template JSON into a read', () async {
      final service = FakeAiLogicService()
        ..regionResult = {
          'impression': 'Calm lymphocytes.',
          'features': ['Even spacing'],
          'uncertainty': 'low',
          'caveat': 'One region.',
        };
      final client = AiLogicRegionReadClient(service);

      final result = await client.readRegion(
        RegionReadRequest(imageBytes: Uint8List.fromList([1])),
      );

      expect(result.impression, 'Calm lymphocytes.');
      expect(result.uncertainty, RegionUncertainty.low);
    });

    test('a bad read fails closed', () async {
      final service = FakeAiLogicService()
        ..regionResult = {'impression': 'Calm.'};
      final client = AiLogicRegionReadClient(service);

      await expectLater(
        client.readRegion(
          RegionReadRequest(imageBytes: Uint8List.fromList([1])),
        ),
        throwsA(AppError.unknown),
      );
    });
  });
}
