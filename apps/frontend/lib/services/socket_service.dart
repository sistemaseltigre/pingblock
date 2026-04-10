import 'package:socket_io_client/socket_io_client.dart' as io;

/// All Socket.IO events — mirrored from backend constants.js
class SocketEvents {
  // Client → Server
  static const joinLobby   = 'join_lobby';
  static const paddleMove  = 'paddle_move';
  static const usePower    = 'use_power';

  // Server → Client
  static const lobbyJoined    = 'lobby_joined';
  static const matchFound     = 'match_found';
  static const gameStart      = 'game_start';
  static const gameState      = 'game_state';
  static const scoreUpdate    = 'score_update';
  static const powerActivated = 'power_activated';
  static const powerExpired   = 'power_expired';
  static const gameOver       = 'game_over';
  static const opponentLeft   = 'opponent_left';
  static const error          = 'error';
}

typedef SocketCallback = void Function(dynamic data);

class SocketService {
  static const String _serverUrl = 'http://localhost:3000';

  io.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  // ── Connection ────────────────────────────────────────────────────────────

  void connect() {
    _socket = io.io(
      _serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .build(),
    );

    _socket!.onConnect((_)    => _log('connected'));
    _socket!.onDisconnect((_) => _log('disconnected'));
    _socket!.onError((e)      => _log('error: $e'));

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  // ── Emitters ──────────────────────────────────────────────────────────────

  void joinLobby(String playerName) {
    _emit(SocketEvents.joinLobby, {'name': playerName});
  }

  /// Debug mode: play against a CPU opponent immediately.
  /// [difficulty] must be 'easy', 'medium', or 'hard'.
  void joinVsCpu(String playerName, String difficulty) {
    _emit('join_vs_cpu', {'name': playerName, 'difficulty': difficulty});
  }

  /// [y] is in game-space coordinates (0..GameConstants.gameHeight)
  void sendPaddleMove(double y) {
    _emit(SocketEvents.paddleMove, {'y': y});
  }

  void usePower() {
    _emit(SocketEvents.usePower, null);
  }

  // ── Listeners ─────────────────────────────────────────────────────────────

  void onLobbyJoined(SocketCallback cb)    => _on(SocketEvents.lobbyJoined, cb);
  void onMatchFound(SocketCallback cb)     => _on(SocketEvents.matchFound, cb);
  void onGameStart(SocketCallback cb)      => _on(SocketEvents.gameStart, cb);
  void onGameState(SocketCallback cb)      => _on(SocketEvents.gameState, cb);
  void onScoreUpdate(SocketCallback cb)    => _on(SocketEvents.scoreUpdate, cb);
  void onPowerActivated(SocketCallback cb) => _on(SocketEvents.powerActivated, cb);
  void onPowerExpired(SocketCallback cb)   => _on(SocketEvents.powerExpired, cb);
  void onGameOver(SocketCallback cb)       => _on(SocketEvents.gameOver, cb);
  void onOpponentLeft(SocketCallback cb)   => _on(SocketEvents.opponentLeft, cb);
  void onServerError(SocketCallback cb)    => _on(SocketEvents.error, cb);

  void off(String event) => _socket?.off(event);

  void removeAllListeners() {
    for (final e in [
      SocketEvents.lobbyJoined, SocketEvents.matchFound, SocketEvents.gameStart,
      SocketEvents.gameState,   SocketEvents.scoreUpdate, SocketEvents.powerActivated,
      SocketEvents.powerExpired, SocketEvents.gameOver,  SocketEvents.opponentLeft,
      SocketEvents.error,
    ]) {
      _socket?.off(e);
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _emit(String event, dynamic data) {
    if (!isConnected) {
      _log('tried to emit "$event" but not connected');
      return;
    }
    if (data == null) {
      _socket!.emit(event);
    } else {
      _socket!.emit(event, data);
    }
  }

  void _on(String event, SocketCallback cb) => _socket?.on(event, cb);

  void _log(String msg) => print('[SocketService] $msg');
}
