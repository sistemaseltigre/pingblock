import 'package:socket_io_client/socket_io_client.dart' as io;

/// All Socket.IO events — mirrored from backend constants.js
class SocketEvents {
  // Client → Server
  static const joinLobby   = 'join_lobby';
  static const joinWagerLobby = 'join_wager_lobby';
  static const cancelWagerSearch = 'cancel_wager_search';
  static const paddleMove  = 'paddle_move';
  static const usePower    = 'use_power';

  // Server → Client
  static const lobbyJoined    = 'lobby_joined';
  static const wagerLobbyJoined = 'wager_lobby_joined';
  static const matchFound     = 'match_found';
  static const wagerMatchFound = 'wager_match_found';
  static const gameStart      = 'game_start';
  static const gameState      = 'game_state';
  static const scoreUpdate    = 'score_update';
  static const powerActivated = 'power_activated';
  static const powerExpired   = 'power_expired';
  static const gameOver       = 'game_over';
  static const opponentLeft   = 'opponent_left';
  static const wagerRefundPending = 'wager_refund_pending';
  static const wagerRefundDone = 'wager_refund_done';
  static const wagerSettlementPending = 'wager_settlement_pending';
  static const wagerSettlementDone = 'wager_settlement_done';
  static const wagerError = 'wager_error';
  static const error          = 'error';
}

typedef SocketCallback = void Function(dynamic data);

class SocketService {
  static const String _serverUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:3000');

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

  void joinWagerLobby({
    required String playerName,
    required int lamports,
    required String wallet,
    required String escrowTxSig,
    required String intentId,
  }) {
    _emit(SocketEvents.joinWagerLobby, {
      'name': playerName,
      'lamports': lamports,
      'wallet': wallet,
      'escrowTxSig': escrowTxSig,
      'intentId': intentId,
    });
  }

  void cancelWagerSearch() {
    _emit(SocketEvents.cancelWagerSearch, null);
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
  void onWagerLobbyJoined(SocketCallback cb) => _on(SocketEvents.wagerLobbyJoined, cb);
  void onMatchFound(SocketCallback cb)     => _on(SocketEvents.matchFound, cb);
  void onWagerMatchFound(SocketCallback cb) => _on(SocketEvents.wagerMatchFound, cb);
  void onGameStart(SocketCallback cb)      => _on(SocketEvents.gameStart, cb);
  void onGameState(SocketCallback cb)      => _on(SocketEvents.gameState, cb);
  void onScoreUpdate(SocketCallback cb)    => _on(SocketEvents.scoreUpdate, cb);
  void onPowerActivated(SocketCallback cb) => _on(SocketEvents.powerActivated, cb);
  void onPowerExpired(SocketCallback cb)   => _on(SocketEvents.powerExpired, cb);
  void onGameOver(SocketCallback cb)       => _on(SocketEvents.gameOver, cb);
  void onOpponentLeft(SocketCallback cb)   => _on(SocketEvents.opponentLeft, cb);
  void onWagerRefundPending(SocketCallback cb) => _on(SocketEvents.wagerRefundPending, cb);
  void onWagerRefundDone(SocketCallback cb) => _on(SocketEvents.wagerRefundDone, cb);
  void onWagerSettlementPending(SocketCallback cb) => _on(SocketEvents.wagerSettlementPending, cb);
  void onWagerSettlementDone(SocketCallback cb) => _on(SocketEvents.wagerSettlementDone, cb);
  void onWagerError(SocketCallback cb) => _on(SocketEvents.wagerError, cb);
  void onServerError(SocketCallback cb)    => _on(SocketEvents.error, cb);

  void off(String event) => _socket?.off(event);

  void removeAllListeners() {
    for (final e in [
      SocketEvents.lobbyJoined, SocketEvents.matchFound, SocketEvents.gameStart,
      SocketEvents.wagerLobbyJoined, SocketEvents.wagerMatchFound,
      SocketEvents.gameState,   SocketEvents.scoreUpdate, SocketEvents.powerActivated,
      SocketEvents.powerExpired, SocketEvents.gameOver,  SocketEvents.opponentLeft,
      SocketEvents.wagerRefundPending, SocketEvents.wagerRefundDone,
      SocketEvents.wagerSettlementPending, SocketEvents.wagerSettlementDone,
      SocketEvents.wagerError,
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

  void _log(String msg) {
    // ignore: avoid_print
    print('[SocketService] $msg');
  }
}
