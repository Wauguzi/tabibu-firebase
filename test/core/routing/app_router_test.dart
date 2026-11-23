import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/constants/enums.dart';
import 'package:tabibu/core/helpers/role_helper.dart';
import 'package:tabibu/core/routing/app_router.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_state.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';

import '../../helpers/role_sessions.dart';

void main() {
  group('SessionChanges', () {
    late StreamController<AuthState> states;
    late SessionChanges changes;
    late int refreshes;

    setUp(() {
      states = StreamController<AuthState>();
      final bloc = MockAuthBloc();
      whenListen(
        bloc,
        states.stream,
        initialState: SignInSuccess(session: RoleSessions.patient),
      );
      changes = SessionChanges(bloc);
      refreshes = 0;
      changes.addListener(() => refreshes++);
    });

    tearDown(() async {
      changes.dispose();
      await states.close();
    });

    Future<void> emit(AuthSession session) async {
      states.add(SignInSuccess(session: session));
      await Future<void>.delayed(Duration.zero);
    }

    test('a profile save does not run the guard again', () async {
      await emit(RoleSessions.patient);
      expect(refreshes, 1, reason: 'the first session counts once');

      await emit(
        PatientSession(
          patient: RoleSessions.patient.patient.copyWith(firstName: 'Grace'),
          roles: RoleSessions.patient.roles,
        ),
      );

      expect(refreshes, 1);
    });

    test('signing out, or a change of claims, runs it again', () async {
      await emit(RoleSessions.patient);
      await emit(const SignedOutSession());
      expect(refreshes, 2);

      await emit(RoleSessions.doctor());
      await emit(RoleSessions.doctor(isAlertApprover: true));
      expect(refreshes, 4);
    });

    test('an equal claim set built anew is not a change', () async {
      await emit(RoleSessions.doctor());
      await emit(
        PractitionerSession(
          doctor: RoleSessions.doctor().doctor.copyWith(bio: 'New bio'),
          roles: const RoleHelper(
            role: Role.doctor,
            isAdmin: false,
            isAlertApprover: false,
          ),
        ),
      );
      expect(refreshes, 1);
    });
  });
}
