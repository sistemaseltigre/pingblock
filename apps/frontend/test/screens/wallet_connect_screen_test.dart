// Widget tests for WalletConnectScreen.
// All tests use a [MockWalletService] — no physical device or wallet required.
//
// Design constraints:
//   1. WalletConnectScreen has a forever-repeating ScaleTransition (pulse
//      animation), so pumpAndSettle() never settles. Use pump(duration) instead.
//   2. LobbyScreen.initState() opens a real socket. Tests deliberately avoid
//      advancing past the 600 ms navigation delay to prevent LobbyScreen from
//      being rendered in the test host.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingblock_game/screens/wallet_connect_screen.dart';
import 'package:pingblock_game/services/wallet_service.dart';

// ── Mock ──────────────────────────────────────────────────────────────────────

class MockWalletService implements WalletService {
  final WalletConnectionResult? _result;
  final Duration _delay;

  int connectCallCount = 0;

  MockWalletService({
    WalletConnectionResult? result,
    Duration delay = Duration.zero,
  })  : _result = result,
        _delay = delay;

  @override
  Future<WalletConnectionResult?> connect() async {
    connectCallCount++;
    await Future.delayed(_delay);
    return _result;
  }

  @override
  Future<int?> getBalanceLamports(String walletAddress) async => null;

  @override
  Future<String?> signAndSendTransactionBase64({
    required String transactionBase64,
  }) async =>
      null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _testAddress = '4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL';
const _testResult =
    WalletConnectionResult(address: _testAddress, authToken: 'tok');

Widget _buildScreen(WalletService service) {
  return MaterialApp(home: WalletConnectScreen(walletService: service));
}

/// Pump just enough frames to resolve a zero-delay future (connect() returns
/// immediately) but stop well before the 600 ms navigation timer fires.
Future<void> _pumpUntilConnectResolves(WidgetTester tester) async {
  await tester.pump(); // tap callback starts
  await tester.pump(); // connect() resolves, setState is called
  await tester.pump(); // rebuild with new state
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WalletConnectScreen — initial state', () {
    testWidgets('shows CONNECT WALLET button', (tester) async {
      await tester.pumpWidget(_buildScreen(MockWalletService()));
      expect(find.text('CONNECT WALLET'), findsOneWidget);
    });

    testWidgets('shows PING BLOCK title', (tester) async {
      await tester.pumpWidget(_buildScreen(MockWalletService()));
      expect(find.text('PING\nBLOCK'), findsOneWidget);
    });

    testWidgets('shows wallet icon', (tester) async {
      await tester.pumpWidget(_buildScreen(MockWalletService()));
      expect(
          find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    });

    testWidgets('shows supported wallet chips', (tester) async {
      await tester.pumpWidget(_buildScreen(MockWalletService()));
      expect(find.text('Phantom'), findsOneWidget);
      expect(find.text('Solflare'), findsOneWidget);
      expect(find.text('Seed Vault'), findsOneWidget);
    });

    testWidgets('no status message on first render', (tester) async {
      await tester.pumpWidget(_buildScreen(MockWalletService()));
      expect(find.textContaining('Connected'), findsNothing);
      expect(find.textContaining('cancelled'), findsNothing);
    });
  });

  group('WalletConnectScreen — loading state', () {
    // Using a mock with a long delay so connect() is still pending during the
    // assertions. pumpAndSettle() is NOT used here because the repeating
    // ScaleTransition never settles. Instead, we advance the clock step by step.

    testWidgets('shows Connecting… spinner while awaiting result',
        (tester) async {
      final svc = MockWalletService(
        result: null, // resolves to null (cancel)
        delay: const Duration(seconds: 10),
      );

      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      await tester.pump(); // trigger setState → _connecting = true

      // Spinner visible while loading.
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Drain the 10 s delay so the mock resolves and the test can close.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('button is disabled while connecting', (tester) async {
      final svc = MockWalletService(
        result: null,
        delay: const Duration(seconds: 10),
      );
      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);

      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('WalletConnectScreen — error state', () {
    testWidgets('shows error when connect() returns null', (tester) async {
      final svc = MockWalletService(result: null);
      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      // pump() resolves the instant-null future; pump(200ms) lets AnimatedSwitcher
      // complete the fade-in so the text is findable.
      await _pumpUntilConnectResolves(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('cancelled or failed'), findsOneWidget);
    });

    testWidgets('button is re-enabled after failure', (tester) async {
      final svc = MockWalletService(result: null);
      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      await _pumpUntilConnectResolves(tester);
      await tester.pump(const Duration(milliseconds: 400));

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('can retry — connect() called again after failure',
        (tester) async {
      final svc = MockWalletService(result: null);
      await tester.pumpWidget(_buildScreen(svc));

      await tester.tap(find.text('CONNECT WALLET'));
      await _pumpUntilConnectResolves(tester);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('CONNECT WALLET'));
      await _pumpUntilConnectResolves(tester);
      // Drain AnimatedSwitcher fade so no timer is pending at teardown.
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.connectCallCount, 2);
    });
  });

  group('WalletConnectScreen — success state', () {
    testWidgets('shows "Connected as …" confirmation text', (tester) async {
      final formatted =
          WalletUtils.formatAddress(_testAddress); // "4Nd1...nEKL"
      final svc = MockWalletService(result: _testResult);

      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      await _pumpUntilConnectResolves(tester);
      // Let AnimatedSwitcher fade in the text.
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Connected as $formatted'), findsOneWidget);
    });

    testWidgets('connect() is called exactly once per tap', (tester) async {
      final svc =
          MockWalletService(result: null); // instant failure, no navigation
      await tester.pumpWidget(_buildScreen(svc));
      await tester.tap(find.text('CONNECT WALLET'));
      await _pumpUntilConnectResolves(tester);
      // Drain any pending animation timers (AnimatedSwitcher fade-in).
      await tester.pump(const Duration(milliseconds: 400));

      expect(svc.connectCallCount, 1);
    });

    testWidgets('second tap while loading is ignored (button disabled)',
        (tester) async {
      final svc = MockWalletService(
        result: null,
        delay: const Duration(seconds: 10),
      );
      await tester.pumpWidget(_buildScreen(svc));

      await tester.tap(find.text('CONNECT WALLET'));
      await tester.pump(); // now loading

      // Attempt a second tap — should be ignored because button is disabled.
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();

      expect(svc.connectCallCount, 1); // only one call despite two taps

      await tester.pump(const Duration(seconds: 11)); // drain mock delay
    });
  });
}
