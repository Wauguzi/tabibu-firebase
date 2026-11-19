import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:injectable/injectable.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';

/// The doctor's care-patient cache. It outlives the order screen, so a
/// patient added offline is sent when the doctor's other data syncs.
@injectable
class PatientsBloc extends Bloc<PatientsEvent, PatientsState> {
  PatientsBloc(PatientSync sync)
    : _sync = sync,
      super(const PatientsInitial()) {
    // One at a time below: a load finishing after a sync would put the
    // stale cache back.
    on<PatientsLoadRequested>(_onLoad, transformer: droppable());
    on<PatientsSyncRequested>(_onSync, transformer: droppable());
    on<PatientsAdded>(_onAdded, transformer: sequential());
    on<PatientsReset>((_, emit) => emit(const PatientsInitial()));
  }

  final PatientSync _sync;
  Future<void> _queue = Future<void>.value();

  Future<void> _onLoad(
    PatientsLoadRequested event,
    Emitter<PatientsState> emit,
  ) {
    return _alone(() async {
      await _emitRows(emit, event.doctorUid, () => _sync.load(event.doctorUid));
    });
  }

  Future<void> _onSync(
    PatientsSyncRequested event,
    Emitter<PatientsState> emit,
  ) {
    return _alone(() async {
      emit(
        PatientsLoadInProgress(
          patients: state.patients,
          doctorUid: event.doctorUid,
        ),
      );
      await _emitRows(
        emit,
        event.doctorUid,
        () => _sync.drain(event.doctorUid),
      );
    });
  }

  Future<void> _onAdded(PatientsAdded event, Emitter<PatientsState> emit) {
    return _alone(() async {
      final pending = await _sync.remember(event.patient);
      final shown = _with(state.patients, pending);
      emit(PatientsLoadSuccess(patients: shown, doctorUid: event.doctorUid));
      try {
        final rows = await _sync.drain(event.doctorUid);
        emit(PatientsLoadSuccess(patients: rows, doctorUid: event.doctorUid));
      } on Object catch (error) {
        emit(
          PatientsLoadFailure(
            patients: shown,
            doctorUid: event.doctorUid,
            error: error is AppError ? error : AppError.serviceUnavailable,
          ),
        );
      }
    });
  }

  Future<void> _emitRows(
    Emitter<PatientsState> emit,
    String doctorUid,
    Future<List<PatientModel>> Function() read,
  ) async {
    try {
      emit(PatientsLoadSuccess(patients: await read(), doctorUid: doctorUid));
    } on Object catch (error) {
      emit(
        PatientsLoadFailure(
          patients: state.patients,
          doctorUid: doctorUid,
          error: error is AppError ? error : AppError.serviceUnavailable,
        ),
      );
    }
  }

  /// Handlers of different events run together; this keeps their reads and
  /// writes in the order they started.
  Future<void> _alone(Future<void> Function() body) {
    final run = _queue.then((_) => body());
    _queue = run.then((_) {}, onError: (_, _) {});
    return run;
  }

  List<PatientModel> _with(List<PatientModel> rows, PatientModel pending) => [
    for (final row in rows)
      if (row.patientId != pending.patientId) row,
    pending,
  ];
}
