import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/constants/app_spacing.dart';
import 'package:tabibu/core/utils/text_fold.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_bloc.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/l10n/l10n.dart';

/// The doctor's patients in care, by name, each read by phone number.
class CarePatientList extends StatefulWidget {
  const CarePatientList({
    required this.doctorUid,
    required this.patients,
    required this.selectedPatientId,
    required this.onPick,
    super.key,
  });

  final String doctorUid;
  final List<PatientModel> patients;
  final String selectedPatientId;
  final ValueChanged<PatientModel> onPick;

  @override
  State<CarePatientList> createState() => _CarePatientListState();
}

class _CarePatientListState extends State<CarePatientList> {
  @override
  void initState() {
    super.initState();
    context.read<PatientsBloc>().add(
      PatientsLoadRequested(doctorUid: widget.doctorUid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        for (final patient in _byName(widget.patients)) ...[
          OptionCard(
            key: ValueKey('care-${patient.patientId}'),
            title: patient.fullName,
            supporting: _caption(l10n, patient),
            leading: Avatar(
              name: patient.fullName,
              radius: 22,
              image: patient.profilePictureUrl.isEmpty
                  ? null
                  : NetworkImage(patient.profilePictureUrl),
            ),
            selected: widget.selectedPatientId == patient.patientId,
            onTap: () => widget.onPick(patient),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  /// By name, accents and case aside; the phone keeps two of one name in a
  /// fixed order.
  List<PatientModel> _byName(List<PatientModel> patients) =>
      [...patients]..sort((a, b) {
        final byName = foldForSearch(
          a.fullName,
        ).compareTo(foldForSearch(b.fullName));
        return byName != 0 ? byName : a.phoneNumber.compareTo(b.phoneNumber);
      });

  /// The phone number tells two patients of one name apart; a sync warning
  /// follows it, so it is never lost.
  String? _caption(AppLocalizations l10n, PatientModel patient) {
    final status = patient.held
        ? l10n.errorPatientExists
        : !patient.synced
        ? l10n.addPatientPending
        : '';
    final line = [
      patient.phoneNumber,
      status,
    ].where((part) => part.isNotEmpty).join(' · ');
    return line.isEmpty ? null : line;
  }
}
