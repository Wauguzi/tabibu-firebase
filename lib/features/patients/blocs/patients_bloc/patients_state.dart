import 'package:equatable/equatable.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';

/// The doctor's patients on this phone. Pending and refused rows stay in
/// [patients]; those marks live on the model.
sealed class PatientsState extends Equatable {
  const PatientsState({this.patients = const [], this.doctorUid = ''});

  final List<PatientModel> patients;
  final String doctorUid;

  /// The rows only when they belong to [uid]: a screen never shows another
  /// session's patients.
  List<PatientModel> patientsFor(String uid) =>
      uid.isNotEmpty && uid == doctorUid ? patients : const [];

  @override
  List<Object?> get props => [patients, doctorUid];
}

final class PatientsInitial extends PatientsState {
  const PatientsInitial();
}

final class PatientsLoadInProgress extends PatientsState {
  const PatientsLoadInProgress({super.patients, super.doctorUid});
}

final class PatientsLoadSuccess extends PatientsState {
  const PatientsLoadSuccess({super.patients, super.doctorUid});
}

final class PatientsLoadFailure extends PatientsState {
  const PatientsLoadFailure({
    required this.error,
    super.patients,
    super.doctorUid,
  });

  final AppError error;

  @override
  List<Object?> get props => [patients, doctorUid, error];
}
