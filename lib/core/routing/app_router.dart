import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/helpers/role_helper.dart';
import 'package:tabibu/core/routing/app_routes.dart';
import 'package:tabibu/core/routing/landing.dart';
import 'package:tabibu/features/auth/blocs/auth_bloc/auth_bloc.dart';
import 'package:tabibu/features/auth/data/models/auth_session.dart';

/// The one router (architecture §8). Built once with the [AuthBloc] above
/// it; the guard runs again whenever the session changes, so signing out
/// moves anyone on a role route back through the decision route.
abstract final class TabibuRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey(
    debugLabel: 'root',
  );

  static GoRouter create(AuthBloc authBloc) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: const DecisionRoute().location,
    routes: $appRoutes,
    refreshListenable: SessionChanges(authBloc),
    redirect: (context, state) => guardLocation(
      location: state.uri.toString(),
      session: authBloc.state.session,
    ),
    errorBuilder: (context, state) =>
        const DecisionRoute().build(context, state),
  );
}

/// Tells the router to run its guard again.
@visibleForTesting
class SessionChanges extends ChangeNotifier {
  SessionChanges(AuthBloc bloc) {
    // Only what guardLocation reads: who is signed in and their claims. A
    // profile save changes the session too, and refreshing on it could put
    // back a screen the save had just popped.
    _subscription = bloc.stream
        .map((state) => _guardKey(state.session))
        .distinct()
        .listen((_) => notifyListeners());
  }

  late final StreamSubscription<(Type, RoleHelper?)> _subscription;

  static (Type, RoleHelper?) _guardKey(AuthSession session) => (
    session.runtimeType,
    switch (session) {
      PatientSession(:final roles) => roles,
      PractitionerSession(:final roles) => roles,
      _ => null,
    },
  );

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
