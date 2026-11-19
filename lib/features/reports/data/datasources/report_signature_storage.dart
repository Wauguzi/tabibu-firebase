import 'package:firebase_storage/firebase_storage.dart';
import 'package:tabibu/core/constants/enums.dart';

/// Reads `reports/{caseUid}/{reportUid}/signature-{sha256}.png`.
/// The download checks the hash before anything is drawn.
class ReportSignatureStorage {
  ReportSignatureStorage(this._storage);

  final FirebaseStorage _storage;

  Future<List<int>> read(String path) async {
    final data = await _storage.ref(path).getData();
    if (data == null || data.isEmpty) throw AppError.dataNotFound;
    return data;
  }
}
