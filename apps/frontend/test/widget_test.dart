// Smoke test: the app renders the wallet connect screen on launch.
import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/main.dart';
import 'package:pingblock_game/services/wallet_service.dart';

// ── Mock (identical to the one in wallet_connect_screen_test.dart) ────────────

class _MockWalletService implements WalletService {
  @override
  Future<WalletConnectionResult?> connect() async => null;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  testWidgets('app renders WalletConnectScreen first', (tester) async {
    await tester.pumpWidget(PingBlockApp(walletService: _MockWalletService()));
    await tester.pump();

    // The wallet connect screen should show the title and the connect button.
    expect(find.text('PING\nBLOCK'),       findsOneWidget);
    expect(find.text('CONNECT WALLET'),    findsOneWidget);
  });
}
