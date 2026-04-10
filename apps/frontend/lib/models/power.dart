import 'paddle_type.dart';

class ActivePower {
  final PaddleType type;
  final String side; // 'left' | 'right'
  final DateTime expiresAt;

  const ActivePower({
    required this.type,
    required this.side,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  double get remainingMs =>
      expiresAt.difference(DateTime.now()).inMilliseconds.toDouble().clamp(0, double.infinity);
}
