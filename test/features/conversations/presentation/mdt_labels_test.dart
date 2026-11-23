import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/presentation/mdt_labels.dart';

void main() {
  test('a sender label is the title, the first name and initials', () {
    expect(
      mdtMemberSenderLabel(
        const ConversationMemberModel(
          title: 'Dr.',
          firstName: 'Achieng',
          lastName: 'Odhiambo',
        ),
      ),
      'Dr. Achieng O.',
    );
  });

  test('a middle name is an initial too', () {
    expect(
      mdtMemberSenderLabel(
        const ConversationMemberModel(
          title: 'Dr.',
          firstName: 'Achieng',
          lastName: 'Wanjiku Odhiambo',
        ),
      ),
      'Dr. Achieng W. O.',
    );
    expect(
      mdtMemberSenderLabel(
        const ConversationMemberModel(
          title: 'Dr.',
          firstName: 'Achieng Wanjiku',
          lastName: 'Odhiambo',
        ),
      ),
      'Dr. Achieng W. O.',
    );
  });

  test('a missing title is left out', () {
    expect(
      mdtMemberSenderLabel(
        const ConversationMemberModel(
          firstName: 'Achieng',
          lastName: 'Odhiambo',
        ),
      ),
      'Achieng O.',
    );
  });

  test('a first name alone stands by itself', () {
    expect(
      mdtMemberSenderLabel(const ConversationMemberModel(firstName: 'Achieng')),
      'Achieng',
    );
  });
}
