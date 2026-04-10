import 'dart:async';
import 'dart:math' show min;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_constants.dart';
import '../models/game_state.dart';
import '../services/socket_service.dart';
import '../game/ping_pong_game.dart';
import '../game/overlays/hud_overlay.dart';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  final GameState gameState;
  final SocketService socketService;
  final String mySide;

  const GameScreen({
    super.key,
    required this.gameState,
    required this.socketService,
    required this.mySide,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late PingPongGame _game;

  // 3-2-1-GO countdown (purely visual)
  int _countdown = 3;
  bool _countdownDone = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();

    // Allow both landscape and portrait — detect phone orientation automatically.
    // No forced lock; the camera adapts via onGameResize.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // PingPongGame calls onStateChanged() when power cooldown toggles,
    // which triggers setState here so the HUD button updates.
    _game = PingPongGame(
      gameState:      widget.gameState,
      socketService:  widget.socketService,
      mySide:         widget.mySide,
      onStateChanged: () { if (mounted) setState(() {}); },
    );

    _setupSocketListeners();
    _startCountdown();
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _countdownDone = true;
          t.cancel();
        }
      });
    });
  }

  // ── Socket listeners ──────────────────────────────────────────────────────

  void _setupSocketListeners() {
    widget.socketService.onScoreUpdate((data) {
      if (mounted) setState(() => widget.gameState.applyScoreUpdate(data as Map<String, dynamic>));
    });

    widget.socketService.onGameOver((data) {
      final d = data as Map<String, dynamic>;
      if (mounted) _showGameOver(d);
    });

    widget.socketService.onOpponentLeft((_) {
      if (mounted) _showOpponentLeft();
    });
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showGameOver(Map<String, dynamic> data) {
    final winner = data['winner'] as String;
    final scores = data['scores'] as Map<String, dynamic>;
    final iWon   = winner == widget.mySide;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111128),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          iWon ? '🏆 You Win!' : '💔 You Lose',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: iWon ? const Color(0xFFFF6B35) : Colors.white54,
            fontSize: 24,
          ),
        ),
        content: Text(
          '${scores['left']} — ${scores['right']}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.socketService.disconnect();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
                (_) => false,
              );
            },
            child: const Text('BACK TO LOBBY', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }

  void _showOpponentLeft() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111128),
        title: const Text('Opponent disconnected', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () {
              widget.socketService.disconnect();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
                (_) => false,
              );
            },
            child: const Text('BACK TO LOBBY', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    // Restore all orientations when leaving the game
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate the largest 800:450 box that fits within the screen.
          // This ensures BOTH paddles are always visible regardless of orientation.
          final screenW    = constraints.maxWidth;
          final screenH    = constraints.maxHeight;

          final scale    = min(screenW / GameConstants.gameWidth,
                               screenH / GameConstants.gameHeight);
          final canvasW  = GameConstants.gameWidth  * scale;
          final canvasH  = GameConstants.gameHeight * scale;
          final padLeft  = (screenW - canvasW) / 2;
          final padTop   = (screenH - canvasH) / 2;

          return Stack(
            children: [
              // ── Full-screen dark background (fills letterbox/pillarbox bars) ─
              const ColoredBox(
                color: Color(0xFF0A0A1A),
                child: SizedBox.expand(),
              ),

              // ── Game canvas — always centered, correct aspect ratio ─────────
              Positioned(
                left:   padLeft,
                top:    padTop,
                width:  canvasW,
                height: canvasH,
                child: GameWidget(
                  game: _game,
                  backgroundBuilder: (_) =>
                      const ColoredBox(color: Color(0xFF0A0A1A)),
                  loadingBuilder: (_) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
                  ),
                ),
              ),

              // ── HUD — positioned inside the game canvas area ───────────────
              Positioned(
                left:   padLeft,
                top:    padTop,
                width:  canvasW,
                height: canvasH,
                child: HudOverlay(
                  gameState: widget.gameState,
                  mySide:    widget.mySide,
                  onUsePower: () => widget.socketService.usePower(),
                ),
              ),

              // ── Countdown overlay — also inside canvas area ────────────────
              if (!_countdownDone)
                Positioned(
                  left:   padLeft,
                  top:    padTop,
                  width:  canvasW,
                  height: canvasH,
                  child: _CountdownOverlay(count: _countdown),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Countdown widget ──────────────────────────────────────────────────────────

class _CountdownOverlay extends StatefulWidget {
  final int count;
  const _CountdownOverlay({required this.count});

  @override
  State<_CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<_CountdownOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
  }

  @override
  void didUpdateWidget(_CountdownOverlay old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count > 0 ? '${widget.count}' : 'GO!';
    final color = widget.count > 0
        ? const Color(0xFF64D9FF)
        : const Color(0xFFFF6B35);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        // Subtle border to show the game canvas boundary during countdown
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w900,
              color: color,
              shadows: [Shadow(color: color.withValues(alpha: 0.5), blurRadius: 40)],
            ),
          ),
        ),
      ),
    );
  }
}
