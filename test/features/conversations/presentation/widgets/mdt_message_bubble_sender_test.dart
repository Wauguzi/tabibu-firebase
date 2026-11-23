import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabibu/features/conversations/data/models/conversation_member_model.dart';
import 'package:tabibu/features/conversations/data/models/message_model.dart';
import 'package:tabibu/features/conversations/presentation/mdt_labels.dart';
import 'package:tabibu/features/conversations/presentation/widgets/mdt_message_bubble.dart';
import 'package:tabibu/features/conversations/presentation/widgets/voice_note_player.dart';

import '../../../../helpers/helpers.dart';

final _achieng = ConversationMemberModel(
  uid: 'achieng',
  title: 'Dr.',
  firstName: 'Achieng' * 4,
  lastName: 'Odhiambo',
);

const _text = MessageModel(
  uid: 'm1',
  text: 'Seen in one node.',
  sentAt: '2026-11-04T10:00:00Z',
);

const _voice = MessageModel(
  uid: 'v1',
  kind: 'Voice',
  voiceDurationMs: 61000,
  voicePeaks: [10, 40, 70, 40, 10],
  sentAt: '2026-11-04T10:00:00Z',
);

void main() {
  late FakeAudioPlayerService player;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    player = FakeAudioPlayerService();
  });

  tearDown(() async {
    await player.dispose();
  });

  Future<void> pumpBubble(
    WidgetTester tester, {
    required MessageModel message,
    required bool mine,
    double width = 390,
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpApp(
      SizedBox(
        width: width,
        child: MdtMessageBubble(
          message: message,
          mine: mine,
          sender: _achieng,
          voiceSurface: 'mdt',
          loadVoiceBytes: (_) async => Uint8List.fromList([1, 2, 3]),
          player: player,
        ),
      ),
      locale: locale,
    );
    await tester.pump();
  }

  testWidgets('a colleague bubble shows the sender above the text', (
    tester,
  ) async {
    await pumpBubble(tester, message: _text, mine: false);
    final label = mdtMemberSenderLabel(_achieng);
    expect(find.text(label), findsOneWidget);
    final sender = tester.getTopLeft(find.text(label));
    final message = tester.getTopLeft(find.text(_text.text));
    expect(sender.dy, lessThan(message.dy));
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        '$label: ${_text.text}, ${mdtClockLabel(_text.sentAt, 'en')}',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('my bubble has no sender line and the time sits to the right', (
    tester,
  ) async {
    await pumpBubble(tester, message: _text, mine: true);
    expect(find.text(mdtMemberSenderLabel(_achieng)), findsNothing);
    final message = tester.getRect(find.text(_text.text));
    final time = tester.getRect(find.text(mdtClockLabel(_text.sentAt, 'en')));
    expect(time.top, greaterThan(message.top));
    expect(time.right, greaterThan(message.left));
    expect(
      tester.widget<Column>(find.byType(Column).first).mainAxisAlignment,
      MainAxisAlignment.center,
    );
  });

  testWidgets('a colleague voice note carries the sender line', (tester) async {
    await pumpBubble(tester, message: _voice, mine: false);
    final label = mdtMemberSenderLabel(_achieng);
    expect(find.text(label), findsOneWidget);
    expect(find.byType(VoiceNotePlayer), findsOneWidget);
    final sender = tester.getTopLeft(find.text(label));
    final player = tester.getTopLeft(find.byType(VoiceNotePlayer));
    expect(sender.dy, lessThan(player.dy));
  });

  testWidgets('a long sender fits at 2.0x in Swahili on a narrow phone', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      message: _text,
      mine: false,
      width: 360,
      textScale: 2,
      locale: const Locale('sw'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(mdtMemberSenderLabel(_achieng)), findsOneWidget);
  });
}
