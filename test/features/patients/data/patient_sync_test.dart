import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/utils/sync_cursor.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';

class _MemoryStore implements PatientStore {
  final rows = <String, PatientModel>{};

  @override
  Future<List<PatientModel>> carePatients(String doctorUid) async => [
    for (final row in rows.values)
      if (row.doctorUids.contains(doctorUid)) row,
  ];

  @override
  Future<void> put(List<PatientModel> patients) async {
    for (final patient in patients) {
      rows[patient.patientId] = patient;
    }
  }

  /// Same merge as the cache: an unsynced local row is kept.
  @override
  Future<void> cacheFromCloud(List<PatientModel> patients) async {
    for (final patient in patients) {
      final cached = rows[patient.patientId];
      if (cached != null &&
          !cloudRowWins(
            cachedSynced: cached.synced,
            cachedLastUpdatedAt: cached.lastUpdatedAt,
            incomingLastUpdatedAt: patient.lastUpdatedAt,
          )) {
        continue;
      }
      rows[patient.patientId] = patient.copyWith(synced: true);
    }
  }
}

PatientModel _pending(String id) => PatientModel.empty().copyWith(
  patientId: id,
  uid: '',
  createdByUid: 'doc-1',
  firstName: 'Amina',
  lastName: 'Otieno',
  sex: 'Female',
  dateOfBirth: '1990-05-14',
  phoneNumber: '+254712345678',
  county: 'Nairobi',
  subCounty: 'Kibra',
  doctorUids: const ['doc-1'],
  language: 'sw',
  synced: false,
);

void main() {
  group('PatientSync', () {
    late _MemoryStore store;
    late bool online;
    late List<String> calls;
    late List<String> fetches;
    late List<PatientModel>? remote;

    setUp(() {
      store = _MemoryStore();
      online = false;
      calls = [];
      fetches = [];
      remote = null;
    });

    PatientSync sync({
      AddPatientReply Function(PatientModel patient)? reply,
      PatientAreaIds? Function(PatientModel patient)? areas,
    }) => PatientSync(
      store: store,
      online: () async => online,
      careTeam: (doctorUid) async {
        fetches.add(doctorUid);
        return remote ?? await store.carePatients(doctorUid);
      },
      areaIds: (patient) async =>
          areas == null ? (countyId: 47, subCountyId: 30) : areas(patient),
      addPatient: (patient, ids) async {
        calls.add(patient.patientId);
        expect(ids.countyId, 47);
        return reply?.call(patient) ?? AddPatientCreated(patient.patientId);
      },
    );

    test('offline caches the patient as pending and does not call', () async {
      final pending = await sync().remember(_pending('id-1'));
      final rows = await sync().drain('doc-1');
      expect(pending.synced, isFalse);
      expect(calls, isEmpty);
      expect(rows.single.patientId, 'id-1');
      expect(rows.single.synced, isFalse);
    });

    test('reconnecting calls addPatient once with the same id', () async {
      final client = sync();
      await client.remember(_pending('id-1'));
      online = true;
      await client.drain('doc-1');
      await client.drain('doc-1');
      expect(calls, ['id-1']);
      expect(store.rows['id-1']!.synced, isTrue);
    });

    test(
      'alreadyInCare swaps the pending id for the existing patient',
      () async {
        final client = sync(
          reply: (_) => const AddPatientAlreadyInCare('server-id'),
        );
        await client.remember(_pending('id-1'));
        online = true;
        final rows = await client.drain('doc-1');
        expect(calls, ['id-1']);
        expect(rows.single.patientId, 'server-id');
        expect(rows.single.synced, isTrue);
        expect(store.rows['id-1']!.doctorUids, isEmpty);
      },
    );

    test(
      'patientExists keeps the row marked and does not send again',
      () async {
        final client = PatientSync(
          store: store,
          online: () async => online,
          careTeam: (doctorUid) async {
            fetches.add(doctorUid);
            return remote ?? await store.carePatients(doctorUid);
          },
          areaIds: (_) async => (countyId: 47, subCountyId: 30),
          addPatient: (patient, _) async {
            calls.add(patient.patientId);
            throw AppError.patientExists;
          },
        );
        await client.remember(_pending('id-1'));
        online = true;
        final rows = await client.drain('doc-1');
        await client.drain('doc-1');
        expect(calls, ['id-1']);
        expect(rows.single.held, isTrue);
        expect(rows.single.synced, isFalse);
        expect(rows.single.patientId, 'id-1');
      },
    );

    test('fetched patients are cached and returned with their photo', () async {
      online = true;
      remote = [
        _pending('booked').copyWith(
          synced: true,
          profilePictureUrl: 'https://example.test/amina.jpg',
        ),
      ];
      final rows = await sync().drain('doc-1');
      expect(fetches, ['doc-1']);
      expect(calls, isEmpty);
      expect(rows.single.profilePictureUrl, 'https://example.test/amina.jpg');
      expect(
        store.rows['booked']!.profilePictureUrl,
        'https://example.test/amina.jpg',
      );
      expect(store.rows['booked']!.synced, isTrue);
    });

    test('a pending row is not overwritten by an older server copy', () async {
      await sync().remember(
        _pending('id-1').copyWith(
          firstName: 'Amina',
          lastUpdatedAt: '2026-11-19T12:00:00.000Z',
        ),
      );
      online = true;
      remote = [
        _pending('id-1').copyWith(
          firstName: 'Old',
          profilePictureUrl: 'https://example.test/old.jpg',
          lastUpdatedAt: '2026-11-01T00:00:00.000Z',
          synced: true,
        ),
      ];
      final rows = await sync(areas: (_) => null).drain('doc-1');
      expect(calls, isEmpty);
      expect(rows.single.firstName, 'Amina');
      expect(rows.single.profilePictureUrl, isEmpty);
      expect(rows.single.synced, isFalse);
    });

    test(
      'a server-removed synced patient is evicted and a pending one kept',
      () async {
        await store.put([
          _pending('gone').copyWith(synced: true),
          _pending('walk-in'),
          _pending('held-one').copyWith(held: true),
        ]);
        online = true;
        remote = [
          _pending('booked').copyWith(
            profilePictureUrl: 'https://example.test/amina.jpg',
            synced: true,
          ),
        ];
        final rows = await sync(areas: (_) => null).drain('doc-1');
        expect(rows.map((row) => row.patientId).toSet(), {
          'walk-in',
          'held-one',
          'booked',
        });
        expect(
          rows.firstWhere((row) => row.patientId == 'walk-in').synced,
          isFalse,
        );
        expect(
          rows.firstWhere((row) => row.patientId == 'held-one').held,
          isTrue,
        );
        expect(store.rows['gone']!.doctorUids, isEmpty);
      },
    );

    test('offline returns the cache and calls nothing', () async {
      await store.put([_pending('id-1')]);
      remote = [
        _pending(
          'booked',
        ).copyWith(profilePictureUrl: 'https://example.test/amina.jpg'),
      ];
      final rows = await sync().drain('doc-1');
      expect(fetches, isEmpty);
      expect(calls, isEmpty);
      expect(rows.single.patientId, 'id-1');
      expect(store.rows.containsKey('booked'), isFalse);
    });
  });
}
