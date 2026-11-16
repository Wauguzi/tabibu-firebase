import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/preread/data/models/region_read_request.dart';
import 'package:tabibu/features/preread/data/models/region_read_result.dart';
import 'package:tabibu/features/preread/data/region_read_client.dart';

/// Runs region reads through [AiLogicService], validating the template JSON
/// into a read. Anything malformed fails closed.
class AiLogicRegionReadClient implements RegionReadClient {
  AiLogicRegionReadClient(this._service);

  final AiLogicService _service;

  @override
  Future<RegionReadResult> readRegion(RegionReadRequest request) async {
    final json = await _service.readRegion(
      imageBytes: request.imageBytes,
      imageMime: RegionReadRequest.imageMime,
      question: request.question,
      stain: request.stain,
    );
    final parsed = RegionReadResult.tryParse(json);
    if (parsed == null) throw AppError.unknown;
    return parsed;
  }
}
