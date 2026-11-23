import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';

/// The doctor's patients on the server. A single `array-contains` filter
/// needs no composite index, so each sync reads the whole care list.
@lazySingleton
class PatientFirebase {
  PatientFirebase({required this._firestore});

  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  Future<List<PatientModel>> fetchCareTeam(String doctorUid) async {
    if (doctorUid.isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection('patients')
          .where('doctorUids', arrayContains: doctorUid)
          .get(const GetOptions(source: Source.server));
      return [
        for (final doc in snap.docs)
          PatientModel.fromJson({...doc.data(), 'patientId': doc.id}),
      ];
    } on Exception catch (error, stackTrace) {
      if (kDebugMode) {
        _logger.e('Care team fetch failed: $error', stackTrace: stackTrace);
      }
      throw switch (error) {
        AppError() => error,
        FirebaseException(:final code) => AppError.fromFirebaseCode(code),
        _ => AppError.unknown,
      };
    }
  }
}
