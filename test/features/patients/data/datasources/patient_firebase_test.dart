import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/patients/data/datasources/patient_firebase.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';

void main() {
  group('fetchCareTeam', () {
    test(
      'the query is the care team, from the server, with no order',
      () async {
        final recording = _RecordingFirestore();
        final remote = PatientFirebase(firestore: recording);

        await remote.fetchCareTeam('doc-1');

        expect(recording.path, 'patients');
        expect(recording.field, 'doctorUids');
        expect(recording.arrayContains, 'doc-1');
        expect(recording.ordered, isFalse);
        expect(recording.source, Source.server);
      },
    );

    test('an empty doctor asks for nothing', () async {
      final recording = _RecordingFirestore();
      final remote = PatientFirebase(firestore: recording);

      expect(await remote.fetchCareTeam(''), isEmpty);
      expect(recording.path, isNull);
    });

    test('returns the care team and keeps each photo', () async {
      final firestore = FakeFirebaseFirestore();
      final mine = _patient('p1', doctors: const ['doc-1']);
      final other = _patient(
        'p2',
        doctors: const ['doc-2'],
        photo: 'https://example.test/other.jpg',
      );
      await firestore.collection('patients').doc('p1').set(mine.toJson());
      await firestore.collection('patients').doc('p2').set(other.toJson());
      final remote = PatientFirebase(firestore: firestore);

      final rows = await remote.fetchCareTeam('doc-1');

      expect(rows, hasLength(1));
      expect(rows.single.patientId, 'p1');
      expect(rows.single.profilePictureUrl, 'https://example.test/amina.jpg');
    });
  });
}

PatientModel _patient(
  String id, {
  required List<String> doctors,
  String photo = 'https://example.test/amina.jpg',
}) => PatientModel.empty().copyWith(
  patientId: id,
  uid: 'user-$id',
  firstName: 'Amina',
  lastName: 'Otieno',
  doctorUids: doctors,
  profilePictureUrl: photo,
  createdAt: '2026-11-18T09:00:00.000Z',
  lastUpdatedAt: '2026-11-18T09:00:00.000Z',
);

/// Records the one care-team query and answers with no documents.
class _RecordingFirestore extends Fake implements FirebaseFirestore {
  String? path;
  Object? field;
  Object? arrayContains;
  bool ordered = false;
  Source? source;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    path = collectionPath;
    return _RecordingCollection(this);
  }
}

// A Fake can only stand in for the sealed Firestore types via implements;
// every member below is hand-written, which is all the test needs.
// ignore: subtype_of_sealed_class
class _RecordingCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _RecordingCollection(this._firestore);

  final _RecordingFirestore _firestore;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    _firestore.field = field;
    _firestore.arrayContains = arrayContains;
    return _RecordingQuery(_firestore);
  }
}

// A Fake can only stand in for the sealed Firestore types via implements;
// every member below is hand-written, which is all the test needs.
// ignore: subtype_of_sealed_class
class _RecordingQuery extends Fake implements Query<Map<String, dynamic>> {
  _RecordingQuery(this._firestore);

  final _RecordingFirestore _firestore;

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    _firestore.ordered = true;
    return this;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    _firestore.source = options?.source;
    return _EmptySnap();
  }
}

class _EmptySnap extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
}
