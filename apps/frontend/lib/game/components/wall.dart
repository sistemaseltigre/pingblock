import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors, Paint, PaintingStyle;
import 'dart:ui';
import '../../models/game_constants.dart';

/// Visual center divider line — no physics (server handles boundaries).
class CourtComponent extends PositionComponent {
  CourtComponent()
      : super(
          position: Vector2.zero(),
          size: Vector2(GameConstants.gameWidth, GameConstants.gameHeight),
        );

  @override
  void render(Canvas canvas) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, GameConstants.gameWidth, GameConstants.gameHeight),
      Paint()..color = const Color(0xFF0A0A1A),
    );

    // Center line — dashed
    final dashHeight = 20.0;
    final gap = 12.0;
    final cx = GameConstants.gameWidth / 2;
    double y = 0;
    final dashPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 2;

    while (y < GameConstants.gameHeight) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dashHeight), dashPaint);
      y += dashHeight + gap;
    }

    // Top & bottom border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(1, 1, GameConstants.gameWidth - 2, GameConstants.gameHeight - 2),
      borderPaint,
    );
  }
}
