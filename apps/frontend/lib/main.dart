import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/wallet_connect_screen.dart';
import 'services/wallet_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow both portrait (lobby/wallet) and landscape (game).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PingBlockApp());
}

class PingBlockApp extends StatelessWidget {
  /// Inject a custom [WalletService] (e.g. a mock in tests).
  /// Defaults to the real [MobileWalletAdapterService] in production.
  final WalletService? walletService;

  const PingBlockApp({super.key, this.walletService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PingBlock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6B35),
          secondary: Color(0xFF64D9FF),
        ),
      ),
      home: WalletConnectScreen(
        walletService: walletService ?? MobileWalletAdapterService(),
      ),
    );
  }
}
