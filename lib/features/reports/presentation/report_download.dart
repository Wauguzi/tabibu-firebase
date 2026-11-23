import 'dart:io';

// Transitive only; no new dependency. Resolved by pubspec.lock.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/get_it_helper.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';
import 'package:tabibu/features/reports/data/cache/report_cache_helper.dart';
import 'package:tabibu/features/reports/data/datasources/report_signature_storage.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/data/models/report_pdf_input.dart';
import 'package:tabibu/features/reports/data/models/report_text_approved_model.dart';
import 'package:tabibu/features/reports/data/report_text_id.dart';
import 'package:tabibu/features/reports/data/services/report_pdf_builder.dart';
import 'package:tabibu/l10n/l10n.dart';

/// Builds a signed-report PDF for the patient and hands it to the platform
/// share sheet. Uses a temp file deleted after the sheet closes (S-3). Never
/// logs a name, diagnosis or result.
class ReportDownload {
  ReportDownload({
    ReportPdfBuilder? pdfBuilder,
    ReportCacheHelper? reports,
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams params)? share,
    Future<List<PatientModel>> Function(String doctorUid)? carePatients,
    Future<List<int>> Function(String path)? readSignature,
    Logger? logger,
    AnalyticsService? analytics,
  }) : _pdf = pdfBuilder ?? getIt<ReportPdfBuilder>(),
       _reports = reports ?? getIt<ReportCacheHelper>(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share,
       // Named for the caller; the field stays private.
       // ignore: prefer_initializing_formals
       _carePatients = carePatients,
       // Named for the caller; the field stays private.
       // ignore: prefer_initializing_formals
       _readSignature = readSignature,
       _logger = logger ?? Logger(),
       // Named for the caller; the field stays private.
       // ignore: prefer_initializing_formals
       _analytics = analytics;

  final ReportPdfBuilder _pdf;
  final ReportCacheHelper _reports;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams params) _share;
  final Future<List<PatientModel>> Function(String doctorUid)? _carePatients;
  final Future<List<int>> Function(String path)? _readSignature;
  final Logger _logger;
  final AnalyticsService? _analytics;

  /// Builds and shares the PDF, or throws [AppError] when the release gate
  /// refuses (`permissionDenied` / `dataNotFound`). Callers show a generic
  /// failure; this method never logs personal content.
  Future<void> sharePatientReport({
    required PathologyReportModel report,
    required CaseModel caseModel,
    required PatientModel patient,
    required String language,
    required AppLocalizations l10n,
    required DateTime now,
    ActorRole viewerRole = .patient,
    String? viewerUid,
  }) async {
    final translation = await _approvedTranslation(
      caseUid: caseModel.uid,
      report: report,
      language: language,
    );
    final dateOfBirth = await _dateOfBirth(patient, caseModel);
    final signature = await _signature(report);
    final input = ReportPdfInput.fromSignedReport(
      report: report,
      viewerRole: viewerRole.value,
      viewerUid: viewerUid ?? patient.uid,
      patientUid: patient.uid,
      patientDisplayName: patient.fullName,
      dateOfBirth: dateOfBirth,
      sex: patient.sex,
      county: patient.county,
      subCounty: patient.subCounty,
      doctorName: caseModel.doctorName,
      doctorFacilityName: caseModel.doctorFacilityName,
      clinicalNotes: caseModel.clinicalNotes,
      now: now,
      translation: translation,
      signaturePng: signature.png,
      signatureUnavailable: signature.unavailable,
      recordedAgeYears: caseModel.patientAgeYears,
    );

    File? file;
    try {
      final bytes = await _pdf.build(input, l10n);
      final dir = await _temporaryDirectory();
      final safeName = _fileName(report, caseModel);
      file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      await _share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
      );
      // Role only: the event must not carry a name, a case or a report.
      await _logDownloaded(viewerRole);
    } on AppError {
      // Refusal: nothing personal reaches the log.
      rethrow;
    } on Object {
      if (kDebugMode) _logger.w('Report download failed');
      throw AppError.unknown;
    } finally {
      final written = file;
      if (written != null) {
        try {
          if (written.existsSync()) written.deleteSync();
        } on Object {
          if (kDebugMode) _logger.w('Temp report file not removed');
        }
      }
    }
  }

  Future<void> _logDownloaded(ActorRole viewerRole) async {
    final analytics =
        _analytics ??
        (getIt.isRegistered<AnalyticsService>()
            ? getIt<AnalyticsService>()
            : null);
    if (analytics == null) return;
    await analytics.logReportDownloaded(role: viewerRole.name);
  }

  Future<ReportTextApprovedModel?> _approvedTranslation({
    required String caseUid,
    required PathologyReportModel report,
    required String language,
  }) async {
    final id = reportTextId(report.uid, .translation, language);
    ReportTextApprovedModel? text;
    try {
      text = await _reports.syncApprovedText(caseUid: caseUid, textUid: id);
    } on AppError {
      try {
        text = await _reports.getApprovedText(caseUid, id);
      } on Object {
        return null;
      }
    } on Object {
      return null;
    }
    if (text == null) return null;
    // A mismatched or empty hash is an unapproved / stale draft — omit it.
    if (text.sourceSha256.isEmpty ||
        text.sourceSha256 != report.contentSha256) {
      return null;
    }
    return text;
  }

  String _fileName(PathologyReportModel report, CaseModel caseModel) {
    final order = report.orderNumber.trim().isNotEmpty
        ? report.orderNumber
        : caseModel.orderNumber;
    final test = report.testName.trim().isNotEmpty
        ? report.testName
        : (caseModel.tests.isNotEmpty ? caseModel.tests.first.name : '');
    final raw = order.trim().isNotEmpty
        ? order
        : (test.trim().isNotEmpty ? test : 'report');
    final safe = raw.replaceAll(RegExp(r'[^\w.\- ]+'), '_').trim();
    return '${safe.isEmpty ? 'report' : safe}.pdf';
  }

  /// The doctor's download is handed a patient built from the case, which has
  /// no date of birth. The care row has it, for a walk-in and for a booking.
  Future<String> _dateOfBirth(PatientModel patient, CaseModel caseModel) async {
    if (patient.dateOfBirth.isNotEmpty) return patient.dateOfBirth;
    final lookup = _carePatients ?? _installedCarePatients;
    try {
      final rows = await lookup(caseModel.doctorUid);
      return _careMatch(rows, patient)?.dateOfBirth ?? '';
    } on Object {
      return '';
    }
  }

  Future<List<PatientModel>> _installedCarePatients(String doctorUid) =>
      getIt<PatientSync>().load(doctorUid);

  PatientModel? _careMatch(List<PatientModel> rows, PatientModel patient) {
    for (final row in rows) {
      if (patient.patientId.isNotEmpty && row.patientId == patient.patientId) {
        return row;
      }
      if (patient.uid.isNotEmpty && row.uid == patient.uid) return row;
    }
    return null;
  }

  /// Bytes whose SHA-256 matches the report, or the unavailable line.
  /// A path that is not the stored signature is never fetched.
  Future<({List<int> png, String unavailable})> _signature(
    PathologyReportModel report,
  ) async {
    const none = (png: <int>[], unavailable: '');
    final hash = report.signatureSha256.toLowerCase();
    final path = report.signaturePath;
    if (hash.isEmpty && path.isEmpty) return none;
    final expected =
        'reports/${report.caseUid}/${report.uid}/signature-$hash.png';
    final hashOk = RegExp(r'^[0-9a-f]{64}$').hasMatch(hash);
    if (!hashOk || path != expected) {
      return (png: const <int>[], unavailable: reportPdfSignatureUnavailable);
    }
    try {
      final bytes = await _read(path);
      if (sha256.convert(bytes).toString() == hash) {
        return (png: bytes, unavailable: '');
      }
    } on Object {
      // Fetch or hash failure: the block says so, and the PDF still builds.
    }
    return (png: const <int>[], unavailable: reportPdfSignatureUnavailable);
  }

  Future<List<int>> _read(String path) {
    final read = _readSignature;
    if (read != null) return read(path);
    return ReportSignatureStorage(getIt<FirebaseStorage>()).read(path);
  }
}
