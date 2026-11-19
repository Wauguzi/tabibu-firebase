import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/appointments/data/models/appointment_model.dart';
import 'package:tabibu/features/orders/presentation/widgets/order_patient_step.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_bloc.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('a pending patient from the bloc is listed and can be chosen', (
    tester,
  ) async {
    final bloc = _MockPatientsBloc();
    final pending = PatientModel.empty().copyWith(
      patientId: 'local-1',
      firstName: 'Amina',
      lastName: 'Otieno',
      doctorUids: const ['doc-1'],
      synced: false,
    );
    when(
      () => bloc.state,
    ).thenReturn(PatientsLoadSuccess(patients: [pending], doctorUid: 'doc-1'));
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    final picked = <PatientModel>[];

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 18),
            selectedAppointmentUid: '',
            onPick: (_) {},
            canAdd: true,
            county: 'Nairobi',
            subCounty: 'Kibra',
            onPickAdded: picked.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(l10n.addPatientPending), findsOneWidget);
    expect(find.text('Amina Otieno'), findsOneWidget);
    tester
        .widget<Tappable>(
          find.ancestor(
            of: find.text('Amina Otieno'),
            matching: find.byType(Tappable),
          ),
        )
        .onTap
        ?.call();
    expect(picked, [pending]);
  });

  testWidgets('load and pull-to-refresh ask the bloc to sync the list', (
    tester,
  ) async {
    final bloc = _MockPatientsBloc();
    when(() => bloc.state).thenReturn(const PatientsInitial());
    when(
      () => bloc.stream,
    ).thenAnswer((_) => Stream.value(const PatientsLoadSuccess()));

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 18),
            selectedAppointmentUid: '',
            onPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    verify(
      () => bloc.add(const PatientsLoadRequested(doctorUid: 'doc-1')),
    ).called(1);
    verify(
      () => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
    ).called(1);

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();

    verify(
      () => bloc.add(const PatientsSyncRequested(doctorUid: 'doc-1')),
    ).called(1);
  });

  testWidgets('a set profile picture shows, and an empty one stays initials', (
    tester,
  ) async {
    final bloc = _MockPatientsBloc();
    const photo = 'https://example.test/amina.jpg';
    final withPhoto = PatientModel.empty().copyWith(
      patientId: 'p-photo',
      firstName: 'Amina',
      lastName: 'Otieno',
      profilePictureUrl: photo,
      doctorUids: const ['doc-1'],
    );
    final noPhoto = PatientModel.empty().copyWith(
      patientId: 'p-plain',
      firstName: 'Grace',
      lastName: 'Atieno',
      doctorUids: const ['doc-1'],
    );
    when(() => bloc.state).thenReturn(
      PatientsLoadSuccess(patients: [withPhoto, noPhoto], doctorUid: 'doc-1'),
    );
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    debugNetworkImageHttpClientProvider = _NoImage.new;
    addTearDown(() => debugNetworkImageHttpClientProvider = null);

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [
              AppointmentModel(
                uid: 'a-1',
                status: 'Accepted',
                patientId: 'p-photo',
                patientName: 'Amina Otieno',
                doctorUid: 'doc-1',
                scheduledStart: '2026-11-18T09:00:00.000Z',
                scheduledEnd: '2026-11-18T09:30:00.000Z',
              ),
            ],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 18, 12),
            selectedAppointmentUid: '',
            onPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final avatars = tester.widgetList<Avatar>(find.byType(Avatar)).toList();
    expect(avatars.map((avatar) => avatar.name), [
      'Amina Otieno',
      'Grace Atieno',
    ]);
    expect((avatars.first.image! as NetworkImage).url, photo);
    expect(avatars.last.image, isNull);
  });

  testWidgets('each row reads by phone number, so two of one name differ, and '
      'a pending one keeps its warning', (tester) async {
    final bloc = _MockPatientsBloc();
    final visit = PatientModel.empty().copyWith(
      patientId: 'p-visit',
      firstName: 'Amina',
      lastName: 'Otieno',
      phoneNumber: '+254712000111',
      doctorUids: const ['doc-1'],
    );
    final pending = PatientModel.empty().copyWith(
      patientId: 'p-new',
      firstName: 'Amina',
      lastName: 'Otieno',
      phoneNumber: '+254712000222',
      doctorUids: const ['doc-1'],
      synced: false,
    );
    when(() => bloc.state).thenReturn(
      PatientsLoadSuccess(patients: [visit, pending], doctorUid: 'doc-1'),
    );
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [
              AppointmentModel(
                uid: 'a-1',
                status: 'Accepted',
                patientId: 'p-visit',
                patientName: 'Amina Otieno',
                doctorUid: 'doc-1',
                scheduledStart: '2026-11-18T09:00:00.000Z',
                scheduledEnd: '2026-11-18T09:30:00.000Z',
              ),
            ],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 18, 12),
            selectedAppointmentUid: '',
            onPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('+254712000111'), findsOneWidget);
    expect(
      find.text('+254712000222 · ${l10n.addPatientPending}'),
      findsOneWidget,
    );
  });

  testWidgets("pull-to-refresh is the dashboard's, in the primary colour", (
    tester,
  ) async {
    final bloc = _MockPatientsBloc();
    when(() => bloc.state).thenReturn(const PatientsLoadSuccess());
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 18),
            selectedAppointmentUid: '',
            onPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final context = tester.element(find.byType(OrderPatientStep));
    expect(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).color,
      Theme.of(context).colorScheme.primary,
    );
  });

  test('visit rows sort by name, accents and case aside', () {
    AppointmentModel visit(String uid, String patientId, String name) =>
        AppointmentModel(
          uid: uid,
          status: 'Accepted',
          patientId: patientId,
          patientName: name,
          doctorUid: 'doc-1',
          scheduledStart: '2026-11-1${uid.length}T09:00:00.000Z',
          scheduledEnd: '2026-11-1${uid.length}T09:30:00.000Z',
        );
    final rows = patientsForOrdering(
      appointments: [
        visit('a', 'p1', 'Wanjiru Kamau'),
        visit('bb', 'p2', 'amina Otieno'),
        visit('ccc', 'p3', 'Émile Odhiambo'),
      ],
      doctorUid: 'doc-1',
      now: DateTime.utc(2026, 11, 19),
    );
    expect(rows.map((r) => r.patientName), [
      'amina Otieno',
      'Émile Odhiambo',
      'Wanjiru Kamau',
    ]);
  });

  testWidgets('care rows sort by name', (tester) async {
    final bloc = _MockPatientsBloc();
    PatientModel care(String id, String first, String last) =>
        PatientModel.empty().copyWith(
          patientId: id,
          firstName: first,
          lastName: last,
          doctorUids: const ['doc-1'],
        );
    when(() => bloc.state).thenReturn(
      PatientsLoadSuccess(
        patients: [
          care('p1', 'Zawadi', 'Njeri'),
          care('p2', 'Brian', 'Kiprop'),
          care('p3', 'Amina', 'Otieno'),
        ],
        doctorUid: 'doc-1',
      ),
    );
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpApp(
      BlocProvider<PatientsBloc>.value(
        value: bloc,
        child: SizedBox(
          height: 800,
          child: OrderPatientStep(
            appointments: const [],
            doctorUid: 'doc-1',
            now: DateTime.utc(2026, 11, 19),
            selectedAppointmentUid: '',
            onPick: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final names = tester
        .widgetList<Avatar>(find.byType(Avatar))
        .map((avatar) => avatar.name)
        .toList();
    expect(names, ['Amina Otieno', 'Brian Kiprop', 'Zawadi Njeri']);
  });
}

class _MockPatientsBloc extends Mock implements PatientsBloc {}

class _NoImage extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw StateError('no image');
}
