import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_bloc.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';

class MockPatientSync extends Mock implements PatientSync {}

PatientModel _row({
  String id = 'id-1',
  bool synced = false,
  bool held = false,
}) => PatientModel.empty().copyWith(
  patientId: id,
  uid: '',
  createdByUid: 'doc-1',
  firstName: 'Amina',
  lastName: 'Otieno',
  phoneNumber: '+254712345678',
  dateOfBirth: '1990-05-14',
  doctorUids: const ['doc-1'],
  synced: synced,
  held: held,
);

void main() {
  setUpAll(() => registerFallbackValue(PatientModel.empty()));

  group('PatientsBloc', () {
    late MockPatientSync sync;

    setUp(() => sync = MockPatientSync());

    blocTest<PatientsBloc, PatientsState>(
      'add offline caches the patient as pending and emits it',
      build: () {
        final pending = _row();
        when(() => sync.remember(any())).thenAnswer((_) async => pending);
        when(() => sync.drain(any())).thenAnswer((_) async => [pending]);
        return PatientsBloc(sync);
      },
      act: (bloc) =>
          bloc.add(PatientsAdded(doctorUid: 'doc-1', patient: _row())),
      expect: () => [
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) {
        verify(() => sync.remember(any())).called(1);
        verify(() => sync.drain('doc-1')).called(1);
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'sync calls drain once and replaces pending rows with synced ones',
      build: () {
        when(
          () => sync.drain('doc-1'),
        ).thenAnswer((_) async => [_row(synced: true)]);
        return PatientsBloc(sync);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadInProgress(patients: [_row()], doctorUid: 'doc-1'),
        PatientsLoadSuccess(patients: [_row(synced: true)], doctorUid: 'doc-1'),
      ],
      verify: (_) => verify(() => sync.drain('doc-1')).called(1),
    );

    blocTest<PatientsBloc, PatientsState>(
      'alreadyInCare swaps the id',
      build: () {
        when(
          () => sync.drain('doc-1'),
        ).thenAnswer((_) async => [_row(id: 'server-id', synced: true)]);
        return PatientsBloc(sync);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        isA<PatientsLoadInProgress>(),
        isA<PatientsLoadSuccess>().having(
          (state) => state.patients.single.patientId,
          'patientId',
          'server-id',
        ),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'patientExists keeps the mark',
      build: () {
        when(
          () => sync.drain('doc-1'),
        ).thenAnswer((_) async => [_row(held: true)]);
        return PatientsBloc(sync);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        isA<PatientsLoadInProgress>(),
        isA<PatientsLoadSuccess>().having(
          (state) => state.patients.single.held,
          'held',
          isTrue,
        ),
      ],
    );

    blocTest<PatientsBloc, PatientsState>(
      'a sync while offline changes nothing',
      build: () {
        when(() => sync.drain('doc-1')).thenAnswer((_) async => [_row()]);
        return PatientsBloc(sync);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadInProgress(patients: [_row()], doctorUid: 'doc-1'),
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) {
        verify(() => sync.drain('doc-1')).called(1);
        verifyNever(() => sync.remember(any()));
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'load reads the cache and does not send',
      build: () {
        when(() => sync.load('doc-1')).thenAnswer((_) async => [_row()]);
        return PatientsBloc(sync);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) => verifyNever(() => sync.drain(any())),
    );
  });
}
