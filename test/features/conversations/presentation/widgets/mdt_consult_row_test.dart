import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/core/widgets/widgets.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/data/models/conversation_model.dart';
import 'package:tabibu/features/conversations/presentation/mdt_labels.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_avatar_stack.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_consult_row.dart';

import '../../../../helpers/helpers.dart';

ConversationModel _consult() => const ConversationModel(
  uid: 'mdt-1',
  createdByUid: 'achieng',
  members: {
    'achieng': ConversationMemberModel(
      uid: 'achieng',
      memberRole: 'Owner',
      title: 'Dr.',
      firstName: 'Achieng',
      lastName: 'Odhiambo',
      status: 'Accepted',
    ),
    'njeri': ConversationMemberModel(
      uid: 'njeri',
      title: 'Dr.',
      firstName: 'Njeri',
      lastName: 'Kamau',
      status: 'Accepted',
    ),
    'wambui': ConversationMemberModel(
      uid: 'wambui',
      title: 'Dr.',
      firstName: 'Wambui',
      lastName: 'Otieno',
      status: 'Accepted',
    ),
  },
);

void main() {
  Future<void> pumpRow(WidgetTester tester, {required String myUid}) {
    return tester.pumpApp(
      MdtConsultRow(consult: _consult(), myUid: myUid, onTap: () {}),
    );
  }

  testWidgets('the row shows one avatar, the creator, whoever is signed in', (
    tester,
  ) async {
    await pumpRow(tester, myUid: 'njeri');
    expect(find.byType(Avatar), findsOneWidget);
    expect(
      tester.widget<Avatar>(find.byType(Avatar)).name,
      mdtMemberName(mdtConsultOwner(_consult())),
    );
  });

  testWidgets('a consult with many members still shows one avatar', (
    tester,
  ) async {
    await pumpRow(tester, myUid: 'achieng');
    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byType(MdtAvatarStack), findsNothing);
  });
}
