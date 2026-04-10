import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;
import '../../models/game_constants.dart';

class BallComponent extends CircleComponent {
  bool isVisible = true;

  // Local prediction velocity (used between server ticks)
  double vx = 0;
  double vy = 0;

  BallComponent()
      : super(
          radius: GameConstants.ballRadius,
          anchor: Anchor.center,
          paint: Paint()
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );

  @override
  void update(double dt) {
    super.update(dt);
    if (!isVisible) return;

    // Client-side prediction between server updates
    position.x += vx * dt;
    position.y += vy * dt;

    // Wall prediction (top/bottom)
    if (position.y - GameConstants.ballRadius <= 0) {
      position.y = GameConstants.ballRadius;
      vy = vy.abs();
    }
    if (position.y + GameConstants.ballRadius >= GameConstants.gameHeight) {
      position.y = GameConstants.gameHeight - GameConstants.ballRadius;
      vy = -vy.abs();
    }
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    // Outer glow
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      GameConstants.ballRadius * 2,
      Paint()
        ..color = Colors.white.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Ball body
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      GameConstants.ballRadius,
      Paint()..color = Colors.white,
    );
  }

  /// Called by game when server authoritative state arrives.
  void syncFromServer({
    required double x,
    required double y,
    required double serverVx,
    required double serverVy,
  }) {
    // Smoothly interpolate to server position
    const lerpFactor = 0.3;
    position.x = lerpDouble(position.x, x, lerpFactor)!;
    position.y = lerpDouble(position.y, y, lerpFactor)!;
    vx = serverVx;
    vy = serverVy;
  }
}
