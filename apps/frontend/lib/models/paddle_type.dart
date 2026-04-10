import 'package:flutter/material.dart';

enum PaddleType {
  phoenix,
  frost,
  thunder,
  shadow,
  earth;

  String get displayName {
    switch (this) {
      case PaddleType.phoenix: return 'Phoenix';
      case PaddleType.frost:   return 'Frost';
      case PaddleType.thunder: return 'Thunder';
      case PaddleType.shadow:  return 'Shadow';
      case PaddleType.earth:   return 'Earth';
    }
  }

  String get powerDescription {
    switch (this) {
      case PaddleType.phoenix: return '+50% ball speed on hit';
      case PaddleType.frost:   return '-40% ball speed on hit';
      case PaddleType.thunder: return 'Random angle on hit';
      case PaddleType.shadow:  return 'Ball invisible 1s';
      case PaddleType.earth:   return 'Paddle +50% height 3s';
    }
  }

  Color get primaryColor {
    switch (this) {
      case PaddleType.phoenix: return const Color(0xFFFF6B35);
      case PaddleType.frost:   return const Color(0xFF64D9FF);
      case PaddleType.thunder: return const Color(0xFFFFE234);
      case PaddleType.shadow:  return const Color(0xFFAA44FF);
      case PaddleType.earth:   return const Color(0xFF66BB6A);
    }
  }

  Color get glowColor {
    switch (this) {
      case PaddleType.phoenix: return const Color(0xFFFF3D00);
      case PaddleType.frost:   return const Color(0xFF00B0FF);
      case PaddleType.thunder: return const Color(0xFFFFD600);
      case PaddleType.shadow:  return const Color(0xFF7B1FA2);
      case PaddleType.earth:   return const Color(0xFF2E7D32);
    }
  }

  static PaddleType fromString(String s) {
    return PaddleType.values.firstWhere(
      (t) => t.name == s,
      orElse: () => PaddleType.phoenix,
    );
  }
}
