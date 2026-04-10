import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/main.dart';

void main() {
  testWidgets('PingBlock app renders lobby screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PingBlockApp());
    await tester.pump();
    // Lobby should show the game title
    expect(find.text('PING\nBLOCK'), findsOneWidget);
  });
}
