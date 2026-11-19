import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/utils/nairobi_time.dart';
import 'package:tabibu/core/utils/settle_refresh.dart';
import 'package:tabibu/core/utils/text_fold.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/appointments/data/models/appointment_model.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_bloc.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/presentation/add_patient_sheet.dart';
import 'package:tabibu/features/patients/presentation/care_patient_list.dart';
import 'package:tabibu/gen/assets.gen.dart';
import 'package:tabibu/l10n/l10n.dart';

/// One patient the doctor may order for, on the visit the order hangs off.
typedef OrderablePatient = ({
  String patientId,
  String patientName,
  AppointmentModel appointment,
});

/// The doctor's orderable patients from visits already on the device: one
/// row per `patientId` with an Accepted or Completed visit of this doctor's.
/// Each row hangs off the visit under way where there is one, else the
/// latest; rows sort by name, accents and case aside, the latest visit first
/// between two of one name. Pure, so the screen owns no query.
List<OrderablePatient> patientsForOrdering({
  required List<AppointmentModel> appointments,
  required String doctorUid,
  required DateTime now,
}) {
  final byPatient = <String, List<AppointmentModel>>{};
  for (final appointment in appointments) {
    if (appointment.uid.isEmpty ||
        appointment.patientId.isEmpty ||
        appointment.doctorUid != doctorUid) {
      continue;
    }
    if (appointment.statusValue != .accepted &&
        appointment.statusValue != .completed) {
      continue;
    }
    (byPatient[appointment.patientId] ??= []).add(appointment);
  }
  DateTime? startOf(AppointmentModel a) => DateTime.tryParse(a.scheduledStart);
  bool underWay(AppointmentModel a) {
    final start = startOf(a);
    final end = DateTime.tryParse(a.scheduledEnd);
    if (start == null || end == null || start.isAfter(now)) return false;
    return !end.isBefore(now);
  }

  int byStartDesc(AppointmentModel a, AppointmentModel b) {
    final sa = startOf(a);
    final sb = startOf(b);
    if (sa == null) return sb == null ? 0 : 1;
    if (sb == null) return -1;
    return sb.compareTo(sa);
  }

  final rows = <OrderablePatient>[];
  for (final entry in byPatient.entries) {
    final visits = entry.value..sort(byStartDesc);
    final current = visits.where(underWay).toList()
      ..sort((a, b) => startOf(a)!.compareTo(startOf(b)!));
    final chosen = current.isNotEmpty ? current.first : visits.first;
    rows.add((
      patientId: entry.key,
      patientName: chosen.patientName,
      appointment: chosen,
    ));
  }
  rows.sort((a, b) {
    final byName = foldForSearch(
      a.patientName,
    ).compareTo(foldForSearch(b.patientName));
    return byName != 0 ? byName : byStartDesc(a.appointment, b.appointment);
  });
  return rows;
}

/// The wizard's first step on the home "+" path: pick which patient the
/// order is for. The visits come from the screen. Added patients come from
/// [PatientsBloc]; this step only reads that list and asks it to sync.
class OrderPatientStep extends StatefulWidget {
  const OrderPatientStep({
    required this.appointments,
    required this.doctorUid,
    required this.now,
    required this.selectedAppointmentUid,
    required this.onPick,
    this.canAdd = false,
    this.county = '',
    this.subCounty = '',
    this.language = '',
    this.selectedPatientId = '',
    this.onPickAdded,
    super.key,
  });

  final List<AppointmentModel> appointments;
  final String doctorUid;
  final DateTime now;
  final String selectedAppointmentUid;
  final ValueChanged<AppointmentModel> onPick;
  final bool canAdd;
  final String county;
  final String subCounty;

  /// The doctor's profile language, stored on the patient.
  final String language;
  final String selectedPatientId;
  final ValueChanged<PatientModel>? onPickAdded;

  @override
  State<OrderPatientStep> createState() => _OrderPatientStepState();
}

class _OrderPatientStepState extends State<OrderPatientStep> {
  String _query = '';

  /// The patient the sheet just saved, matched again after an id swap.
  String? _watchPhone;
  String? _watchDob;
  PatientModel? _lastPicked;

  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(
      PatientsSyncRequested(doctorUid: widget.doctorUid),
    );
  }

  void _onPatients(PatientsState state) {
    final phone = _watchPhone;
    if (phone == null) return;
    final after = state.patients.firstWhereOrNull(
      (row) =>
          row.phoneNumber == phone &&
          row.dateOfBirth == _watchDob &&
          row.doctorUids.contains(widget.doctorUid),
    );
    if (after == null) return;
    final last = _lastPicked;
    if (last != null &&
        last.patientId == after.patientId &&
        last.synced == after.synced &&
        last.held == after.held) {
      return;
    }
    _lastPicked = after;
    widget.onPickAdded?.call(after);
  }

  Future<void> _refresh() async {
    final bloc = context.read<PatientsBloc>()
      ..add(PatientsSyncRequested(doctorUid: widget.doctorUid));
    await settleRefresh<PatientsState>(
      bloc.stream,
      (state) => state is PatientsLoadInProgress,
    );
  }

  Future<void> _add() async {
    final saved = await AddPatientSheet.show(
      context,
      doctorUid: widget.doctorUid,
      county: widget.county,
      subCounty: widget.subCounty,
      language: widget.language,
    );
    if (saved == null || !mounted) return;
    _watchPhone = saved.phoneNumber;
    _watchDob = saved.dateOfBirth;
    _lastPicked = null;
    context.read<PatientsBloc>().add(
      PatientsAdded(doctorUid: widget.doctorUid, patient: saved),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final all = patientsForOrdering(
      appointments: widget.appointments,
      doctorUid: widget.doctorUid,
      now: widget.now,
    );
    final addedPatients = context.watch<PatientsBloc>().state.patients;
    // A visit does not carry a photo. The care row does, and an empty url
    // is no photo: initials, as on the home header.
    final photoOf = {
      for (final patient in addedPatients)
        patient.patientId: patient.profilePictureUrl,
    };
    // The number tells two patients of one name apart.
    final phoneOf = {
      for (final patient in addedPatients)
        if (patient.phoneNumber.isNotEmpty)
          patient.patientId: patient.phoneNumber,
    };
    final visitIds = {for (final row in all) row.patientId};
    final added = addedPatients.where(
      (row) => !visitIds.contains(row.patientId),
    );
    final needle = foldForSearch(_query.trim());
    final rows = needle.isEmpty
        ? all
        : all
              .where((row) => foldForSearch(row.patientName).contains(needle))
              .toList();
    final addedRows = needle.isEmpty
        ? added.toList()
        : added
              .where((row) => foldForSearch(row.fullName).contains(needle))
              .toList();
    return BlocListener<PatientsBloc, PatientsState>(
      listener: (_, state) => _onPatients(state),
      child: Stack(
        children: [
          // The dashboard's indicator: native on iOS, in the primary colour.
          RefreshIndicator.adaptive(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenMargin,
                AppSpacing.screenMargin,
                AppSpacing.screenMargin,
                96,
              ),
              keyboardDismissBehavior: .onDrag,
              children: [
                SectionHeader(title: l10n.orderPatientTitle),
                const SizedBox(height: AppSpacing.xs),
                SearchField(
                  hint: l10n.orderPatientSearchHint,
                  clearLabel: MaterialLocalizations.of(
                    context,
                  ).deleteButtonTooltip,
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (all.isEmpty && addedRows.isEmpty)
                  EmptyState(
                    title: l10n.orderPatientEmptyTitle,
                    body: l10n.orderPatientEmptyBody,
                  )
                else
                  for (final row in rows) ...[
                    OptionCard(
                      key: ValueKey(row.patientId),
                      title: row.patientName,
                      supporting:
                          phoneOf[row.patientId] ??
                          _visitDate(row.appointment, language),
                      leading: Avatar(
                        name: row.patientName,
                        radius: 22,
                        image: _patientPhoto(photoOf[row.patientId] ?? ''),
                      ),
                      selected:
                          widget.selectedAppointmentUid == row.appointment.uid,
                      onTap: () => widget.onPick(row.appointment),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                CarePatientList(
                  doctorUid: widget.doctorUid,
                  patients: addedRows,
                  selectedPatientId: widget.selectedPatientId,
                  onPick: (patient) => widget.onPickAdded?.call(patient),
                ),
              ],
            ),
          ),
          if (widget.canAdd)
            Positioned(
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Fab(
                key: const Key('add-patient'),
                icon: Assets.icons.addIcon,
                semanticLabel: l10n.addPatientTitle,
                onTap: () => unawaited(_add()),
              ),
            ),
        ],
      ),
    );
  }

  String? _visitDate(AppointmentModel appointment, String language) {
    final at = nairobiTimeOf(appointment.scheduledStart);
    if (at == null) return null;
    return DateFormat('EEE d MMM', language).format(at);
  }
}

/// An empty url is no photo, so the avatar keeps its initials.
ImageProvider<Object>? _patientPhoto(String url) =>
    url.isEmpty ? null : NetworkImage(url);
