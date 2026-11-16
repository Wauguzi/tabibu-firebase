import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/ai_logic_service.dart';
import 'package:tabibu/features/appointments/data/datasources/appointment_firebase.dart';

import '../../../../helpers/helpers.dart';

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

class _Refusal extends FirebaseFunctionsException {
  _Refusal(String reason, String code) : super(message: reason, code: code);
}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockFunctions functions;
  late _MockCallable callable;
  late FakeAiLogicService ai;
  late AppointmentFirebase remote;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    functions = _MockFunctions();
    callable = _MockCallable();
    ai = FakeAiLogicService(
      result: const SymptomTranscript(
        transcript: 'Headache since morning',
        language: 'en',
      ),
    );
    remote = AppointmentFirebase(
      firestore: firestore,
      functions: functions,
      ai: ai,
    );
    when(() => functions.httpsCallable(any())).thenReturn(callable);
  });

  group('deltas', () {
    test('patient delta filters by patientUid and cursor', () async {
      await firestore.collection('appointments').doc('a1').set({
        'patientUid': 'p1',
        'doctorUid': 'd1',
        'lastUpdatedAt': '2026-11-01T10:00:00.000Z',
      });
      await firestore.collection('appointments').doc('a2').set({
        'patientUid': 'p1',
        'doctorUid': 'd1',
        'lastUpdatedAt': '2026-11-01T12:00:00.000Z',
      });
      await firestore.collection('appointments').doc('a3').set({
        'patientUid': 'p2',
        'doctorUid': 'd1',
        'lastUpdatedAt': '2026-11-01T12:00:00.000Z',
      });

      final rows = await remote.fetchPatientDelta(
        patientUid: 'p1',
        cursor: '2026-11-01T11:00:00.000Z',
      );
      expect(rows.map((r) => r.uid), ['a2']);
    });

    test('doctor delta filters by doctorUid', () async {
      await firestore.collection('appointments').doc('a1').set({
        'patientUid': 'p1',
        'doctorUid': 'd1',
        'lastUpdatedAt': '2026-11-01T12:00:00.000Z',
      });
      await firestore.collection('appointments').doc('a2').set({
        'patientUid': 'p1',
        'doctorUid': 'd2',
        'lastUpdatedAt': '2026-11-01T12:00:00.000Z',
      });

      final rows = await remote.fetchDoctorDelta(doctorUid: 'd1');
      expect(rows.map((r) => r.uid), ['a1']);
    });
  });

  group('callables', () {
    test('requestAppointment sends the documented map', () async {
      final result = _MockCallableResult();
      when(() => result.data).thenReturn({'status': 'ok'});
      when(
        () => callable.call<dynamic>(any<dynamic>()),
      ).thenAnswer((_) async => result);

      await remote.requestAppointment(
        appointmentUid: 'a1',
        type: 'Consultation',
        doctorUid: 'd1',
        scheduledStart: '2026-11-02T08:00:00.000Z',
        symptomText: 'Headache',
      );

      verify(() => functions.httpsCallable('requestAppointment')).called(1);
      final sent =
          verify(
                () => callable.call<dynamic>(captureAny<dynamic>()),
              ).captured.single
              as Map<String, dynamic>;
      expect(sent['appointmentUid'], 'a1');
      expect(sent['type'], 'Consultation');
      expect(sent['doctorUid'], 'd1');
      expect(sent['scheduledStart'], '2026-11-02T08:00:00.000Z');
    });

    test('a FirebaseFunctionsException maps to AppError', () async {
      when(
        () => callable.call<dynamic>(any<dynamic>()),
      ).thenThrow(_Refusal('permission-denied', 'permission-denied'));
      await expectLater(
        remote.cancelAppointment(appointmentUid: 'a1'),
        throwsA(AppError.permissionDenied),
      );
    });

    test('transcribeSymptoms records the text and does not upload', () async {
      final result = _MockCallableResult();
      when(() => result.data).thenReturn({'transcriptionUid': 'tr-1'});
      when(
        () => callable.call<dynamic>(any<dynamic>()),
      ).thenAnswer((_) async => result);

      final bytes = Uint8List.fromList([1, 2, 3]);
      final out = await remote.transcribeSymptoms(
        bytes: bytes,
        durationMs: 2500,
      );
      expect(out.transcriptionUid, 'tr-1');
      expect(out.transcript, 'Headache since morning');
      expect(out.detectedLanguage, 'en');
      expect(out.models['transcribe'], AiLogicService.symptomTranscribeModel);
      expect(ai.calls, [(byteLength: 3, mimeType: 'audio/wav')]);
      verify(
        () => functions.httpsCallable('recordSymptomTranscript'),
      ).called(1);
      final sent =
          verify(
                () => callable.call<dynamic>(captureAny<dynamic>()),
              ).captured.single
              as Map<dynamic, dynamic>;
      expect(sent['text'], 'Headache since morning');
      expect(sent['language'], 'en');
      expect(sent['durationBucket'], '0_15');
      expect(sent['model'], AiLogicService.symptomTranscribeModel);
      expect(sent.containsKey('audioUid'), isFalse);
      verifyNever(() => functions.httpsCallable('transcribeSymptoms'));
    });

    test(
      'transcribeSymptoms refuses oversized audio before the model',
      () async {
        await expectLater(
          remote.transcribeSymptoms(
            bytes: Uint8List(AppointmentFirebase.maxSpeechBytes + 1),
            durationMs: 1000,
          ),
          throwsA(AppError.fileTooLarge),
        );
        expect(ai.calls, isEmpty);
        verifyNever(() => functions.httpsCallable(any()));
      },
    );

    test('a switched-off voice record becomes voiceUnavailable', () async {
      when(
        () => callable.call<dynamic>(any<dynamic>()),
      ).thenThrow(_Refusal('voiceDisabled', 'failed-precondition'));
      await expectLater(
        remote.transcribeSymptoms(
          bytes: Uint8List.fromList([1]),
          durationMs: 1000,
        ),
        throwsA(AppError.voiceUnavailable),
      );
    });
  });

  group('server reads', () {
    test('eviction reads reach the server, never the cache', () async {
      final recording = RecordingFirestore();
      final server = AppointmentFirebase(
        firestore: recording,
        functions: functions,
        ai: ai,
      );

      await server.fetchPatientDelta(patientUid: 'p1');
      await server.fetchDoctorDelta(doctorUid: 'd1');

      recording.expectServerReads(2);
    });
  });
}
