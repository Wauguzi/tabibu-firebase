import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/routing/app_routes.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';
import 'package:tabibu/features/cases/blocs/cases_bloc/cases_bloc.dart';
import 'package:tabibu/features/reports/blocs/report_reader_bloc/report_reader_bloc.dart';
import 'package:tabibu/features/reports/presentation/doctor_report_download.dart';
import 'package:tabibu/features/reports/presentation/report_download.dart';
import 'package:tabibu/features/reports/presentation/widgets/explanation_review_section.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_diagnosis_card.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_footer_notices.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_measurements_card.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_reader_scaffold.dart';
import 'package:tabibu/features/reports/presentation/widgets/report_signed_banner.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

enum _ReportOption { openFull, download, startMdt }

/// D-REPORT-SUMMARY. The case's signed report as its doctor reads it: who
/// signed it, the diagnosis and comments, the measurements. The report is
/// signed and human-made; the AI explanations appear only in the review
/// section at the bottom, each in its draft frame until approved.
class DoctorReportScreen extends StatefulWidget {
  const DoctorReportScreen({required this.caseUid, this.download, super.key});

  final String caseUid;
  final ReportDownload? download;

  @override
  State<DoctorReportScreen> createState() => _DoctorReportScreenState();
}

class _DoctorReportScreenState extends State<DoctorReportScreen> {
  bool _downloading = false;
  bool _failed = false;

  Future<void> _download() async {
    final reader = context.read<ReportReaderBloc>().state;
    final report = reader.report;
    final caseModel = context
        .read<CasesBloc>()
        .state
        .cases
        .where((row) => row.uid == widget.caseUid)
        .firstOrNull;
    final session = context.read<AuthBloc>().state.session;
    if (report == null ||
        caseModel == null ||
        session is! PractitionerSession) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      await (widget.download ?? ReportDownload()).sharePatientReport(
        report: report,
        caseModel: caseModel,
        patient: patientForDoctorReport(caseModel),
        language: 'en',
        l10n: context.l10n,
        now: DateTime.now().toUtc(),
        viewerRole: .doctor,
        viewerUid: session.doctor.uid,
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

  Future<void> _openOptions(BuildContext context) async {
    final l10n = context.l10n;
    final choice = await showOptionsSheet<_ReportOption>(
      context,
      title: l10n.reportPdfTitle,
      actions: [
        OptionsAction(
          value: .openFull,
          icon: Assets.icons.documentIcon,
          label: l10n.doctorReportOpenFull,
          supporting: l10n.doctorReportOpenFullSubtitle,
        ),
        OptionsAction(
          value: .download,
          icon: Assets.icons.documentIcon,
          label: l10n.doctorReportDownload,
        ),
        // The consult opens on this case; its summary carries only the
        // signed report (S-3).
        OptionsAction(
          value: .startMdt,
          icon: Assets.icons.mdtIcon,
          label: l10n.mdtEntryStart,
          supporting: l10n.mdtEntryStartBody,
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case .openFull:
        await FullReportRoute(caseUid: widget.caseUid).push<void>(context);
      case .download:
        await _download();
      case .startMdt:
        await DoctorMdtNewRoute(caseUid: widget.caseUid).push<void>(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ReportReaderScaffold(
      caseUid: widget.caseUid,
      trailing: MoreButton(
        semanticLabel: l10n.notificationsMoreLabel,
        onTap: () => _openOptions(context),
      ),
      bodyBuilder: (context, report, caseModel) => [
        if (_downloading)
          Semantics(
            label: l10n.resultsLoadingLabel,
            child: const LinearProgressIndicator(),
          ),
        if (_failed)
          Text(
            l10n.errorUnknown,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ReportSignedBanner(report: report),
        ReportDiagnosisCard(report: report),
        if (report.measurements.isNotEmpty)
          ReportMeasurementsCard(report: report),
        ReportFooterNotices(
          report: report,
          patientName: caseModel?.patientName ?? '',
        ),
        ExplanationReviewSection(
          caseUid: widget.caseUid,
          patientName: caseModel?.patientName ?? '',
        ),
      ],
    );
  }
}
