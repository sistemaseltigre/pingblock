import 'package:flame/components.dart' show Anchor;
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../models/game_constants.dart';
import '../models/game_state.dart';
import '../models/paddle_type.dart';
import '../services/socket_service.dart';
import 'components/ball.dart';
import 'components/paddle.dart';
import 'components/wall.dart';

class PingPongGame extends FlameGame with DragCallbacks {
  final GameState gameState;
  final SocketService socketService;
  final String mySide; // 'left' | 'right'
  /// Called whenever power cooldown state changes so the Flutter HUD rebuilds.
  final VoidCallback onStateChanged;

  late PaddleComponent myPaddle;
  late PaddleComponent opponentPaddle;
  late BallComponent ball;

  // Track the active drag for paddle control
  int? _activeDragId;
  // Accumulate drag position from start + deltas
  Vector2 _dragPosition = Vector2.zero();

  PingPongGame({
    required this.gameState,
    required this.socketService,
    required this.mySide,
    required this.onStateChanged,
  });

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Color backgroundColor() => const Color(0xFF0A0A1A);

  // ── Camera: called on every resize (orientation change, first load) ───────

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // "Contain" mode: fit entire 800×450 world into any canvas size.
    // Zoom = min(canvasW/gameW, canvasH/gameH) so nothing is ever cropped.
    const gw = GameConstants.gameWidth;
    const gh = GameConstants.gameHeight;
    final zoom = (size.x / gw) < (size.y / gh)
        ? size.x / gw
        : size.y / gh;
    camera.viewfinder.zoom     = zoom;
    camera.viewfinder.anchor   = Anchor.center;
    camera.viewfinder.position = Vector2(gw / 2, gh / 2);
  }

  @override
  Future<void> onLoad() async {

    final myType   = _myPaddleType();
    final oppType  = _opponentPaddleType();
    final myX      = mySide == 'left'
        ? GameConstants.paddleMargin
        : GameConstants.gameWidth - GameConstants.paddleMargin - GameConstants.paddleWidth;
    final oppX     = mySide == 'left'
        ? GameConstants.gameWidth - GameConstants.paddleMargin - GameConstants.paddleWidth
        : GameConstants.paddleMargin;
    final midY = GameConstants.gameHeight / 2 - GameConstants.paddleHeight / 2;

    await world.add(CourtComponent());

    myPaddle = PaddleComponent(
      type: myType,
      isLocalPlayer: true,
      x: myX,
      initialY: midY,
    );
    opponentPaddle = PaddleComponent(
      type: oppType,
      isLocalPlayer: false,
      x: oppX,
      initialY: midY,
    );
    ball = BallComponent()
      ..position = Vector2(
        GameConstants.gameWidth / 2,
        GameConstants.gameHeight / 2,
      );

    await world.add(myPaddle);
    await world.add(opponentPaddle);
    await world.add(ball);

    _setupSocketListeners();
  }

  @override
  void onRemove() {
    socketService.removeAllListeners();
    super.onRemove();
  }

  // ── Server state sync ─────────────────────────────────────────────────────

  void _setupSocketListeners() {
    socketService.onGameState((data) {
      final d = data as Map<String, dynamic>;
      gameState.applyGameStateEvent(d);

      final ballData = d['ball'] as Map<String, dynamic>;
      ball.syncFromServer(
        x:        (ballData['x']  as num).toDouble(),
        y:        (ballData['y']  as num).toDouble(),
        serverVx: (ballData['vx'] as num).toDouble(),
        serverVy: (ballData['vy'] as num).toDouble(),
      );

      final paddles = d['paddles'] as Map<String, dynamic>;
      final oppKey = mySide == 'left' ? 'right' : 'left';
      final oppData = paddles[oppKey] as Map<String, dynamic>;
      opponentPaddle.syncFromServer(
        (oppData['y']      as num).toDouble(),
        (oppData['height'] as num).toDouble(),
      );
    });

    socketService.onPowerActivated((data) {
      final d = data as Map<String, dynamic>;
      final side = d['side'] as String;
      if (side == mySide) {
        myPaddle.isPowerActive = true;
        gameState.powerCooldown = true;
        onStateChanged(); // tell Flutter HUD to rebuild
      } else {
        opponentPaddle.isPowerActive = true;
      }
      if (d['type'] == 'shadow') ball.isVisible = false;
    });

    socketService.onPowerExpired((data) {
      final d = data as Map<String, dynamic>;
      final side = d['side'] as String;
      if (side == mySide) {
        myPaddle.isPowerActive = false;
        gameState.powerCooldown = false;
        onStateChanged(); // tell Flutter HUD to rebuild
      } else {
        opponentPaddle.isPowerActive = false;
      }
      ball.isVisible = true;
    });
  }

  // ── Touch input ───────────────────────────────────────────────────────────

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _activeDragId = event.pointerId;
    _dragPosition = event.canvasPosition.clone();
    _movePaddleTo(_dragPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (event.pointerId == _activeDragId) {
      _dragPosition.add(event.localDelta);
      _movePaddleTo(_dragPosition);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId == _activeDragId) _activeDragId = null;
  }

  void _movePaddleTo(Vector2 canvasPos) {
    // Convert canvas (screen) pixels → game world coordinates using the camera.
    // Formula: worldPos = cameraCenter + (canvasPos - canvasCenter) / zoom
    final worldPos = camera.viewfinder.position +
        (canvasPos - size / 2) / camera.viewfinder.zoom;

    final gameY    = worldPos.y - GameConstants.paddleHeight / 2;
    final clampedY = gameY.clamp(0.0, GameConstants.gameHeight - GameConstants.paddleHeight);

    myPaddle.setLocalY(clampedY);
    socketService.sendPaddleMove(clampedY);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  PaddleType _myPaddleType() {
    if (mySide == 'left') return gameState.leftPlayer?.paddleType  ?? PaddleType.phoenix;
    return gameState.rightPlayer?.paddleType ?? PaddleType.frost;
  }

  PaddleType _opponentPaddleType() {
    if (mySide == 'left') return gameState.rightPlayer?.paddleType ?? PaddleType.frost;
    return gameState.leftPlayer?.paddleType  ?? PaddleType.phoenix;
  }
}
