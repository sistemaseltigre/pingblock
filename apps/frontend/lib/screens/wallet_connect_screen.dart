import 'dart:async';
import 'package:flutter/material.dart';
import '../services/wallet_service.dart';
import 'lobby_screen.dart';

/// First screen the user sees.
/// Prompts them to connect their Solana wallet via MWA before entering the lobby.
class WalletConnectScreen extends StatefulWidget {
  final WalletService walletService;

  const WalletConnectScreen({super.key, required this.walletService});

  @override
  State<WalletConnectScreen> createState() => _WalletConnectScreenState();
}

class _WalletConnectScreenState extends State<WalletConnectScreen>
    with SingleTickerProviderStateMixin {
  bool _connecting = false;
  String _statusMessage = '';
  bool _hasError = false;

  /// Cancellable timer for the brief "Connected as …" confirmation pause.
  /// Cancelled in dispose() so the test host never sees a pending timer.
  Timer? _navTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Connect flow ───────────────────────────────────────────────────────────

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _statusMessage = 'Opening wallet…';
      _hasError = false;
    });

    final result = await widget.walletService.connect();

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _connecting = false;
        _statusMessage = 'Connection cancelled or failed. Please try again.';
        _hasError = true;
      });
      return;
    }

    final displayName = WalletUtils.formatAddress(result.address);

    setState(() {
      _connecting = false;
      _statusMessage = 'Connected as $displayName';
    });

    // Brief pause so the user sees the confirmation before the screen changes.
    // Using a cancellable Timer so dispose() can clean it up if the widget
    // is removed before the 600 ms window elapses.
    _navTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LobbyScreen(
            walletAddress: result.address,
            displayName: displayName,
            walletBalanceLamportsProvider: (walletAddress) =>
                widget.walletService.getBalanceLamports(walletAddress),
            escrowTransactionSender: ({
              required String transactionBase64,
            }) =>
                widget.walletService.signAndSendTransactionBase64(
              transactionBase64: transactionBase64,
            ),
            transactionConfirmer: (signature) =>
                widget.walletService.confirmTransaction(signature),
          ),
        ),
      );
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo ──────────────────────────────────────────────────
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFF64D9FF)],
                  ).createShader(b),
                  child: const Text(
                    'PING\nBLOCK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                      letterSpacing: 8,
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  'Multiplayer · Solana · NFT Paddles',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 64),

                // ── Wallet icon ───────────────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF9945FF).withValues(alpha: 0.12),
                      border: Border.all(
                        color: const Color(0xFF9945FF).withValues(alpha: 0.40),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFF9945FF),
                      size: 42,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Connect your Solana wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your wallet address will be used as\nyour in-game identity.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white38, fontSize: 13, height: 1.5),
                ),

                const SizedBox(height: 36),

                // ── Connect button ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _connecting ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _connecting
                          ? Colors.grey.shade800
                          : const Color(0xFF9945FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _connecting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Connecting…',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_wallet, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'CONNECT WALLET',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Status / error ────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _statusMessage.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(_statusMessage),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _hasError
                                  ? const Color(0xFFFF6B35)
                                  : const Color(0xFF64D9FF),
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 40),

                // ── Supported wallets note ────────────────────────────────
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _WalletChip(label: 'Phantom'),
                    SizedBox(width: 8),
                    _WalletChip(label: 'Solflare'),
                    SizedBox(width: 8),
                    _WalletChip(label: 'Seed Vault'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Any MWA-compatible wallet works',
                  style: TextStyle(
                      color: Colors.white24, fontSize: 10, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Supporting widget ─────────────────────────────────────────────────────────

class _WalletChip extends StatelessWidget {
  final String label;
  const _WalletChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white38, fontSize: 10),
      ),
    );
  }
}
