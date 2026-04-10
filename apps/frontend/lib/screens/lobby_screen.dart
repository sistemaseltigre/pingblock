import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/paddle_type.dart';
import '../services/socket_service.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _socket = SocketService();
  final _nameController = TextEditingController(text: 'Player');
  String _status = 'Disconnected';
  bool _searching = false;
  // True once we push the GameScreen so dispose() doesn't kill the socket mid-game
  bool _navigatedToGame = false;

  // CPU mode state
  String _selectedDifficulty = 'medium';
  bool _showCpuOptions = false;

  static const _difficulties = ['easy', 'medium', 'hard'];
  static const _difficultyLabels = {
    'easy':   'Easy   — 40% reaction, imperfect aim',
    'medium': 'Medium — 70% reaction, occasional power use',
    'hard':   'Hard   — 95% reaction, ball prediction + powers',
  };

  @override
  void initState() {
    super.initState();
    _connectAndSetup();
  }

  void _connectAndSetup() {
    _socket.connect();
    setState(() => _status = 'Ready to play');

    _socket.onLobbyJoined((_) {
      setState(() => _status = 'Searching for opponent...');
    });

    _socket.onMatchFound(_handleMatchFound);

    _socket.onServerError((data) {
      setState(() {
        _status = 'Error: ${(data as Map)['message']}';
        _searching = false;
      });
    });
  }

  void _handleMatchFound(dynamic data) {
    final d = data as Map<String, dynamic>;
    setState(() {
      _status = 'Match found!';
      _searching = false;
    });

    final leftInfo  = d['left']  as Map<String, dynamic>;
    final rightInfo = d['right'] as Map<String, dynamic>;
    final isCpu     = d['vscpu'] as bool? ?? false;

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
          ),
        ),
      );
    });
  }

  void _findMatch() {
    final name = _nameController.text.trim().isEmpty ? 'Player' : _nameController.text.trim();
    setState(() => _searching = true);
    _socket.joinLobby(name);
  }

  void _playVsCpu() {
    final name = _nameController.text.trim().isEmpty ? 'Player' : _nameController.text.trim();
    setState(() => _searching = true);
    _socket.joinVsCpu(name, _selectedDifficulty);
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
                  style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2),
                ),

                const SizedBox(height: 36),

                // ── Paddle type preview ────────────────────────────────────
                _PaddleTypeGrid(),

                const SizedBox(height: 32),

                // ── Name input ─────────────────────────────────────────────
                TextField(
                  controller: _nameController,
                  maxLength: 16,
                  enabled: !_searching,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Your Name',
                    labelStyle: const TextStyle(color: Colors.white38),
                    counterStyle: const TextStyle(color: Colors.white24),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFF6B35)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF1A1A2A)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Multiplayer button ─────────────────────────────────────
                _PrimaryButton(
                  label: 'FIND MATCH',
                  icon: Icons.people,
                  color: const Color(0xFFFF6B35),
                  loading: _searching,
                  onPressed: _searching ? null : _findMatch,
                ),

                const SizedBox(height: 10),

                // ── VS CPU toggle + button ─────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: Column(
                    children: [
                      // Toggle CPU section
                      GestureDetector(
                        onTap: _searching ? null : () => setState(() => _showCpuOptions = !_showCpuOptions),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: _showCpuOptions
                                ? const Color(0xFF64D9FF).withValues(alpha: 0.08)
                                : Colors.transparent,
                            border: Border.all(
                              color: _showCpuOptions
                                  ? const Color(0xFF64D9FF).withValues(alpha: 0.4)
                                  : const Color(0xFF2A2A3A),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.smart_toy_outlined,
                                color: _showCpuOptions ? const Color(0xFF64D9FF) : Colors.white38,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Play vs CPU  (debug / local test)',
                                  style: TextStyle(
                                    color: _showCpuOptions ? const Color(0xFF64D9FF) : Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Icon(
                                _showCpuOptions ? Icons.expand_less : Icons.expand_more,
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
                          onTap: () => setState(() => _selectedDifficulty = d),
                        )),

                        const SizedBox(height: 12),

                        _PrimaryButton(
                          label: 'START VS CPU',
                          icon: Icons.smart_toy,
                          color: const Color(0xFF64D9FF),
                          loading: _searching,
                          onPressed: _searching ? null : _playVsCpu,
                          textColor: const Color(0xFF0A0A1A),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Status ─────────────────────────────────────────────────
                Text(
                  _status,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Text('Starting...', style: TextStyle(color: textColor ?? Colors.white, fontSize: 15)),
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
      case 'easy':   return const Color(0xFF66BB6A);
      case 'medium': return const Color(0xFFFFE234);
      case 'hard':   return const Color(0xFFFF6B35);
      default:       return Colors.white;
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
            color: selected ? _color.withValues(alpha: 0.6) : const Color(0xFF2A2A3A),
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
                  color: type.primaryColor, fontWeight: FontWeight.bold, fontSize: 11)),
          Text(type.powerDescription,
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}
