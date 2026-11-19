import 'dart:io';
import 'dart:typed_data';

// Transitive only; no new dependency. Resolved by pubspec.lock.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/reports/data/cache/report_cache_helper.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_pdf_input.dart';
import 'package:tabibu/features/reports/data/models/report_text_approved_model.dart';
import 'package:tabibu/features/reports/data/services/report_pdf_builder.dart';
import 'package:tabibu/features/reports/presentation/report_download.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../data/models/pathology_report_model_test.dart' show reportJson;

class _MockPdf extends Mock implements ReportPdfBuilder {}

class _MockReports extends Mock implements ReportCacheHelper {}

class _MemoryLog extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 3, 12);
  final l10n = lookupAppLocalizations(const Locale('en'));
  final patient = PatientModel.empty().copyWith(
    uid: 'patient-1',
    firstName: 'Amina',
    lastName: 'Wanjiku',
    dateOfBirth: '1990-01-15T00:00:00.000Z',
    sex: 'Female',
    county: 'Nairobi',
    subCounty: 'Kibra',
  );
  const caseModel = CaseModel(
    uid: 'case-1',
    doctorName: 'Dr Doc',
    doctorFacilityName: 'Clinic One',
    clinicalNotes: 'Notes',
  );

  late _MockPdf pdf;
  late _MockReports reports;
  late _MemoryLog logOutput;
  late Directory tempDir;
  late List<ShareParams> shared;
  late ReportDownload download;
  late Future<List<int>> Function(String path)? readSignature;
  late Future<List<PatientModel>> Function(String doctorUid)? carePatients;

  PathologyReportModel signed({bool released = true}) =>
      PathologyReportModel.fromJson(reportJson()).copyWith(
        releasedToPatient: released,
        releasedAt: released ? '2026-11-01T12:00:00.000Z' : '',
      );

  setUpAll(() {
    registerFallbackValue(const ReportPdfInput());
    registerFallbackValue(l10n);
  });

  setUp(() async {
    pdf = _MockPdf();
    reports = _MockReports();
    logOutput = _MemoryLog();
    tempDir = await Directory.systemTemp.createTemp('report_download_');
    shared = <ShareParams>[];
    readSignature = null;
    carePatients = null;
    when(
      () => pdf.build(any(), any()),
    ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(
      () => reports.syncApprovedText(
        caseUid: any(named: 'caseUid'),
        textUid: any(named: 'textUid'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => reports.getApprovedText(any(), any()),
    ).thenAnswer((_) async => null);
    download = ReportDownload(
      pdfBuilder: pdf,
      reports: reports,
      temporaryDirectory: () async => tempDir,
      share: (params) async {
        shared.add(params);
        return const ShareResult('', ShareResultStatus.success);
      },
      carePatients: (doctorUid) {
        final lookup = carePatients;
        if (lookup == null) return Future.value(const <PatientModel>[]);
        return lookup(doctorUid);
      },
      readSignature: (path) {
        final read = readSignature;
        if (read == null) throw StateError('signature read was not stubbed');
        return read(path);
      },
      logger: Logger(
        level: Level.warning,
        output: logOutput,
        printer: SimplePrinter(colors: false),
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ReportDownload', () {
    test('refuses an unreleased report and never shares', () async {
      await expectLater(
        () => download.sharePatientReport(
          report: signed(released: false),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        ),
        throwsA(AppError.permissionDenied),
      );
      expect(shared, isEmpty);
      verifyNever(() => pdf.build(any(), any()));
    });

    test('refuses a draft (non-signed) report and never shares', () async {
      await expectLater(
        () => download.sharePatientReport(
          report: signed().copyWith(status: 'Draft'),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        ),
        throwsA(AppError.dataNotFound),
      );
      expect(shared, isEmpty);
      verifyNever(() => pdf.build(any(), any()));
    });

    test('omits a translation whose source hash does not match', () async {
      when(
        () => reports.syncApprovedText(
          caseUid: any(named: 'caseUid'),
          textUid: any(named: 'textUid'),
        ),
      ).thenAnswer(
        (_) async => const ReportTextApprovedModel(
          sourceSha256: 'stale-hash',
          approvedText: {'diagnosis': 'Should not appear'},
          language: 'en',
        ),
      );

      await download.sharePatientReport(
        report: signed(),
        caseModel: caseModel,
        patient: patient,
        language: 'en',
        l10n: l10n,
        now: now,
      );

      final input =
          verify(() => pdf.build(captureAny(), any())).captured.single
              as ReportPdfInput;
      expect(input.translation, isEmpty);
      expect(shared, hasLength(1));
    });

    test('shares a released report and deletes the temp file', () async {
      await download.sharePatientReport(
        report: signed(),
        caseModel: caseModel,
        patient: patient,
        language: 'en',
        l10n: l10n,
        now: now,
      );

      expect(shared, hasLength(1));
      expect(shared.single.files, isNotNull);
      expect(shared.single.files, isNotEmpty);
      final path = shared.single.files!.single.path;
      expect(File(path).existsSync(), isFalse);
      expect(tempDir.listSync(), isEmpty);
    });

    test(
      'refusal and failure log lines never carry a name or result',
      () async {
        final name = patient.fullName;
        const diagnosis = 'Benign';
        const comments = 'Clear margins.';

        await expectLater(
          () => download.sharePatientReport(
            report: signed(released: false),
            caseModel: caseModel,
            patient: patient,
            language: 'en',
            l10n: l10n,
            now: now,
          ),
          throwsA(AppError.permissionDenied),
        );

        when(() => pdf.build(any(), any())).thenThrow(Exception('disk'));
        await expectLater(
          () => download.sharePatientReport(
            report: signed(),
            caseModel: caseModel,
            patient: patient,
            language: 'en',
            l10n: l10n,
            now: now,
          ),
          throwsA(AppError.unknown),
        );

        final joined = logOutput.lines.join('\n');
        expect(joined.contains(name), isFalse);
        expect(joined.contains(diagnosis), isFalse);
        expect(joined.contains(comments), isFalse);
        expect(joined.contains('Amina'), isFalse);
        expect(joined.contains('Wanjiku'), isFalse);
      },
    );

    String sharedName() => shared.single.files!.single.path.split('/').last;

    ReportPdfInput builtInput() =>
        verify(() => pdf.build(captureAny(), any())).captured.single
            as ReportPdfInput;

    test('names the file from the order number', () async {
      await download.sharePatientReport(
        report: signed(),
        caseModel: caseModel,
        patient: patient,
        language: 'en',
        l10n: l10n,
        now: now,
      );
      expect(sharedName(), 'ODR-1.pdf');
    });

    test(
      'an empty order number falls back to the test name, then report',
      () async {
        await download.sharePatientReport(
          report: signed().copyWith(
            orderNumber: '',
            testName: 'Histopathology',
          ),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        );
        expect(sharedName(), 'Histopathology.pdf');

        shared.clear();
        clearInteractions(pdf);
        await download.sharePatientReport(
          report: signed().copyWith(orderNumber: '', testName: ''),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        );
        expect(sharedName(), 'report.pdf');
      },
    );

    test('a walk-in and a booked patient both carry their age', () async {
      PatientModel row({
        required String patientId,
        required String uid,
        required String dateOfBirth,
      }) => PatientModel.empty().copyWith(
        patientId: patientId,
        uid: uid,
        firstName: 'Amina',
        dateOfBirth: dateOfBirth,
      );

      Future<void> share({
        required String appointmentUid,
        required PatientModel stored,
      }) {
        carePatients = (_) async => [stored];
        final shell = PatientModel.empty().copyWith(
          patientId: stored.patientId,
          uid: stored.uid,
          firstName: 'Amina',
        );
        return download.sharePatientReport(
          report: signed(),
          caseModel: CaseModel(
            uid: 'case-1',
            doctorUid: 'doc-1',
            patientId: stored.patientId,
            patientUid: stored.uid,
            appointmentUid: appointmentUid,
            patientAgeYears: 1,
          ),
          patient: shell,
          language: 'en',
          l10n: l10n,
          now: now,
          viewerRole: .doctor,
          viewerUid: 'doc-1',
        );
      }

      await share(
        appointmentUid: '',
        stored: row(
          patientId: 'walk-1',
          uid: 'uid-walk',
          dateOfBirth: '1990-01-15T00:00:00.000Z',
        ),
      );
      final walkIn = builtInput().subject;
      expect(walkIn.ageYears, 36);
      expect(walkIn.ageMonths, 9);

      clearInteractions(pdf);
      await share(
        appointmentUid: 'appt-1',
        stored: row(
          patientId: 'book-1',
          uid: 'uid-book',
          dateOfBirth: '2000-06-01T00:00:00.000Z',
        ),
      );
      final booked = builtInput().subject;
      expect(booked.ageYears, 26);
      expect(booked.ageMonths, 5);
    });

    test(
      'the case age is used when the care row has no date of birth',
      () async {
        carePatients = (_) async => const <PatientModel>[];
        await download.sharePatientReport(
          report: signed(),
          caseModel: const CaseModel(
            uid: 'case-1',
            doctorUid: 'doc-1',
            patientAgeYears: 46,
          ),
          patient: PatientModel.empty().copyWith(patientId: 'missing'),
          language: 'en',
          l10n: l10n,
          now: now,
          viewerRole: .doctor,
          viewerUid: 'doc-1',
        );
        final subject = builtInput().subject;
        expect(subject.ageYears, 46);
        expect(subject.ageMonths, 0);
      },
    );

    test('a stored signature whose hash matches is drawn', () async {
      final png = <int>[137, 80, 78, 71, 1, 2, 3];
      final hash = sha256.convert(png).toString();
      readSignature = (_) async => png;
      await download.sharePatientReport(
        report: signed().copyWith(
          signatureSha256: hash,
          signaturePath: 'reports/case-1/report-1/signature-$hash.png',
        ),
        caseModel: caseModel,
        patient: patient,
        language: 'en',
        l10n: l10n,
        now: now,
      );
      final signature = builtInput().signature;
      expect(signature.png, png);
      expect(signature.unavailable, isEmpty);
    });

    test(
      'a mismatched or failed signature says it could not be shown',
      () async {
        final png = <int>[137, 80, 78, 71, 9, 9, 9];
        final hash = sha256.convert(png).toString();
        final path = 'reports/case-1/report-1/signature-$hash.png';
        readSignature = (_) async => <int>[1, 2, 3, 4];
        await download.sharePatientReport(
          report: signed().copyWith(signatureSha256: hash, signaturePath: path),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        );
        var signature = builtInput().signature;
        expect(signature.png, isEmpty);
        expect(signature.unavailable, reportPdfSignatureUnavailable);

        clearInteractions(pdf);
        readSignature = (_) => Future<List<int>>.error(Exception('denied'));
        await download.sharePatientReport(
          report: signed().copyWith(signatureSha256: hash, signaturePath: path),
          caseModel: caseModel,
          patient: patient,
          language: 'en',
          l10n: l10n,
          now: now,
        );
        signature = builtInput().signature;
        expect(signature.png, isEmpty);
        expect(signature.unavailable, reportPdfSignatureUnavailable);
      },
    );
  });
}
