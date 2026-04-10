// Game room manager for PingBlock
'use strict';

const { v4: uuidv4 } = require('uuid');
const { GAME, PADDLE_TYPES, EVENTS, AI_DIFFICULTIES } = require('./constants');
const { stepBall, initialBall, initialPaddle } = require('./physics');
const { AiPlayer } = require('./aiPlayer');

const ALL_PADDLE_TYPES = Object.values(PADDLE_TYPES);

class GameManager {
  constructor(io) {
    this.io = io;
    /** @type {Map<string, Room>} roomId → Room */
    this.rooms = new Map();
    /** @type {string[]} socketIds waiting for a match */
    this.queue = [];
    /** @type {Map<string, string>} socketId → roomId */
    this.playerRoom = new Map();
  }

  // ── Matchmaking ─────────────────────────────────────────────────────────

  joinLobby(socket, playerName) {
    if (this.playerRoom.has(socket.id)) {
      socket.emit(EVENTS.ERROR, { message: 'Already in a game' });
      return;
    }
    if (this.queue.includes(socket.id)) {
      socket.emit(EVENTS.ERROR, { message: 'Already in queue' });
      return;
    }

    this.queue.push(socket.id);
    socket.data.playerName = playerName || `Player_${socket.id.slice(0, 4)}`;
    socket.emit(EVENTS.LOBBY_JOINED, { position: this.queue.length });

    if (this.queue.length >= 2) {
      const [idA, idB] = this.queue.splice(0, 2);
      this._createRoom(idA, idB);
    }
  }

  /**
   * Create an immediate room against a CPU opponent (debug/local mode).
   * @param {Socket} socket
   * @param {string} playerName
   * @param {string} difficulty 'easy' | 'medium' | 'hard'
   */
  joinVsCpu(socket, playerName, difficulty) {
    if (this.playerRoom.has(socket.id)) {
      socket.emit(EVENTS.ERROR, { message: 'Already in a game' });
      return;
    }

    const diff = AI_DIFFICULTIES.includes(difficulty) ? difficulty : 'medium';
    socket.data.playerName = playerName || `Player_${socket.id.slice(0, 4)}`;

    // Human is always on the right; AI is on the left
    const humanSide = 'right';
    const aiSide    = 'left';

    const humanPaddleType = randomPaddleType();
    const aiPaddleType    = randomPaddleType();
    const ai = new AiPlayer(aiSide, diff);

    const roomId = uuidv4();

    const room = {
      id: roomId,
      players: {
        left:  { id: ai.id,      name: ai.name,                    score: 0, paddleType: aiPaddleType,    powerCooldownUntil: 0 },
        right: { id: socket.id,  name: socket.data.playerName,     score: 0, paddleType: humanPaddleType, powerCooldownUntil: 0 },
      },
      ball:    initialBall(),
      paddles: {
        left:  initialPaddle('left'),
        right: initialPaddle('right'),
      },
      activePowers: { left: null, right: null },
      interval:  null,
      lastTick:  Date.now(),
      started:   false,
      // ── CPU fields ──────────────────────────────────────────────────────
      aiPlayer: ai,
      aiSide,
      isCpuGame: true,
    };

    this.rooms.set(roomId, room);
    this.playerRoom.set(socket.id, roomId);
    this.playerRoom.set(ai.id, roomId); // register AI id too (for usePower path)

    socket.join(roomId);

    const matchPayload = {
      roomId,
      vscpu:      true,
      difficulty: diff,
      left:  { name: ai.name,                    paddleType: aiPaddleType    },
      right: { name: socket.data.playerName,     paddleType: humanPaddleType },
    };

    socket.emit(EVENTS.MATCH_FOUND, matchPayload);

    setTimeout(() => this._startGame(roomId), 3000);
  }

  _createRoom(idA, idB) {
    const roomId = uuidv4();
    const sockA  = this.io.sockets.sockets.get(idA);
    const sockB  = this.io.sockets.sockets.get(idB);

    if (!sockA || !sockB) return;

    const paddleA = randomPaddleType();
    const paddleB = randomPaddleType();

    const room = {
      id: roomId,
      players: {
        left:  { id: idA, name: sockA.data.playerName, score: 0, paddleType: paddleA, powerCooldownUntil: 0 },
        right: { id: idB, name: sockB.data.playerName, score: 0, paddleType: paddleB, powerCooldownUntil: 0 },
      },
      ball:    initialBall(),
      paddles: {
        left:  initialPaddle('left'),
        right: initialPaddle('right'),
      },
      activePowers: { left: null, right: null },
      interval:  null,
      lastTick:  Date.now(),
      started:   false,
      aiPlayer:  null,
      aiSide:    null,
      isCpuGame: false,
    };

    this.rooms.set(roomId, room);
    this.playerRoom.set(idA, roomId);
    this.playerRoom.set(idB, roomId);

    sockA.join(roomId);
    sockB.join(roomId);

    const matchPayload = {
      roomId,
      vscpu: false,
      left:  { name: room.players.left.name,  paddleType: paddleA },
      right: { name: room.players.right.name, paddleType: paddleB },
    };

    this.io.to(roomId).emit(EVENTS.MATCH_FOUND, matchPayload);

    setTimeout(() => this._startGame(roomId), 3000);
  }

  // ── Game loop ────────────────────────────────────────────────────────────

  _startGame(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    room.started   = true;
    room.lastTick  = Date.now();
    this.io.to(roomId).emit(EVENTS.GAME_START, {});

    room.interval = setInterval(() => this._tick(roomId), GAME.TICK_MS);
  }

  _tick(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    const now = Date.now();
    const dt  = (now - room.lastTick) / 1000;
    room.lastTick = now;

    // ── AI move (CPU games) ────────────────────────────────────────────────
    if (room.aiPlayer) {
      const ai      = room.aiPlayer;
      const aiSide  = room.aiSide;
      const newY    = ai.computeMove(room.ball, room.paddles[aiSide]);
      room.paddles[aiSide].y = newY;

      // AI maybe uses power
      if (ai.shouldUsePower(now)) {
        this._activatePowerForSide(roomId, aiSide, now);
      }
    }

    // ── Power expiry ───────────────────────────────────────────────────────
    for (const side of ['left', 'right']) {
      const ap = room.activePowers[side];
      if (ap && now >= ap.expiresAt) {
        room.paddles[side].power = null;
        room.activePowers[side]  = null;
        this.io.to(roomId).emit(EVENTS.POWER_EXPIRED, { side });
        // Reset earth paddle height
        if (ap.type === 'earth') {
          room.paddles[side].height = GAME.PADDLE_HEIGHT;
        }
      } else if (ap) {
        room.paddles[side].power = ap.type;
      }
    }

    // ── Physics ────────────────────────────────────────────────────────────
    const { ball, scored } = stepBall(room.ball, room.paddles, dt);
    room.ball = ball;

    if (scored) {
      room.players[scored].score += 1;
      const scores = {
        left:  room.players.left.score,
        right: room.players.right.score,
      };
      this.io.to(roomId).emit(EVENTS.SCORE_UPDATE, { scored, scores });

      if (scores[scored] >= GAME.WIN_SCORE) {
        this._endGame(roomId, scored);
        return;
      }
    }

    // ── Broadcast ──────────────────────────────────────────────────────────
    this.io.to(roomId).emit(EVENTS.GAME_STATE, {
      ball:    room.ball,
      paddles: {
        left:  { y: room.paddles.left.y,  height: room.paddles.left.height },
        right: { y: room.paddles.right.y, height: room.paddles.right.height },
      },
    });
  }

  // ── Player actions ───────────────────────────────────────────────────────

  movePaddle(socketId, y) {
    const roomId = this.playerRoom.get(socketId);
    if (!roomId) return;
    const room = this.rooms.get(roomId);
    if (!room || !room.started) return;

    const side = this._humanSideOf(socketId, room);
    if (!side) return;

    room.paddles[side].y = Math.max(0, Math.min(GAME.HEIGHT - room.paddles[side].height, y));
  }

  usePower(socketId) {
    const roomId = this.playerRoom.get(socketId);
    if (!roomId) return;
    const room = this.rooms.get(roomId);
    if (!room || !room.started) return;

    const side = this._humanSideOf(socketId, room);
    if (!side) return;

    this._activatePowerForSide(roomId, side, Date.now());
  }

  /** Internal — activates power for a side (human or AI). */
  _activatePowerForSide(roomId, side, now) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    const player = room.players[side];
    if (now < player.powerCooldownUntil) return;
    if (room.activePowers[side]) return;

    player.powerCooldownUntil = now + GAME.POWER_COOLDOWN_MS;

    // Earth: grow paddle
    if (player.paddleType === 'earth') {
      room.paddles[side].height = GAME.PADDLE_HEIGHT * 1.5;
    }

    room.activePowers[side] = {
      type:      player.paddleType,
      expiresAt: now + GAME.POWER_DURATION_MS,
    };

    this.io.to(roomId).emit(EVENTS.POWER_ACTIVATED, {
      side,
      type:      player.paddleType,
      duration:  GAME.POWER_DURATION_MS,
    });
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  _endGame(roomId, winner) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    clearInterval(room.interval);

    this.io.to(roomId).emit(EVENTS.GAME_OVER, {
      winner,
      vscpu: room.isCpuGame,
      scores: {
        left:  room.players.left.score,
        right: room.players.right.score,
      },
    });

    this._cleanRoom(roomId);
  }

  playerDisconnected(socketId) {
    const qi = this.queue.indexOf(socketId);
    if (qi !== -1) this.queue.splice(qi, 1);

    const roomId = this.playerRoom.get(socketId);
    if (!roomId) return;

    const room = this.rooms.get(roomId);
    if (!room) return;

    clearInterval(room.interval);

    // In CPU games don't broadcast opponent_left (there's no opponent socket)
    if (!room.isCpuGame) {
      this.io.to(roomId).emit(EVENTS.OPPONENT_LEFT, {});
    }

    this._cleanRoom(roomId);
  }

  _cleanRoom(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;
    for (const p of ['left', 'right']) {
      this.playerRoom.delete(room.players[p].id);
    }
    this.rooms.delete(roomId);
  }

  /** Returns the side for human socket IDs only (skips AI id). */
  _humanSideOf(socketId, room) {
    if (room.players.right.id === socketId) return 'right';
    // In non-CPU games the left player is also human
    if (!room.isCpuGame && room.players.left.id === socketId) return 'left';
    return null;
  }

  _sideOf(socketId, room) {
    if (room.players.left.id  === socketId) return 'left';
    if (room.players.right.id === socketId) return 'right';
    return null;
  }

  // ── Inspect (for tests) ──────────────────────────────────────────────────
  getRoom(roomId)     { return this.rooms.get(roomId); }
  getRoomOf(socketId) { return this.rooms.get(this.playerRoom.get(socketId)); }
  getQueue()          { return [...this.queue]; }
}

function randomPaddleType() {
  return ALL_PADDLE_TYPES[Math.floor(Math.random() * ALL_PADDLE_TYPES.length)];
}

module.exports = { GameManager };
