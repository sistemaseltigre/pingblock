import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/paddle_type.dart';

class HudOverlay extends StatefulWidget {
  final GameState gameState;
  final VoidCallback onUsePower;
  final String mySide;

  const HudOverlay({
    super.key,
    required this.gameState,
    required this.onUsePower,
    required this.mySide,
  });

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  @override
  Widget build(BuildContext context) {
    final gs = widget.gameState;
    final leftScore  = gs.leftPlayer?.score  ?? 0;
    final rightScore = gs.rightPlayer?.score ?? 0;
    final myType = widget.mySide == 'left'
        ? gs.leftPlayer?.paddleType
        : gs.rightPlayer?.paddleType;
    final onCooldown = gs.powerCooldown;

    return Stack(
      children: [
        // Score top-center
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScoreText(leftScore),
              const SizedBox(width: 40),
              _ScoreText(rightScore),
            ],
          ),
        ),

        // Player labels
        Positioned(
          top: 8,
          left: 16,
          child: _PlayerLabel(gs.leftPlayer?.name ?? 'Left', gs.leftPlayer?.paddleType),
        ),
        Positioned(
          top: 8,
          right: 16,
          child: _PlayerLabel(gs.rightPlayer?.name ?? 'Right', gs.rightPlayer?.paddleType),
        ),

        // Power button — bottom center
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Center(
            child: _PowerButton(
              type: myType ?? PaddleType.phoenix,
              onCooldown: onCooldown,
              onPressed: widget.onUsePower,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreText extends StatelessWidget {
  final int score;
  const _ScoreText(this.score);

  @override
  Widget build(BuildContext context) => Text(
        '$score',
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: [Shadow(color: Colors.white54, blurRadius: 12)],
        ),
      );
}

class _PlayerLabel extends StatelessWidget {
  final String name;
  final PaddleType? type;
  const _PlayerLabel(this.name, this.type);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        if (type != null)
          Text(
            type!.displayName,
            style: TextStyle(color: type!.primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}

class _PowerButton extends StatelessWidget {
  final PaddleType type;
  final bool onCooldown;
  final VoidCallback onPressed;

  const _PowerButton({
    required this.type,
    required this.onCooldown,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCooldown ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: onCooldown ? Colors.grey.shade800 : type.primaryColor.withOpacity(0.2),
          border: Border.all(
            color: onCooldown ? Colors.grey.shade600 : type.primaryColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: onCooldown
              ? []
              : [
                  BoxShadow(
                    color: type.glowColor.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flash_on,
              color: onCooldown ? Colors.grey : type.primaryColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              onCooldown ? 'Cooldown...' : '${type.displayName} Power',
              style: TextStyle(
                color: onCooldown ? Colors.grey : type.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
