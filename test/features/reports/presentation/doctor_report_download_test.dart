import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/reports/data/cache/report_cache_helper.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_pdf_input.dart';
import 'package:tabibu/features/reports/data/services/report_pdf_builder.dart';
import 'package:tabibu/features/reports/presentation/doctor_report_download.dart';
import 'package:tabibu/features/reports/presentation/report_download.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../helpers/helpers.dart';
import '../data/models/pathology_report_model_test.dart' show reportJson;

class _MockPdf extends Mock implements ReportPdfBuilder {}

class _MockReports extends Mock implements ReportCacheHelper {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(const Locale('en'));
  const caseModel = CaseModel(
    uid: 'case-1',
    patientName: 'Amina Wanjiku',
    doctorName: 'Dr Doc',
    currentStage: 'ReportSigned',
  );

  late _MockPdf pdf;
  late Directory tempDir;
  late List<String> written;
  late ReportDownload download;

  setUpAll(() {
    registerFallbackValue(const ReportPdfInput());
    registerFallbackValue(l10n);
  });

  setUp(() async {
    pdf = _MockPdf();
    final reports = _MockReports();
    tempDir = await Directory.systemTemp.createTemp('doctor_report_');
    written = [];
    when(() => pdf.build(any(), any())).thenAnswer((invocation) async {
      final input = invocation.positionalArguments.first as ReportPdfInput;
      written.add(input.viewerRole);
      return Uint8List.fromList([1, 2, 3]);
    });
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
        final path = params.files!.single.path;
        expect(File(path).existsSync(), isTrue);
        return const ShareResult('', ShareResultStatus.success);
      },
      logger: Logger(level: Level.off),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('builds the patient PDF for the doctor and deletes the file', () async {
    final patient = patientForDoctorReport(caseModel);
    await download.sharePatientReport(
      report: PathologyReportModel.fromJson(reportJson()),
      caseModel: caseModel,
      patient: patient,
      language: 'en',
      l10n: l10n,
      now: DateTime.utc(2026, 11, 18),
      viewerRole: .doctor,
      viewerUid: 'doc-1',
    );

    expect(written, ['Doctor']);
    expect(tempDir.listSync(), isEmpty);
  });

  testWidgets('a failure shows its line', (tester) async {
    when(() => pdf.build(any(), any())).thenThrow(Exception('disk'));
    await tester.pumpApp(
      DoctorReportDownloadButton(
        download: download,
        caseModel: caseModel,
        patient: patientForDoctorReport(caseModel),
        viewerUid: 'doc-1',
        report: () async => PathologyReportModel.fromJson(reportJson()),
      ),
    );

    await tester.tap(find.text(l10n.doctorReportDownload));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.errorUnknown), findsOneWidget);
  });
}
