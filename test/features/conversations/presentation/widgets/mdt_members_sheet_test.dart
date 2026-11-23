import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_model.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_members_sheet.dart';
import 'package:tabibu/l10n/l10n.dart';

import '../../../../helpers/helpers.dart';

final _owner = ConversationMemberModel(
  uid: 'achieng',
  memberRole: 'Owner',
  title: 'Dr.',
  firstName: 'Achieng' * 4,
  lastName: 'Odhiambo',
  specialty: 'Haematology',
  status: 'Accepted',
);

const _colleague = ConversationMemberModel(
  uid: 'njeri',
  title: 'Dr.',
  firstName: 'Njeri',
  lastName: 'Kamau',
  specialty: 'Histopathology',
  status: 'Accepted',
);

ConversationModel _consult() => ConversationModel(
  uid: 'mdt-1',
  createdByUid: 'achieng',
  createdAt: '2026-11-04T10:00:00Z',
  members: {'achieng': _owner, 'njeri': _colleague},
);

Finder _adminChips() => find.byWidgetPredicate(
  (widget) =>
      widget is StatusChip &&
      widget.label == lookupAppLocalizations(const Locale('en')).mdtAdmin &&
      widget.tone == .signed,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> openSheet(
    WidgetTester tester, {
    required String myUid,
    double textScale = 1,
    Locale locale = const Locale('en'),
    Size size = const Size(1170, 4000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpApp(
      Builder(
        builder: (context) => TabibuButton.primary(
          label: 'Open',
          onTap: () => unawaited(
            showMdtMembersSheet(context, consult: _consult(), myUid: myUid),
          ),
        ),
      ),
      locale: locale,
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the creator carries the Admin chip and nobody else does', (
    tester,
  ) async {
    await openSheet(tester, myUid: 'njeri');
    expect(_adminChips(), findsOneWidget);
    expect(find.text(l10n.mdtYou), findsOneWidget);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).mdtAdmin),
      findsOneWidget,
    );
  });

  testWidgets('your own row as creator shows Admin and You', (tester) async {
    await openSheet(tester, myUid: 'achieng');
    expect(_adminChips(), findsOneWidget);
    expect(find.text(l10n.mdtYou), findsOneWidget);
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).mdtAdmin),
      findsOneWidget,
    );
  });

  testWidgets('a long name fits at 2.0x in Swahili on a narrow phone', (
    tester,
  ) async {
    await openSheet(
      tester,
      myUid: 'achieng',
      textScale: 2,
      locale: const Locale('sw'),
      size: const Size(360 * 3, 2400 * 3),
    );
    expect(tester.takeException(), isNull);
  });
}
