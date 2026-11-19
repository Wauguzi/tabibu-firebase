import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:injectable/injectable.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/facilities_helper.dart';
import 'package:tabibu/core/helpers/hive_helper.dart';
import 'package:tabibu/core/services/internet_service.dart';
import 'package:tabibu/features/patients/data/datasources/patient_firebase.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';

/// County and sub-county ids the `addPatient` callable expects.
typedef PatientAreaIds = ({int countyId, int subCountyId});

/// What `addPatient` answered for a client-minted id.
sealed class AddPatientReply {
  const AddPatientReply(this.patientId);

  final String patientId;
}

final class AddPatientCreated extends AddPatientReply {
  const AddPatientCreated(super.patientId);
}

final class AddPatientAlreadyInCare extends AddPatientReply {
  const AddPatientAlreadyInCare(super.patientId);
}

/// The doctor's patients as cached on the phone.
abstract class PatientStore {
  Future<List<PatientModel>> carePatients(String doctorUid);

  Future<void> put(List<PatientModel> patients);

  /// Server rows. An unsynced local row wins, the same rule as the cache.
  Future<void> cacheFromCloud(List<PatientModel> patients);
}

class HivePatientStore implements PatientStore {
  HivePatientStore(this._hive);

  final HiveHelper _hive;

  @override
  Future<List<PatientModel>> carePatients(String doctorUid) =>
      _hive.getCachedCarePatients(doctorUid);

  @override
  Future<void> put(List<PatientModel> patients) =>
      _hive.cachePatients(patients, fromCloud: false);

  @override
  Future<void> cacheFromCloud(List<PatientModel> patients) =>
      _hive.cachePatients(patients, fromCloud: true);
}

/// Caches a doctor-added patient at once, then calls `addPatient` when the
/// network is there. The client id is the document id, so a retry is the
/// same patient. Widgets never build one: getIt does.
@lazySingleton
class PatientSync {
  PatientSync({
    required this.store,
    required this.online,
    required this.careTeam,
    required this.addPatient,
    required this.areaIds,
  });

  @factoryMethod
  factory PatientSync.installed(
    FirebaseFunctions functions,
    FacilitiesHelper facilities,
    HiveHelper hive,
    InternetService internet,
    PatientFirebase patients,
  ) {
    return PatientSync(
      store: HivePatientStore(hive),
      online: internet.check,
      careTeam: patients.fetchCareTeam,
      areaIds: (patient) => _areaIds(facilities, patient),
      addPatient: (patient, ids) => _callAddPatient(functions, patient, ids),
    );
  }

  final PatientStore store;
  final Future<bool> Function() online;
  final Future<List<PatientModel>> Function(String doctorUid) careTeam;
  final Future<AddPatientReply> Function(
    PatientModel patient,
    PatientAreaIds ids,
  )
  addPatient;
  final Future<PatientAreaIds?> Function(PatientModel patient) areaIds;

  /// The doctor's cached rows, without sending any of them.
  Future<List<PatientModel>> load(String doctorUid) =>
      store.carePatients(doctorUid);

  Future<PatientModel> remember(PatientModel patient) async {
    final pending = patient.copyWith(uid: '', synced: false, held: false);
    await store.put([pending]);
    return pending;
  }

  /// Sends every pending row once, then replaces this doctor's list with the
  /// server's. Offline leaves the cache. A pending or held row stays; a
  /// synced row the server no longer lists leaves this doctor's cache.
  Future<List<PatientModel>> drain(String doctorUid) async {
    final rows = await store.carePatients(doctorUid);
    if (!await online()) return rows;
    for (final row in rows) {
      if (row.synced || row.held) continue;
      final ids = await areaIds(row);
      if (ids == null) continue;
      try {
        final reply = await addPatient(row, ids);
        await _apply(rows, row, reply);
      } on AppError catch (error) {
        if (error != AppError.patientExists) rethrow;
        final held = row.copyWith(held: true, synced: false);
        await store.put([held]);
      }
    }
    final remote = await careTeam(doctorUid);
    await store.cacheFromCloud(remote);
    await _dropRemoved(doctorUid, remote);
    return await store.carePatients(doctorUid);
  }

  /// A cloud merge never deletes. Clearing this doctor's uid hides the row
  /// and leaves the box entry for anyone else it still belongs to.
  Future<void> _dropRemoved(String doctorUid, List<PatientModel> remote) async {
    final listed = {for (final row in remote) row.patientId};
    final gone = [
      for (final row in await store.carePatients(doctorUid))
        if (!row.held && row.synced && !listed.contains(row.patientId))
          row.copyWith(
            doctorUids: [
              for (final uid in row.doctorUids)
                if (uid != doctorUid) uid,
            ],
          ),
    ];
    if (gone.isEmpty) return;
    await store.put(gone);
  }

  Future<List<PatientModel>> _apply(
    List<PatientModel> rows,
    PatientModel pending,
    AddPatientReply reply,
  ) async {
    if (reply is AddPatientAlreadyInCare &&
        reply.patientId != pending.patientId) {
      final kept = pending.copyWith(
        patientId: reply.patientId,
        synced: true,
        held: false,
      );
      // The pending id is no longer this patient. Dropping them from the
      // doctor's list hides the row without deleting the box entry.
      await store.put([
        pending.copyWith(doctorUids: const [], synced: true, held: false),
        kept,
      ]);
      return [
        for (final row in rows)
          if (row.patientId != pending.patientId) row,
        kept,
      ];
    }
    final synced = pending.copyWith(synced: true, held: false);
    await store.put([synced]);
    return _swap(rows, synced);
  }

  List<PatientModel> _swap(List<PatientModel> rows, PatientModel next) => [
    for (final row in rows)
      if (row.patientId != next.patientId) row,
    next,
  ];
}

Future<PatientAreaIds?> _areaIds(
  FacilitiesHelper facilities,
  PatientModel patient,
) async {
  final county = (await facilities.counties()).firstWhereOrNull(
    (row) => row.name == patient.county,
  );
  if (county == null) return null;
  if (patient.subCounty.isEmpty) {
    return (countyId: county.id, subCountyId: 0);
  }
  final sub = (await facilities.nairobiSubCounties()).firstWhereOrNull(
    (row) => row.name == patient.subCounty,
  );
  if (sub == null) return null;
  return (countyId: county.id, subCountyId: sub.id);
}

Future<AddPatientReply> _callAddPatient(
  FirebaseFunctions functions,
  PatientModel patient,
  PatientAreaIds ids,
) async {
  try {
    final result = await functions.httpsCallable('addPatient').call<dynamic>({
      'patientId': patient.patientId,
      'firstName': patient.firstName,
      'middleName': patient.middleName,
      'lastName': patient.lastName,
      'sex': patient.sex,
      'dateOfBirth': patient.dateOfBirth,
      'phoneNumber': patient.phoneNumber,
      'email': patient.email,
      'countyId': ids.countyId,
      'subCountyId': ids.subCountyId,
      'language': patient.language,
    });
    final data = result.data;
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final id = map['patientId'] as String? ?? '';
    return map['status'] == 'alreadyInCare'
        ? AddPatientAlreadyInCare(id)
        : AddPatientCreated(id);
  } on FirebaseFunctionsException catch (error) {
    throw AppError.fromFunctionsException(error);
  }
}
