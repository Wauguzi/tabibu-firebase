import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';

/// Runs a slide-region read against the server prompt template. The live
/// implementation delegates to `AiLogicService`; the UI only ever sees this
/// seam.
abstract class RegionReadClient {
  Future<RegionReadResult> readRegion(RegionReadRequest request);
}

/// In-memory fake: returns [result] (or throws [error]) and keeps the last
/// request for assertions.
class FakeRegionReadClient implements RegionReadClient {
  FakeRegionReadClient({this.result, this.error});

  final RegionReadResult? result;
  final Exception? error;
  RegionReadRequest? lastRequest;
  int calls = 0;

  @override
  Future<RegionReadResult> readRegion(RegionReadRequest request) async {
    lastRequest = request;
    calls++;

    final failure = error;
    if (failure != null) throw failure;
    return result ??
        const RegionReadResult(
          impression: 'A calm field of lymphocytes.',
          features: ['Even spacing', 'Round nuclei'],
          uncertainty: .low,
          caveat: 'A read of one region, not a diagnosis.',
        );
  }
}
