import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/cases/data/models/case_model.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/reports/data/models/pathology_report_model.dart';
import 'package:tabibu/features/reports/presentation/report_download.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The patient's download, offered to the doctor who can open the report.
class DoctorReportDownloadButton extends StatefulWidget {
  const DoctorReportDownloadButton({
    required this.report,
    required this.caseModel,
    required this.patient,
    required this.viewerUid,
    this.download,
    super.key,
  });

  final Future<PathologyReportModel?> Function() report;
  final CaseModel caseModel;
  final PatientModel patient;
  final String viewerUid;
  final ReportDownload? download;

  @override
  State<DoctorReportDownloadButton> createState() =>
      _DoctorReportDownloadButtonState();
}

class _DoctorReportDownloadButtonState
    extends State<DoctorReportDownloadButton> {
  bool _downloading = false;
  bool _failed = false;
  ReportDownload? _download;

  ReportDownload get _reportDownload =>
      _download ??= widget.download ?? ReportDownload();

  Future<void> _onDownload() async {
    if (_downloading) return;
    final l10n = context.l10n;
    if (kIsWeb) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      final report = await widget.report();
      if (report == null) throw AppError.dataNotFound;
      await _reportDownload.sharePatientReport(
        report: report,
        caseModel: widget.caseModel,
        patient: widget.patient,
        language: widget.patient.language.isEmpty
            ? 'en'
            : widget.patient.language,
        l10n: l10n,
        now: DateTime.now().toUtc(),
        viewerRole: .doctor,
        viewerUid: widget.viewerUid,
      );
      if (!mounted) return;
      setState(() => _downloading = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TabibuButton.secondary(
          label: _downloading
              ? l10n.resultsLoadingLabel
              : l10n.doctorReportDownload,
          isLoading: _downloading,
          onTap: _downloading ? null : _onDownload,
        ),
        if (_failed) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.errorUnknown,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }
}

/// A patient row the PDF can name, from the case when the record is not cached.
PatientModel patientForDoctorReport(CaseModel caseModel) =>
    PatientModel.empty().copyWith(
      patientId: caseModel.patientId,
      uid: caseModel.patientUid,
      firstName: caseModel.patientName,
      sex: caseModel.patientSex,
      synced: true,
    );
