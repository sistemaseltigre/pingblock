import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;
import '../../models/game_constants.dart';
import '../../models/paddle_type.dart';

class PaddleComponent extends PositionComponent {
  final PaddleType type;
  final bool isLocalPlayer;
  bool isPowerActive = false;

  double _targetY = 0;

  PaddleComponent({
    required this.type,
    required this.isLocalPlayer,
    required double x,
    required double initialY,
  }) : super(
          position: Vector2(x, initialY),
          size: Vector2(GameConstants.paddleWidth, GameConstants.paddleHeight),
          anchor: Anchor.topLeft,
        ) {
    _targetY = initialY;
  }

  // ── Server sync ──────────────────────────────────────────────────────────

  /// For the remote player's paddle — smooth lerp to server position.
  void syncFromServer(double y, double height) {
    _targetY = y;
    size.y = height;
  }

  /// For local player — immediate snap (since we already predicted it).
  void setLocalY(double y) {
    final clamped = y.clamp(0.0, GameConstants.gameHeight - size.y);
    position.y = clamped;
    _targetY = clamped;
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Lerp toward server position
    position.y = lerpDouble(position.y, _targetY, 0.25)!;
  }

  @override
  void render(Canvas canvas) {
    final paddleRect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = size.x / 2;

    // Glow when power is active
    if (isPowerActive) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          paddleRect.inflate(6),
          Radius.circular(radius + 3),
        ),
        Paint()
          ..color = type.glowColor.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Main paddle body — use dart:ui Gradient.linear directly
    canvas.drawRRect(
      RRect.fromRectAndRadius(paddleRect, Radius.circular(radius)),
      Paint()
        ..shader = Gradient.linear(
          Offset(paddleRect.left, paddleRect.top),
          Offset(paddleRect.left, paddleRect.bottom),
          [type.primaryColor, type.glowColor],
        )
        ..style = PaintingStyle.fill,
    );

    // Edge highlight
    canvas.drawRRect(
      RRect.fromRectAndRadius(paddleRect, Radius.circular(radius)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
