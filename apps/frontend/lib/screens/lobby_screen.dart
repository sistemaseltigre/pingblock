import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_state.dart';
import '../models/paddle_type.dart';
import '../models/wager_amount.dart';
import '../services/socket_service.dart';
import '../services/wager_api_service.dart';
import 'game_screen.dart';

enum _GameMode { free, wager }

typedef WalletBalanceLamportsProvider = Future<int?> Function(
    String walletAddress);
typedef EscrowTransactionSender = Future<String?> Function({
  required String transactionBase64,
});

class LobbyScreen extends StatefulWidget {
  /// Full base58 wallet address (e.g. "4Nd1mBQtrMJVYVfKf2PX98AeguLmasRF3zjeA3FEnEKL").
  final String walletAddress;

  /// Pre-formatted display name shown in the UI (e.g. "4Nd1...EKL").
  final String displayName;

  /// Optional dependency injection for tests.
  final SocketService? socketService;

  /// Optional pre-check of wallet balance before joining wager queue.
  final WalletBalanceLamportsProvider? walletBalanceLamportsProvider;

  /// Optional sender for a prepared base64 transaction.
  final EscrowTransactionSender? escrowTransactionSender;

  const LobbyScreen({
    super.key,
    required this.walletAddress,
    required this.displayName,
    this.socketService,
    this.walletBalanceLamportsProvider,
    this.escrowTransactionSender,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final SocketService _socket;
  // Read-only: name is derived from the connected wallet — not user-editable.
  late final TextEditingController _nameController;
  String _status = 'Disconnected';
  bool _searching = false;
  bool _busyWagerFlow = false;
  // True once we push the GameScreen so dispose() doesn't kill the socket mid-game
  bool _navigatedToGame = false;

  // CPU mode state
  String _selectedDifficulty = 'medium';
  bool _showCpuOptions = false;

  _GameMode _selectedMode = _GameMode.free;
  int? _activeWagerLamports;
  final _wagerApi = WagerApiService();

  static const _difficulties = ['easy', 'medium', 'hard'];
  static const _difficultyLabels = {
    'easy': 'Easy   — 40% reaction, imperfect aim',
    'medium': 'Medium — 70% reaction, occasional power use',
    'hard': 'Hard   — 95% reaction, ball prediction + powers',
  };

  @override
  void initState() {
    super.initState();
    _socket = widget.socketService ?? SocketService();
    // The display name comes from the wallet — it is read-only and cannot
    // be changed by the user.
    _nameController = TextEditingController(text: widget.displayName);
    _connectAndSetup();
  }

  void _connectAndSetup() {
    _socket.connect();
    setState(() => _status = 'Ready to play');

    _socket.onLobbyJoined((_) {
      setState(() => _status = 'Searching for opponent...');
    });

    _socket.onWagerLobbyJoined((data) {
      final map = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
      final lamports = map['lamports'] as int? ?? _activeWagerLamports;
      final wagerText = lamports == null
          ? ''
          : ' (${WagerAmountParser.lamportsToSolText(lamports)} SOL)';
      setState(() {
        _status = 'Wager queued$wagerText. Searching opponent...';
      });
    });

    _socket.onMatchFound(_handleMatchFound);
    _socket.onWagerMatchFound(_handleMatchFound);

    _socket.onWagerRefundPending((_) {
      setState(() => _status = 'Cancelling search. Refund pending...');
    });

    _socket.onWagerRefundDone((_) {
      setState(() {
        _status = 'Wager refunded successfully';
        _searching = false;
        _activeWagerLamports = null;
      });
    });

    _socket.onWagerSettlementPending((_) {
      setState(() => _status = 'Match ended. Settling wager...');
    });

    _socket.onWagerSettlementDone((_) {
      setState(() => _status = 'Wager settlement completed');
    });

    _socket.onWagerError((data) {
      final map = data is Map ? data : <String, dynamic>{};
      final msg = map['message']?.toString() ?? 'Unknown wager error';
      setState(() {
        _status = 'Wager error: $msg';
        _searching = false;
        _busyWagerFlow = false;
      });
    });

    _socket.onServerError((data) {
      final map = data is Map ? data : <String, dynamic>{};
      final msg = map['message']?.toString() ?? 'Unknown server error';
      setState(() {
        _status = 'Error: $msg';
        _searching = false;
        _busyWagerFlow = false;
      });
    });
  }

  void _handleMatchFound(dynamic data) {
    final d = data as Map<String, dynamic>;
    setState(() {
      _status = 'Match found!';
      _searching = false;
      _busyWagerFlow = false;
    });

    final leftInfo = d['left'] as Map<String, dynamic>;
    final rightInfo = d['right'] as Map<String, dynamic>;
    final isCpu = d['vscpu'] as bool? ?? false;

    // Human is always on 'right' in CPU games.
    // In PvP, determine side by matching our name against left.
    String mySide;
    if (isCpu) {
      mySide = 'right';
    } else {
      final myName = _nameController.text.trim();
      mySide = (leftInfo['name'] as String) == myName ? 'left' : 'right';
    }

    final gs = GameState()
      ..roomId = d['roomId'] as String
      ..mySide = mySide
      ..leftPlayer = PlayerInfo(
        name: leftInfo['name'] as String,
        paddleType: PaddleType.fromString(leftInfo['paddleType'] as String),
      )
      ..rightPlayer = PlayerInfo(
        name: rightInfo['name'] as String,
        paddleType: PaddleType.fromString(rightInfo['paddleType'] as String),
      );

    _socket.onGameStart((_) {
      if (!mounted) return;
      // Mark navigated BEFORE pushReplacement so dispose() doesn't disconnect the socket
      _navigatedToGame = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameScreen(
            gameState: gs,
            socketService: _socket,
            mySide: mySide,
            walletAddress: widget.walletAddress,
            displayName: widget.displayName,
          ),
        ),
      );
    });
  }

  void _findMatch() {
    // Always use the wallet-derived display name as the matchmaking identity.
    final name = widget.displayName.isNotEmpty ? widget.displayName : 'Player';
    setState(() => _searching = true);
    _socket.joinLobby(name);
  }

  Future<void> _findWagerMatch() async {
    final lamports = await _promptWagerLamports();
    if (lamports == null || !mounted) return;

    setState(() {
      _busyWagerFlow = true;
      _status = 'Preparing wager escrow...';
    });

    try {
      final hasBalance = await _validateBalanceIfPossible(lamports);
      if (!mounted || !hasBalance) {
        setState(() => _busyWagerFlow = false);
        return;
      }

      final prepared = await _wagerApi.prepareEscrow(
        walletAddress: widget.walletAddress,
        lamports: lamports,
      );
      final escrowSig = await _sendPreparedEscrowTransaction(prepared.txBase64);
      if (!mounted) return;
      if (escrowSig == null) {
        setState(() {
          _busyWagerFlow = false;
          _status = 'Escrow transaction was cancelled or failed';
        });
        return;
      }

      final name =
          widget.displayName.isNotEmpty ? widget.displayName : 'Player';
      setState(() {
        _busyWagerFlow = false;
        _searching = true;
        _activeWagerLamports = lamports;
        _status =
            'Escrow signed (${WagerAmountParser.lamportsToSolText(lamports)} SOL). Joining wager queue...';
      });

      _socket.joinWagerLobby(
        playerName: name,
        lamports: lamports,
        wallet: widget.walletAddress,
        escrowTxSig: escrowSig,
        intentId: prepared.intentId,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busyWagerFlow = false;
        _searching = false;
        _status = 'Failed to start wager flow';
      });
    }
  }

  Future<void> _cancelWagerSearch() async {
    if (!_searching) return;
    setState(() => _status = 'Cancelling wager search...');
    _socket.cancelWagerSearch();
  }

  Future<void> _playVsCpu() async {
    final name = widget.displayName.isNotEmpty ? widget.displayName : 'Player';
    setState(() => _searching = true);
    _socket.joinVsCpu(name, _selectedDifficulty);
  }

  Future<bool> _validateBalanceIfPossible(int lamports) async {
    final provider = widget.walletBalanceLamportsProvider;
    if (provider == null) return true;

    final available = await provider(widget.walletAddress);
    if (available == null) {
      setState(() => _status = 'Could not verify wallet balance. Try again');
      return false;
    }
    if (available < lamports) {
      setState(() {
        _status =
            'Insufficient balance. Need ${WagerAmountParser.lamportsToSolText(lamports)} SOL';
      });
      return false;
    }
    return true;
  }

  Future<String?> _sendPreparedEscrowTransaction(String txBase64) async {
    final provider = widget.escrowTransactionSender;
    if (provider != null) {
      return provider(transactionBase64: txBase64);
    }

    // Dev fallback if no sender is injected.
    await Future.delayed(const Duration(milliseconds: 300));
    return 'mock_escrow_${DateTime.now().millisecondsSinceEpoch}_${max(1, txBase64.length % 999999)}';
  }

  Future<int?> _promptWagerLamports() async {
    final controller = TextEditingController(text: '0.05');
    String? error;

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: !_busyWagerFlow,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final preview =
                WagerAmountParser.parseSolToLamports(controller.text);
            final validLamports = preview.lamports;
            final potText = validLamports == null
                ? '-'
                : WagerAmountParser.lamportsToSolText(validLamports * 2);
            final winnerText = validLamports == null
                ? '-'
                : WagerAmountParser.lamportsToSolText(
                    (validLamports * 18) ~/ 10);
            final treasuryText = validLamports == null
                ? '-'
                : WagerAmountParser.lamportsToSolText(
                    (validLamports * 2) ~/ 10);

            return AlertDialog(
              backgroundColor: const Color(0xFF141427),
              title: const Text(
                'Wager Amount (SOL)',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,9}$')),
                    ],
                    decoration: InputDecoration(
                      hintText: '0.05',
                      labelText: 'Amount',
                      suffixText: 'SOL',
                      errorText: error,
                    ),
                    onChanged: (_) {
                      setDialogState(() {
                        error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _WagerPreviewLine(
                      label: 'Estimated pot', value: '$potText SOL'),
                  _WagerPreviewLine(
                      label: 'Winner payout (90%)', value: '$winnerText SOL'),
                  _WagerPreviewLine(
                      label: 'Treasury (10%)', value: '$treasuryText SOL'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final parsed =
                        WagerAmountParser.parseSolToLamports(controller.text);
                    if (!parsed.isValid) {
                      setDialogState(() {
                        error = parsed.error;
                      });
                      return;
                    }
                    Navigator.of(context).pop(parsed.lamports);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  @override
  void dispose() {
    _nameController.dispose();
    // Only disconnect if we're truly leaving (not transitioning into a game)
    if (!_navigatedToGame) _socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlsDisabled = _searching || _busyWagerFlow;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Title ──────────────────────────────────────────────────
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFF64D9FF)],
                  ).createShader(b),
                  child: const Text(
                    'PING\nBLOCK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Multiplayer · Solana · NFT Paddles',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11, letterSpacing: 2),
                ),

                const SizedBox(height: 36),

                // ── Paddle type preview ────────────────────────────────────
                _PaddleTypeGrid(),

                const SizedBox(height: 32),

                // ── Wallet identity (read-only) ────────────────────────────
                TextField(
                  controller: _nameController,
                  readOnly: true,
                  style: const TextStyle(
                    color: Color(0xFF9945FF),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Your Wallet',
                    labelStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.account_balance_wallet,
                      color: Color(0xFF9945FF),
                      size: 18,
                    ),
                    suffixIcon: const Icon(
                      Icons.lock_outline,
                      color: Colors.white24,
                      size: 16,
                    ),
                    helperText: widget.walletAddress,
                    helperStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: const Color(0xFF9945FF).withValues(alpha: 0.35),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: const Color(0xFF9945FF).withValues(alpha: 0.6),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _ModeSelector(
                  selected: _selectedMode,
                  disabled: controlsDisabled,
                  onChanged: (mode) {
                    if (controlsDisabled) return;
                    setState(() {
                      _selectedMode = mode;
                      _showCpuOptions = false;
                    });
                  },
                ),

                const SizedBox(height: 12),

                if (_selectedMode == _GameMode.free) ...[
                  _PrimaryButton(
                    label: 'FIND MATCH',
                    icon: Icons.people,
                    color: const Color(0xFFFF6B35),
                    loading: _searching,
                    onPressed: controlsDisabled ? null : _findMatch,
                  ),

                  const SizedBox(height: 10),

                  // ── VS CPU toggle + button ───────────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: Column(
                      children: [
                        // Toggle CPU section
                        GestureDetector(
                          onTap: controlsDisabled
                              ? null
                              : () => setState(
                                  () => _showCpuOptions = !_showCpuOptions),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: _showCpuOptions
                                  ? const Color(0xFF64D9FF)
                                      .withValues(alpha: 0.08)
                                  : Colors.transparent,
                              border: Border.all(
                                color: _showCpuOptions
                                    ? const Color(0xFF64D9FF)
                                        .withValues(alpha: 0.4)
                                    : const Color(0xFF2A2A3A),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.smart_toy_outlined,
                                  color: _showCpuOptions
                                      ? const Color(0xFF64D9FF)
                                      : Colors.white38,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Play vs CPU  (debug / local test)',
                                    style: TextStyle(
                                      color: _showCpuOptions
                                          ? const Color(0xFF64D9FF)
                                          : Colors.white38,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _showCpuOptions
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: Colors.white24,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_showCpuOptions) ...[
                          const SizedBox(height: 10),

                          // Difficulty selector
                          ..._difficulties.map((d) => _DifficultyTile(
                                label: d,
                                description: _difficultyLabels[d]!,
                                selected: _selectedDifficulty == d,
                                onTap: () =>
                                    setState(() => _selectedDifficulty = d),
                              )),

                          const SizedBox(height: 12),

                          _PrimaryButton(
                            label: 'START VS CPU',
                            icon: Icons.smart_toy,
                            color: const Color(0xFF64D9FF),
                            loading: _searching,
                            onPressed: controlsDisabled ? null : _playVsCpu,
                            textColor: const Color(0xFF0A0A1A),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  _PrimaryButton(
                    label: _busyWagerFlow
                        ? 'PREPARING ESCROW...'
                        : 'SET SOL WAGER',
                    icon: Icons.local_atm,
                    color: const Color(0xFF14B8A6),
                    loading: _busyWagerFlow,
                    onPressed: controlsDisabled ? null : _findWagerMatch,
                  ),
                  const SizedBox(height: 10),
                  if (_activeWagerLamports != null)
                    _WagerInfoCard(lamports: _activeWagerLamports!),
                  if (_searching) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _cancelWagerSearch,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancel Wager Search'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B35),
                        side: const BorderSide(color: Color(0xFFFF6B35)),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 20),

                // ── Status ─────────────────────────────────────────────────
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final _GameMode selected;
  final bool disabled;
  final ValueChanged<_GameMode> onChanged;

  const _ModeSelector({
    required this.selected,
    required this.disabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF141427),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTab(
              label: 'FREE',
              active: selected == _GameMode.free,
              onTap: disabled ? null : () => onChanged(_GameMode.free),
            ),
          ),
          Expanded(
            child: _ModeTab(
              label: 'WAGER',
              active: selected == _GameMode.wager,
              onTap: disabled ? null : () => onChanged(_GameMode.wager),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _ModeTab({
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active
              ? const Color(0xFF64D9FF).withValues(alpha: 0.16)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF64D9FF) : Colors.white54,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _WagerInfoCard extends StatelessWidget {
  final int lamports;

  const _WagerInfoCard({required this.lamports});

  @override
  Widget build(BuildContext context) {
    final my = WagerAmountParser.lamportsToSolText(lamports);
    final pot = WagerAmountParser.lamportsToSolText(lamports * 2);
    final winner = WagerAmountParser.lamportsToSolText((lamports * 18) ~/ 10);
    final treasury = WagerAmountParser.lamportsToSolText((lamports * 2) ~/ 10);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Wager',
            style: TextStyle(
              color: Color(0xFF14B8A6),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          _WagerPreviewLine(label: 'Your stake', value: '$my SOL'),
          _WagerPreviewLine(label: 'Estimated pot', value: '$pot SOL'),
          _WagerPreviewLine(label: 'Winner payout (90%)', value: '$winner SOL'),
          _WagerPreviewLine(label: 'Treasury (10%)', value: '$treasury SOL'),
        ],
      ),
    );
  }
}

class _WagerPreviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _WagerPreviewLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;
  final Color? textColor;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? Colors.grey.shade800 : color,
          foregroundColor: textColor ?? Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textColor ?? Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Starting...',
                      style: TextStyle(
                          color: textColor ?? Colors.white, fontSize: 15)),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: textColor ?? Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DifficultyTile extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _DifficultyTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  Color get _color {
    switch (label) {
      case 'easy':
        return const Color(0xFF66BB6A);
      case 'medium':
        return const Color(0xFFFFE234);
      case 'hard':
        return const Color(0xFFFF6B35);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: selected
                ? _color.withValues(alpha: 0.6)
                : const Color(0xFF2A2A3A),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _color : Colors.white24,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  color: selected ? _color : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaddleTypeGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: PaddleType.values.map((t) => _PaddleChip(type: t)).toList(),
    );
  }
}

class _PaddleChip extends StatelessWidget {
  final PaddleType type;
  const _PaddleChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: type.primaryColor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(20),
        color: type.primaryColor.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          Text(type.displayName,
              style: TextStyle(
                  color: type.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11)),
          Text(type.powerDescription,
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}
