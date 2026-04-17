import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/screens/lobby_screen.dart';
import 'package:pingblock_game/services/socket_service.dart';

class _FakeSocketService extends SocketService {
  @override
  void connect() {}

  @override
  void disconnect() {}
}

void main() {
  Widget buildScreen() {
    return MaterialApp(
      home: LobbyScreen(
        walletAddress: '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL',
        displayName: '4Nd1...nEKL',
        socketService: _FakeSocketService(),
      ),
    );
  }

  testWidgets('switches to wager mode and opens wager modal', (tester) async {
    await tester.pumpWidget(buildScreen());

    expect(find.text('FIND MATCH'), findsOneWidget);

    await tester.tap(find.text('WAGER'));
    await tester.pumpAndSettle();

    expect(find.text('SET SOL WAGER'), findsOneWidget);

    await tester.tap(find.text('SET SOL WAGER'));
    await tester.pumpAndSettle();

    expect(find.text('Wager Amount (SOL)'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
  });
}
