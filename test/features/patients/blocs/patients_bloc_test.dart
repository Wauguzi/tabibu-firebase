import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_bloc.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';

class MockPatientSync extends Mock implements PatientSync {}

class _MockAnalytics extends Mock implements AnalyticsService {}

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
    late _MockAnalytics analytics;

    setUp(() {
      sync = MockPatientSync();
      analytics = _MockAnalytics();
      when(() => analytics.logPatientAdded()).thenAnswer((_) async {});
    });

    blocTest<PatientsBloc, PatientsState>(
      'add offline caches the patient as pending and emits it',
      build: () {
        final pending = _row();
        when(() => sync.remember(any())).thenAnswer((_) async => pending);
        when(
          () => sync.drain(any(), isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((_) async => [pending]);
        return PatientsBloc(sync, analytics);
      },
      act: (bloc) =>
          bloc.add(PatientsAdded(doctorUid: 'doc-1', patient: _row())),
      expect: () => [
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) {
        verify(() => sync.remember(any())).called(1);
        verify(() => analytics.logPatientAdded()).called(1);
        verify(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).called(1);
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'sync calls drain once and replaces pending rows with synced ones',
      build: () {
        when(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((_) async => [_row(synced: true)]);
        return PatientsBloc(sync, analytics);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadInProgress(patients: [_row()], doctorUid: 'doc-1'),
        PatientsLoadSuccess(patients: [_row(synced: true)], doctorUid: 'doc-1'),
      ],
      verify: (_) => verify(
        () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
      ).called(1),
    );

    blocTest<PatientsBloc, PatientsState>(
      'alreadyInCare swaps the id',
      build: () {
        when(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((_) async => [_row(id: 'server-id', synced: true)]);
        return PatientsBloc(sync, analytics);
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
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((_) async => [_row(held: true)]);
        return PatientsBloc(sync, analytics);
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
        when(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((_) async => [_row()]);
        return PatientsBloc(sync, analytics);
      },
      seed: () => PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      act: (bloc) => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadInProgress(patients: [_row()], doctorUid: 'doc-1'),
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) {
        verify(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).called(1);
        verifyNever(() => sync.remember(any()));
      },
    );

    blocTest<PatientsBloc, PatientsState>(
      'load reads the cache and does not send',
      build: () {
        when(() => sync.load('doc-1')).thenAnswer((_) async => [_row()]);
        return PatientsBloc(sync, analytics);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
      verify: (_) => verifyNever(
        () => sync.drain(any(), isCurrent: any(named: 'isCurrent')),
      ),
    );

    test(
      'a sync that finishes after sign-out shows and writes nothing',
      () async {
        final gate = Completer<List<PatientModel>>();
        bool Function()? check;
        when(
          () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
        ).thenAnswer((inv) {
          check = inv.namedArguments[#isCurrent] as bool Function()?;
          return gate.future;
        });
        final bloc = PatientsBloc(sync, analytics);
        addTearDown(bloc.close);
        final seen = <PatientsState>[];
        final sub = bloc.stream.listen(seen.add);
        addTearDown(sub.cancel);

        bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const PatientsReset());
        await Future<void>.delayed(Duration.zero);
        expect(check!(), isFalse);
        gate.complete([_row(synced: true)]);
        await Future<void>.delayed(Duration.zero);

        expect(bloc.state, const PatientsInitial());
        expect(
          seen.where((s) => s is PatientsLoadSuccess && s.patients.isNotEmpty),
          isEmpty,
        );
      },
    );

    test("the next doctor's first sync runs, behind the last one's", () async {
      final gate = Completer<List<PatientModel>>();
      when(
        () => sync.drain('doc-1', isCurrent: any(named: 'isCurrent')),
      ).thenAnswer((_) => gate.future);
      final other = _row().copyWith(patientId: 'p-b', doctorUids: ['doc-2']);
      when(
        () => sync.drain('doc-2', isCurrent: any(named: 'isCurrent')),
      ).thenAnswer((_) async => [other]);
      final bloc = PatientsBloc(sync, analytics);
      addTearDown(bloc.close);

      bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1'));
      await Future<void>.delayed(Duration.zero);
      bloc
        ..add(const PatientsReset())
        ..add(const PatientsSyncRequested(doctorUid: 'doc-2'));
      await Future<void>.delayed(Duration.zero);
      gate.complete([_row(synced: true)]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state.doctorUid, 'doc-2');
      expect(bloc.state.patients, [other]);
      expect(bloc.state.patientsFor('doc-1'), isEmpty);
    });

    blocTest<PatientsBloc, PatientsState>(
      "a cached row that is not this doctor's is never shown",
      build: () {
        when(() => sync.load('doc-1')).thenAnswer(
          (_) async => [
            _row(),
            _row().copyWith(patientId: 'p-x', doctorUids: ['doc-9']),
          ],
        );
        return PatientsBloc(sync, analytics);
      },
      act: (bloc) => bloc.add(const PatientsLoadRequested(doctorUid: 'doc-1')),
      expect: () => [
        PatientsLoadSuccess(patients: [_row()], doctorUid: 'doc-1'),
      ],
    );
  });
}
