// Shared game constants — mirrored in Flutter lib/models/game_constants.dart
'use strict';

const GAME = {
  // Canvas dimensions (logical pixels, landscape)
  WIDTH: 800,
  HEIGHT: 450,

  // Tick rate
  TICK_RATE_HZ: 60,
  TICK_MS: 1000 / 60,

  // Ball
  BALL_RADIUS: 10,
  BALL_INITIAL_SPEED: 320, // px/s

  // Paddles
  PADDLE_WIDTH: 14,
  PADDLE_HEIGHT: 90,
  PADDLE_MARGIN: 24,    // distance from edge
  PADDLE_SPEED: 480,   // px/s max (client hint only)

  // Scoring
  WIN_SCORE: 7,

  // Room
  ROOM_MAX_PLAYERS: 2,
  MATCHMAKING_TIMEOUT_MS: 30_000,

  // Power cooldown
  POWER_COOLDOWN_MS: 8_000,
  POWER_DURATION_MS: 3_000,
};

const PADDLE_TYPES = {
  PHOENIX: 'phoenix',   // +50% ball speed on hit
  FROST:   'frost',     // -40% ball speed on hit
  THUNDER: 'thunder',   // random angle on hit
  SHADOW:  'shadow',    // ball invisible 1s
  EARTH:   'earth',     // paddle +50% height 3s
};

const EVENTS = {
  // Client → Server
  JOIN_LOBBY:      'join_lobby',
  JOIN_VS_CPU:     'join_vs_cpu',   // debug: play against AI
  PADDLE_MOVE:     'paddle_move',
  USE_POWER:       'use_power',
  READY:           'ready',

  // Server → Client
  LOBBY_JOINED:    'lobby_joined',
  MATCH_FOUND:     'match_found',
  GAME_START:      'game_start',
  GAME_STATE:      'game_state',
  SCORE_UPDATE:    'score_update',
  POWER_ACTIVATED: 'power_activated',
  POWER_EXPIRED:   'power_expired',
  GAME_OVER:       'game_over',
  OPPONENT_LEFT:   'opponent_left',
  ERROR:           'error',
};

const AI_DIFFICULTIES = ['easy', 'medium', 'hard'];

module.exports = { GAME, PADDLE_TYPES, EVENTS, AI_DIFFICULTIES };
