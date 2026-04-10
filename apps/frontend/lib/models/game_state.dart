import 'paddle_type.dart';

class BallState {
  final double x, y, vx, vy;
  const BallState({required this.x, required this.y, required this.vx, required this.vy});

  factory BallState.fromMap(Map<String, dynamic> m) => BallState(
        x:  (m['x']  as num).toDouble(),
        y:  (m['y']  as num).toDouble(),
        vx: (m['vx'] as num).toDouble(),
        vy: (m['vy'] as num).toDouble(),
      );
}

class PaddleState {
  final double y;
  final double height;
  const PaddleState({required this.y, required this.height});

  factory PaddleState.fromMap(Map<String, dynamic> m) => PaddleState(
        y:      (m['y']      as num).toDouble(),
        height: (m['height'] as num).toDouble(),
      );
}

class PlayerInfo {
  final String name;
  final PaddleType paddleType;
  int score;

  PlayerInfo({required this.name, required this.paddleType, this.score = 0});
}

class GameState {
  BallState? ball;
  PaddleState? leftPaddle;
  PaddleState? rightPaddle;
  PlayerInfo? leftPlayer;
  PlayerInfo? rightPlayer;
  String? roomId;
  String? mySide; // 'left' | 'right'

  bool ballVisible = true;
  bool powerCooldown = false;
  DateTime? powerAvailableAt;

  GameState();

  void applyGameStateEvent(Map<String, dynamic> data) {
    ball = BallState.fromMap(data['ball'] as Map<String, dynamic>);
    final paddles = data['paddles'] as Map<String, dynamic>;
    leftPaddle  = PaddleState.fromMap(paddles['left']  as Map<String, dynamic>);
    rightPaddle = PaddleState.fromMap(paddles['right'] as Map<String, dynamic>);
  }

  void applyScoreUpdate(Map<String, dynamic> data) {
    final scores = data['scores'] as Map<String, dynamic>;
    if (leftPlayer  != null) leftPlayer!.score  = (scores['left']  as num).toInt();
    if (rightPlayer != null) rightPlayer!.score = (scores['right'] as num).toInt();
  }
}
