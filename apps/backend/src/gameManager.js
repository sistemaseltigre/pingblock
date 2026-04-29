// Game room manager for PingBlock
'use strict';

const { v4: uuidv4 } = require('uuid');
const { GAME, WAGER, PADDLE_TYPES, EVENTS, AI_DIFFICULTIES } = require('./constants');
const { stepBall, initialBall, initialPaddle } = require('./physics');
const { AiPlayer } = require('./aiPlayer');
const { isValidWagerAmountLamports } = require('./wagerRules');
const { WagerCustodyService } = require('./wagerCustodyService');

const ALL_PADDLE_TYPES = Object.values(PADDLE_TYPES);

class GameManager {
  constructor(io, opts = {}) {
    this.io = io;
    /** @type {Map<string, Room>} roomId → Room */
    this.rooms = new Map();
    /** @type {string[]} socketIds waiting for a match */
    this.queue = [];
    /** @type {Map<string, string>} socketId → roomId */
    this.playerRoom = new Map();
    /** @type {Map<number, string[]>} lamports bucket -> socketId[] */
    this.wagerQueues = new Map();
    /** @type {Map<string, {wallet,lamports,escrowTxSig,intentId,wagerEscrowPda,joinedAt}>} */
    this.wagerEntries = new Map();
    /** @type {Map<string, number>} socketId -> lamports bucket */
    this.socketWagerBucket = new Map();
    /**
     * @type {Map<string, {
     *   wagerId, lamportsEach, potLamports, settled,
     *   matchEscrowPda, wagerEscrowPdaA, wagerEscrowPdaB,
     *   playerAWallet, playerBWallet, matchWagersSig
     * }>}
     */
    this.roomWagers = new Map();
    this.wagerCustody = opts.wagerCustody || new WagerCustodyService();
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

  async joinWagerLobby(socket, { playerName, wallet, lamports, escrowTxSig, intentId }) {
    if (this.playerRoom.has(socket.id)) {
      socket.emit(EVENTS.WAGER_ERROR, { code: 'ALREADY_IN_GAME', message: 'Already in a game' });
      return;
    }
    if (this.queue.includes(socket.id) || this.socketWagerBucket.has(socket.id)) {
      socket.emit(EVENTS.WAGER_ERROR, { code: 'ALREADY_IN_QUEUE', message: 'Already in queue' });
      return;
    }
    if (!wallet || typeof wallet !== 'string') {
      socket.emit(EVENTS.WAGER_ERROR, { code: 'INVALID_WALLET', message: 'Wallet is required' });
      return;
    }
    if (!isValidWagerAmountLamports(lamports, WAGER.MIN_LAMPORTS, WAGER.MAX_LAMPORTS)) {
      socket.emit(EVENTS.WAGER_ERROR, {
        code: 'INVALID_WAGER_AMOUNT',
        message: `Wager must be between ${WAGER.MIN_LAMPORTS} and ${WAGER.MAX_LAMPORTS} lamports`,
      });
      return;
    }
    if (intentId == null || `${intentId}`.trim() === '') {
      socket.emit(EVENTS.WAGER_ERROR, {
        code: 'INVALID_INTENT_ID',
        message: 'intentId is required for escrow verification',
      });
      return;
    }

    const verified = await this.wagerCustody.verifyEscrow({ wallet, lamports, escrowTxSig, intentId });
    if (!verified) {
      socket.emit(EVENTS.WAGER_ERROR, {
        code: 'WAGER_ESCROW_NOT_VERIFIED',
        message: 'Escrow transaction could not be verified for this wallet/amount.',
      });
      return;
    }

    // Derive the wager_escrow PDA so we can use it later for match_wagers.
    const wagerEscrowPda = this.wagerCustody.mode === 'onchain'
      ? this.wagerCustody.solana.deriveWagerEscrowPda(wallet, intentId)
      : `mock_escrow_${wallet}_${intentId}`;

    socket.data.playerName = playerName || `Player_${socket.id.slice(0, 4)}`;
    socket.data.wallet = wallet;

    if (!this.wagerQueues.has(lamports)) this.wagerQueues.set(lamports, []);
    const bucket = this.wagerQueues.get(lamports);
    bucket.push(socket.id);

    this.wagerEntries.set(socket.id, {
      wallet,
      lamports,
      escrowTxSig,
      intentId,
      wagerEscrowPda,
      joinedAt: Date.now(),
    });
    this.socketWagerBucket.set(socket.id, lamports);

    socket.emit(EVENTS.WAGER_LOBBY_JOINED, { position: bucket.length, lamports });

    if (bucket.length >= 2) {
      const [idA, idB] = bucket.splice(0, 2);
      await this._createWagerRoom(idA, idB, lamports);
    }
  }

  async cancelWagerSearch(socket) {
    const bucketLamports = this.socketWagerBucket.get(socket.id);
    const entry = this.wagerEntries.get(socket.id);
    if (!entry || bucketLamports == null) {
      socket.emit(EVENTS.WAGER_ERROR, { code: 'NOT_IN_WAGER_QUEUE', message: 'Not in wager queue' });
      return;
    }

    const bucket = this.wagerQueues.get(bucketLamports);
    if (bucket) {
      const i = bucket.indexOf(socket.id);
      if (i !== -1) bucket.splice(i, 1);
    }

    this.socketWagerBucket.delete(socket.id);
    this.wagerEntries.delete(socket.id);

    socket.emit(EVENTS.WAGER_REFUND_PENDING, {});
    const refund = await this.wagerCustody.refundSearchCancel(entry);
    socket.emit(EVENTS.WAGER_REFUND_DONE, {
      refundTxSig: refund.refundTxSig,
      lamports: entry.lamports,
    });
  }

  /**
   * Join a CPU game, optionally with a wager.
   *
   * When wager params are provided:
   *   1. Verify the player's escrow on-chain.
   *   2. Create a matching "house" escrow (backend signs).
   *   3. Call match_wagers on-chain to link both escrows.
   *   4. Start the game; settle on completion.
   *
   * @param {Socket} socket
   * @param {string} playerName
   * @param {string} difficulty  'easy' | 'medium' | 'hard'
   * @param {object} [wager]     Optional wager params
   * @param {string}  wager.wallet
   * @param {number}  wager.lamports
   * @param {string}  wager.escrowTxSig
   * @param {string}  wager.intentId
   * @param {string}  [wager.wagerEscrowPda]
   */
  async joinVsCpu(socket, playerName, difficulty, wager = null) {
    if (this.playerRoom.has(socket.id)) {
      socket.emit(EVENTS.ERROR, { message: 'Already in a game' });
      return;
    }

    const diff = AI_DIFFICULTIES.includes(difficulty) ? difficulty : 'medium';
    socket.data.playerName = playerName || `Player_${socket.id.slice(0, 4)}`;

    const isWagerGame = !!(wager && wager.wallet && wager.lamports && wager.escrowTxSig && wager.intentId);
    let wagerRoomData = null;

    if (isWagerGame) {
      // Validate wager amount
      if (!isValidWagerAmountLamports(wager.lamports, WAGER.MIN_LAMPORTS, WAGER.MAX_LAMPORTS)) {
        socket.emit(EVENTS.WAGER_ERROR, {
          code: 'INVALID_WAGER_AMOUNT',
          message: `Wager must be between ${WAGER.MIN_LAMPORTS} and ${WAGER.MAX_LAMPORTS} lamports`,
        });
        return;
      }

      // Verify the player's escrow
      socket.emit(EVENTS.WAGER_LOBBY_JOINED, { position: 1, lamports: wager.lamports });
      const verified = await this.wagerCustody.verifyEscrow({
        wallet: wager.wallet,
        lamports: wager.lamports,
        escrowTxSig: wager.escrowTxSig,
        intentId: wager.intentId,
      });
      if (!verified) {
        socket.emit(EVENTS.WAGER_ERROR, {
          code: 'WAGER_ESCROW_NOT_VERIFIED',
          message: 'Escrow transaction could not be verified for this wallet/amount.',
        });
        return;
      }

      // Derive player's wager escrow PDA
      const playerEscrowPda = wager.wagerEscrowPda ||
        (this.wagerCustody.mode === 'onchain'
          ? this.wagerCustody.solana.deriveWagerEscrowPda(wager.wallet, wager.intentId)
          : `mock_escrow_${wager.wallet}_${wager.intentId}`);

      console.log(`[GameManager] CPU wager: creating house escrow for ${wager.lamports} lamports...`);

      // Create house escrow (backend's matching stake)
      const house = await this.wagerCustody.initHouseEscrow({ lamports: wager.lamports });
      console.log(`[GameManager] CPU wager: house escrow=${house.houseEscrowPda} sig=${house.houseEscrowSig}`);

      // Call match_wagers: player = escrow A, house = escrow B
      const wagerId = uuidv4();
      console.log(`[GameManager] CPU wager: calling match_wagers wagerId=${wagerId}`);
      const { matchWagersSig, matchEscrowPda } = await this.wagerCustody.matchWagersOnChain({
        wagerId,
        wagerEscrowPdaA: playerEscrowPda,
        wagerEscrowPdaB: house.houseEscrowPda,
      });
      console.log(`[GameManager] CPU wager: match_wagers ok sig=${matchWagersSig} matchEscrow=${matchEscrowPda}`);

      wagerRoomData = {
        wagerId,
        lamportsEach:    wager.lamports,
        potLamports:     wager.lamports * 2,
        settled:         false,
        matchEscrowPda,
        wagerEscrowPdaA: playerEscrowPda,   // player is A
        wagerEscrowPdaB: house.houseEscrowPda, // house is B
        playerAWallet:   wager.wallet,
        playerBWallet:   house.houseWallet,
        matchWagersSig,
      };
    }

    // ── Build room ───────────────────────────────────────────────────────────

    const humanSide = 'right';
    const aiSide    = 'left';

    const humanPaddleType = randomPaddleType();
    const aiPaddleType    = randomPaddleType();
    const ai = new AiPlayer(aiSide, diff);

    const roomId = uuidv4();

    const room = {
      id: roomId,
      players: {
        left:  {
          id:                 ai.id,
          name:               ai.name,
          score:              0,
          paddleType:         aiPaddleType,
          powerCooldownUntil: 0,
          // House wallet for wager settlement (null for free games)
          wallet: isWagerGame ? wagerRoomData.playerBWallet : null,
        },
        right: {
          id:                 socket.id,
          name:               socket.data.playerName,
          score:              0,
          paddleType:         humanPaddleType,
          powerCooldownUntil: 0,
          wallet: isWagerGame ? wager.wallet : null,
        },
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
      aiPlayer:  ai,
      aiSide,
      isCpuGame:   true,
      isWagerGame: isWagerGame,
    };

    this.rooms.set(roomId, room);
    this.playerRoom.set(socket.id, roomId);
    this.playerRoom.set(ai.id, roomId);

    if (isWagerGame) {
      this.roomWagers.set(roomId, wagerRoomData);
    }

    socket.join(roomId);

    const matchPayload = {
      roomId,
      vscpu:      true,
      difficulty: diff,
      left:  { name: ai.name,                paddleType: aiPaddleType    },
      right: { name: socket.data.playerName, paddleType: humanPaddleType },
    };

    socket.emit(EVENTS.MATCH_FOUND, matchPayload);

    if (isWagerGame) {
      socket.emit(EVENTS.WAGER_MATCH_FOUND, {
        wagerId:      wagerRoomData.wagerId,
        roomId,
        lamportsEach: wager.lamports,
        potLamports:  wager.lamports * 2,
      });
    }

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

  async _createWagerRoom(idA, idB, lamportsEach) {
    const roomId = uuidv4();
    const wagerId = uuidv4();
    const sockA = this.io.sockets.sockets.get(idA);
    const sockB = this.io.sockets.sockets.get(idB);
    const entryA = this.wagerEntries.get(idA);
    const entryB = this.wagerEntries.get(idB);

    if (!sockA || !sockB || !entryA || !entryB) return;

    const paddleA = randomPaddleType();
    const paddleB = randomPaddleType();

    const room = {
      id: roomId,
      players: {
        left: {
          id: idA,
          name: sockA.data.playerName,
          score: 0,
          paddleType: paddleA,
          powerCooldownUntil: 0,
          wallet: entryA.wallet,
        },
        right: {
          id: idB,
          name: sockB.data.playerName,
          score: 0,
          paddleType: paddleB,
          powerCooldownUntil: 0,
          wallet: entryB.wallet,
        },
      },
      ball: initialBall(),
      paddles: {
        left: initialPaddle('left'),
        right: initialPaddle('right'),
      },
      activePowers: { left: null, right: null },
      interval: null,
      lastTick: Date.now(),
      started: false,
      aiPlayer: null,
      aiSide: null,
      isCpuGame: false,
      isWagerGame: true,
    };

    this.rooms.set(roomId, room);
    this.playerRoom.set(idA, roomId);
    this.playerRoom.set(idB, roomId);

    this.socketWagerBucket.delete(idA);
    this.socketWagerBucket.delete(idB);
    this.wagerEntries.delete(idA);
    this.wagerEntries.delete(idB);

    sockA.join(roomId);
    sockB.join(roomId);

    const matchPayload = {
      roomId,
      vscpu: false,
      left:  { name: room.players.left.name,  paddleType: paddleA },
      right: { name: room.players.right.name, paddleType: paddleB },
    };

    this.io.to(roomId).emit(EVENTS.MATCH_FOUND, matchPayload);
    this.io.to(roomId).emit(EVENTS.WAGER_MATCH_FOUND, {
      wagerId,
      roomId,
      left:  { name: room.players.left.name,  paddleType: paddleA, wallet: entryA.wallet },
      right: { name: room.players.right.name, paddleType: paddleB, wallet: entryB.wallet },
      lamportsEach,
      potLamports: lamportsEach * 2,
    });

    // Call match_wagers on-chain asynchronously (game starts in 3s regardless).
    // If it fails the room will have no matchEscrowPda and settlement will emit WAGER_ERROR.
    let matchEscrowPda = null;
    let matchWagersSig = null;

    try {
      console.log(`[GameManager] PvP wager: calling match_wagers wagerId=${wagerId}`);
      const result = await this.wagerCustody.matchWagersOnChain({
        wagerId,
        wagerEscrowPdaA: entryA.wagerEscrowPda,
        wagerEscrowPdaB: entryB.wagerEscrowPda,
      });
      matchEscrowPda = result.matchEscrowPda;
      matchWagersSig = result.matchWagersSig;
      console.log(`[GameManager] PvP wager: match_wagers ok sig=${matchWagersSig} matchEscrow=${matchEscrowPda}`);
    } catch (e) {
      console.error(`[GameManager] PvP wager: match_wagers FAILED: ${e.message || e}`);
      this.io.to(roomId).emit(EVENTS.WAGER_ERROR, {
        code: 'MATCH_WAGERS_FAILED',
        message: `Failed to link escrows on-chain: ${e.message || e}`,
      });
    }

    this.roomWagers.set(roomId, {
      wagerId,
      lamportsEach,
      potLamports: lamportsEach * 2,
      settled: false,
      matchEscrowPda,
      wagerEscrowPdaA: entryA.wagerEscrowPda,
      wagerEscrowPdaB: entryB.wagerEscrowPda,
      playerAWallet:   entryA.wallet,
      playerBWallet:   entryB.wallet,
      matchWagersSig,
    });

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

    if (room.aiPlayer) {
      const ai     = room.aiPlayer;
      const aiSide = room.aiSide;
      const newY   = ai.computeMove(room.ball, room.paddles[aiSide]);
      room.paddles[aiSide].y = newY;

      if (ai.shouldUsePower(now)) {
        this._activatePowerForSide(roomId, aiSide, now);
      }
    }

    for (const side of ['left', 'right']) {
      const ap = room.activePowers[side];
      if (ap && now >= ap.expiresAt) {
        room.paddles[side].power = null;
        room.activePowers[side]  = null;
        this.io.to(roomId).emit(EVENTS.POWER_EXPIRED, { side });
        if (ap.type === 'earth') {
          room.paddles[side].height = GAME.PADDLE_HEIGHT;
        }
      } else if (ap) {
        room.paddles[side].power = ap.type;
      }
    }

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

  _activatePowerForSide(roomId, side, now) {
    const room = this.rooms.get(roomId);
    if (!room) return;

    const player = room.players[side];
    if (now < player.powerCooldownUntil) return;
    if (room.activePowers[side]) return;

    player.powerCooldownUntil = now + GAME.POWER_COOLDOWN_MS;

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

    if (!room.isWagerGame) {
      this._cleanRoom(roomId);
      return;
    }

    this._settleWagerRoom(roomId, winner)
      .catch((e) => {
        this.io.to(roomId).emit(EVENTS.WAGER_ERROR, {
          code: 'SETTLEMENT_FAILED',
          message: `Settlement failed: ${e.message || e}`,
        });
      })
      .finally(() => this._cleanRoom(roomId));
  }

  playerDisconnected(socketId) {
    const qi = this.queue.indexOf(socketId);
    if (qi !== -1) this.queue.splice(qi, 1);

    const wagerBucket = this.socketWagerBucket.get(socketId);
    const wagerEntry  = this.wagerEntries.get(socketId);
    if (wagerBucket != null && wagerEntry) {
      const bucket = this.wagerQueues.get(wagerBucket);
      if (bucket) {
        const i = bucket.indexOf(socketId);
        if (i !== -1) bucket.splice(i, 1);
      }
      this.socketWagerBucket.delete(socketId);
      this.wagerEntries.delete(socketId);
      this.wagerCustody.refundSearchCancel(wagerEntry).catch(() => {});
    }

    const roomId = this.playerRoom.get(socketId);
    if (!roomId) return;

    const room = this.rooms.get(roomId);
    if (!room) return;

    clearInterval(room.interval);

    if (!room.isCpuGame) {
      this.io.to(roomId).emit(EVENTS.OPPONENT_LEFT, {});
    }

    if (!room.isWagerGame) {
      this._cleanRoom(roomId);
      return;
    }

    const quitterSide = this._sideOf(socketId, room);
    if (!quitterSide) {
      this._cleanRoom(roomId);
      return;
    }
    const winnerSide = quitterSide === 'left' ? 'right' : 'left';
    this._settleWagerRoom(roomId, winnerSide)
      .catch(() => {})
      .finally(() => this._cleanRoom(roomId));
  }

  _cleanRoom(roomId) {
    const room = this.rooms.get(roomId);
    if (!room) return;
    for (const p of ['left', 'right']) {
      this.playerRoom.delete(room.players[p].id);
    }
    this.roomWagers.delete(roomId);
    this.rooms.delete(roomId);
  }

  _humanSideOf(socketId, room) {
    if (room.players.right.id === socketId) return 'right';
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
  getWagerQueue(lamports) { return [...(this.wagerQueues.get(lamports) || [])]; }

  async _settleWagerRoom(roomId, winnerSide) {
    const room  = this.rooms.get(roomId);
    const wager = this.roomWagers.get(roomId);
    if (!room || !wager || wager.settled) return;

    wager.settled = true;
    const winnerWallet = room.players[winnerSide]?.wallet;
    const loserSide    = winnerSide === 'left' ? 'right' : 'left';
    const loserWallet  = room.players[loserSide]?.wallet;

    if (!winnerWallet || !loserWallet) {
      this.io.to(roomId).emit(EVENTS.WAGER_ERROR, {
        code: 'MISSING_WALLETS',
        message: 'Missing wallet info for wager settlement',
      });
      return;
    }

    if (!wager.matchEscrowPda) {
      this.io.to(roomId).emit(EVENTS.WAGER_ERROR, {
        code: 'MATCH_ESCROW_MISSING',
        message: 'match_wagers was never completed — cannot settle on-chain',
      });
      return;
    }

    this.io.to(roomId).emit(EVENTS.WAGER_SETTLEMENT_PENDING, { wagerId: wager.wagerId });

    const settlement = await this.wagerCustody.settleMatch({
      wagerId:        wager.wagerId,
      lamportsEach:   wager.lamportsEach,
      winnerWallet,
      loserWallet,
      matchEscrowPda:  wager.matchEscrowPda,
      wagerEscrowPdaA: wager.wagerEscrowPdaA,
      wagerEscrowPdaB: wager.wagerEscrowPdaB,
      playerAWallet:   wager.playerAWallet,
      playerBWallet:   wager.playerBWallet,
    });

    this.io.to(roomId).emit(EVENTS.WAGER_SETTLEMENT_DONE, {
      wagerId:          settlement.wagerId,
      winnerWallet:     settlement.winnerWallet,
      winnerLamports:   settlement.winnerLamports.toString(),
      treasuryLamports: settlement.treasuryLamports.toString(),
      settlementTxSig:  settlement.settlementTxSig,
    });
  }
}

function randomPaddleType() {
  return ALL_PADDLE_TYPES[Math.floor(Math.random() * ALL_PADDLE_TYPES.length)];
}

module.exports = { GameManager };
