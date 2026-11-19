import 'package:equatable/equatable.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';

sealed class PatientsEvent extends Equatable {
  const PatientsEvent();

  @override
  List<Object?> get props => [];
}

/// The doctor's cached patients, with no network send.
final class PatientsLoadRequested extends PatientsEvent {
  const PatientsLoadRequested({required this.doctorUid});

  final String doctorUid;

  @override
  List<Object?> get props => [doctorUid];
}

/// Send every pending patient, then show the cache as it stands.
final class PatientsSyncRequested extends PatientsEvent {
  const PatientsSyncRequested({required this.doctorUid});

  final String doctorUid;

  @override
  List<Object?> get props => [doctorUid];
}

/// Cache a doctor-added patient at once, then try to send them.
final class PatientsAdded extends PatientsEvent {
  const PatientsAdded({required this.doctorUid, required this.patient});

  final String doctorUid;
  final PatientModel patient;

  @override
  List<Object?> get props => [doctorUid, patient];
}

/// Sign-out drops the list so the next account never sees it.
final class PatientsReset extends PatientsEvent {
  const PatientsReset();
}
