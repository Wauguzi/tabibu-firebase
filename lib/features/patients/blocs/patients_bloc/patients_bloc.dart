import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:injectable/injectable.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/services/analytics_service.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_event.dart';
import 'package:tabibu/features/patients/blocs/patients_bloc/patients_state.dart';
import 'package:tabibu/features/patients/data/models/patient_model.dart';
import 'package:tabibu/features/patients/data/patient_sync.dart';

/// The doctor's care-patient cache. It outlives the order screen, so a
/// patient added offline is sent when the doctor's other data syncs.
@injectable
class PatientsBloc extends Bloc<PatientsEvent, PatientsState> {
  PatientsBloc(PatientSync sync, AnalyticsService analytics)
    : _sync = sync,
      _analytics = analytics,
      super(const PatientsInitial()) {
    // In order, never dropped: a new doctor's first sync must not be lost
    // behind the last session's. `_alone` keeps reads and writes in turn.
    on<PatientsLoadRequested>(_onLoad, transformer: sequential());
    on<PatientsSyncRequested>(_onSync, transformer: sequential());
    on<PatientsAdded>(_onAdded, transformer: sequential());
    on<PatientsReset>((_, emit) {
      _session++;
      emit(const PatientsInitial());
    });
  }

  final PatientSync _sync;
  final AnalyticsService _analytics;
  Future<void> _queue = Future<void>.value();

  /// Bumped on sign-out. Work started in an earlier session neither emits
  /// nor writes the cache.
  int _session = 0;

  bool _live(int session) => session == _session;

  void _emit(Emitter<PatientsState> emit, int session, PatientsState next) {
    if (_live(session) && !emit.isDone) emit(next);
  }

  /// This doctor's rows only, whatever the cache held.
  List<PatientModel> _mine(List<PatientModel> rows, String doctorUid) => [
    for (final row in rows)
      if (row.doctorUids.contains(doctorUid)) row,
  ];

  Future<void> _onLoad(
    PatientsLoadRequested event,
    Emitter<PatientsState> emit,
  ) {
    final session = _session;
    return _alone(() async {
      if (!_live(session)) return;
      await _emitRows(
        emit,
        session,
        event.doctorUid,
        () => _sync.load(event.doctorUid),
      );
    });
  }

  Future<void> _onSync(
    PatientsSyncRequested event,
    Emitter<PatientsState> emit,
  ) {
    final session = _session;
    return _alone(() async {
      if (!_live(session)) return;
      _emit(
        emit,
        session,
        PatientsLoadInProgress(
          patients: state.patientsFor(event.doctorUid),
          doctorUid: event.doctorUid,
        ),
      );
      await _emitRows(
        emit,
        session,
        event.doctorUid,
        () => _sync.drain(event.doctorUid, isCurrent: () => _live(session)),
      );
    });
  }

  Future<void> _onAdded(PatientsAdded event, Emitter<PatientsState> emit) {
    final session = _session;
    return _alone(() async {
      if (!_live(session)) return;
      final pending = await _sync.remember(event.patient);
      unawaited(_analytics.logPatientAdded());
      final shown = _with(state.patientsFor(event.doctorUid), pending);
      _emit(
        emit,
        session,
        PatientsLoadSuccess(patients: shown, doctorUid: event.doctorUid),
      );
      try {
        final rows = await _sync.drain(
          event.doctorUid,
          isCurrent: () => _live(session),
        );
        _emit(
          emit,
          session,
          PatientsLoadSuccess(
            patients: _mine(rows, event.doctorUid),
            doctorUid: event.doctorUid,
          ),
        );
      } on Object catch (error) {
        _emit(
          emit,
          session,
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
    int session,
    String doctorUid,
    Future<List<PatientModel>> Function() read,
  ) async {
    try {
      final rows = await read();
      _emit(
        emit,
        session,
        PatientsLoadSuccess(
          patients: _mine(rows, doctorUid),
          doctorUid: doctorUid,
        ),
      );
    } on Object catch (error) {
      _emit(
        emit,
        session,
        PatientsLoadFailure(
          patients: state.patientsFor(doctorUid),
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
