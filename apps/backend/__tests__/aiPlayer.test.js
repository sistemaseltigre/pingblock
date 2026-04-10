// Unit + integration tests for AiPlayer
'use strict';

const { AiPlayer, DIFFICULTY } = require('../src/aiPlayer');
const { GAME } = require('../src/constants');

function makePaddle(y = null) {
  return {
    y:      y ?? GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2,
    height: GAME.PADDLE_HEIGHT,
    power:  null,
  };
}

function makeBall({ x, y, vx, vy } = {}) {
  return {
    x:  x  ?? GAME.WIDTH / 2,
    y:  y  ?? GAME.HEIGHT / 2,
    vx: vx ?? 200,
    vy: vy ?? 0,
  };
}

// ── Constructor ──────────────────────────────────────────────────────────────

describe('AiPlayer constructor', () => {
  test('generates a unique id with ai_ prefix', () => {
    const a = new AiPlayer('left', 'medium');
    expect(a.id).toMatch(/^ai_/);
  });

  test('name includes difficulty', () => {
    const a = new AiPlayer('right', 'hard');
    expect(a.name.toLowerCase()).toContain('hard');
  });

  test('defaults to medium if unknown difficulty given', () => {
    const a = new AiPlayer('left', 'godmode');
    expect(a.difficulty).toBe('godmode');      // stored as-is
    expect(a._cfg).toEqual(DIFFICULTY.medium); // falls back to medium cfg
  });
});

// ── computeMove ──────────────────────────────────────────────────────────────

describe('AiPlayer.computeMove — output clamping', () => {
  test('never returns Y below 0', () => {
    const ai      = new AiPlayer('left', 'hard');
    const paddle  = makePaddle(-50);
    const ball    = makeBall({ y: 0, vx: -300 });
    const newY    = ai.computeMove(ball, paddle);
    expect(newY).toBeGreaterThanOrEqual(0);
  });

  test('never returns Y above canvas bottom limit', () => {
    const ai      = new AiPlayer('left', 'hard');
    const paddle  = makePaddle(GAME.HEIGHT + 50);
    const ball    = makeBall({ y: GAME.HEIGHT, vx: -300 });
    const newY    = ai.computeMove(ball, paddle);
    expect(newY).toBeLessThanOrEqual(GAME.HEIGHT - GAME.PADDLE_HEIGHT);
  });
});

describe('AiPlayer.computeMove — easy difficulty moves slowly', () => {
  test('easy AI moves less per tick than hard AI', () => {
    const ballAbove = makeBall({ y: 10, vx: -200, vy: 0 });
    const paddleBot = makePaddle(GAME.HEIGHT - GAME.PADDLE_HEIGHT - 1);

    const easyAi = new AiPlayer('left', 'easy');
    const hardAi = new AiPlayer('left', 'hard');

    // Override noise to 0 so we measure pure movement
    easyAi._noiseY = 0; easyAi._noiseTicksLeft = 999;
    hardAi._noiseY = 0; hardAi._noiseTicksLeft = 999;

    const easyMove = Math.abs(easyAi.computeMove(ballAbove, { ...paddleBot }) - paddleBot.y);
    const hardMove = Math.abs(hardAi.computeMove(ballAbove, { ...paddleBot }) - paddleBot.y);

    expect(hardMove).toBeGreaterThan(easyMove);
  });
});

describe('AiPlayer.computeMove — direction', () => {
  test('moves upward when ball is above paddle center', () => {
    const ai = new AiPlayer('left', 'hard');
    ai._noiseY = 0; ai._noiseTicksLeft = 999;

    const paddle = makePaddle(300); // bottom half of screen
    const ball   = makeBall({ y: 50, vx: -200, vy: 0 }); // top of screen

    const newY = ai.computeMove(ball, paddle);
    expect(newY).toBeLessThan(paddle.y); // moved up
  });

  test('moves downward when ball is below paddle center', () => {
    const ai = new AiPlayer('left', 'hard');
    ai._noiseY = 0; ai._noiseTicksLeft = 999;

    const paddle = makePaddle(10); // top of screen
    const ball   = makeBall({ y: GAME.HEIGHT - 20, vx: -200, vy: 0 });

    const newY = ai.computeMove(ball, paddle);
    expect(newY).toBeGreaterThan(paddle.y); // moved down
  });
});

// ── _predictLandingY ─────────────────────────────────────────────────────────

describe('AiPlayer._predictLandingY', () => {
  test('returns ball.y when ball is stationary', () => {
    const ai   = new AiPlayer('left', 'hard');
    const ball = makeBall({ vx: 0, vy: 0 });
    expect(ai._predictLandingY(ball)).toBe(ball.y);
  });

  test('returns ball.y when ball moves away from AI', () => {
    // Left AI but ball moving right (away)
    const ai   = new AiPlayer('left', 'hard');
    const ball = makeBall({ x: GAME.WIDTH / 2, vx: 300, vy: 0 });
    expect(ai._predictLandingY(ball)).toBe(ball.y);
  });

  test('predicts landing within canvas bounds when ball bounces', () => {
    const ai   = new AiPlayer('left', 'hard');
    const ball = makeBall({
      x:  GAME.WIDTH / 2,
      y:  GAME.BALL_RADIUS + 5,
      vx: -400,
      vy: -200, // heading toward top wall
    });
    const predicted = ai._predictLandingY(ball);
    expect(predicted).toBeGreaterThanOrEqual(GAME.BALL_RADIUS);
    expect(predicted).toBeLessThanOrEqual(GAME.HEIGHT - GAME.BALL_RADIUS);
  });
});

// ── shouldUsePower ───────────────────────────────────────────────────────────

describe('AiPlayer.shouldUsePower', () => {
  test('easy AI never uses power (powerChance = 0)', () => {
    const ai  = new AiPlayer('left', 'easy');
    let fired = false;
    for (let i = 0; i < 1000; i++) {
      if (ai.shouldUsePower(Date.now())) { fired = true; break; }
    }
    expect(fired).toBe(false);
  });

  test('hard AI may use power over many ticks', () => {
    const ai  = new AiPlayer('left', 'hard');
    let fired = false;
    for (let i = 0; i < 5000; i++) {
      if (ai.shouldUsePower(Date.now())) { fired = true; break; }
    }
    expect(fired).toBe(true);
  });

  test('cooldown prevents immediate re-use', () => {
    const ai  = new AiPlayer('left', 'hard');
    // Force it to fire
    ai._powerCooldownUntil = 0;
    // Even if shouldUsePower returns true once, set internal cooldown externally
    ai._powerCooldownUntil = Date.now() + 99_999;
    expect(ai.shouldUsePower(Date.now())).toBe(false);
  });
});

// ── Integration: vs-cpu game via GameManager ─────────────────────────────────

const { createServer } = require('http');
const { Server }       = require('socket.io');
const Client           = require('socket.io-client');
const { GameManager }  = require('../src/gameManager');
const { EVENTS }       = require('../src/constants');

function makeStack() {
  const httpServer = createServer();
  const io         = new Server(httpServer, { cors: { origin: '*' } });
  const gm         = new GameManager(io);

  io.on('connection', (socket) => {
    socket.on(EVENTS.JOIN_LOBBY,  ({ name } = {})             => gm.joinLobby(socket, name));
    socket.on(EVENTS.JOIN_VS_CPU, ({ name, difficulty } = {}) => gm.joinVsCpu(socket, name, difficulty));
    socket.on(EVENTS.PADDLE_MOVE, ({ y })                     => gm.movePaddle(socket.id, y));
    socket.on(EVENTS.USE_POWER,   ()                          => gm.usePower(socket.id));
    socket.on('disconnect',       ()                          => gm.playerDisconnected(socket.id));
  });

  return new Promise((resolve) => {
    httpServer.listen(0, () => {
      const { port } = httpServer.address();
      resolve({ io, gm, httpServer, port });
    });
  });
}

function connect(port) {
  return Client(`http://localhost:${port}`, { forceNew: true, transports: ['websocket'] });
}

function waitFor(socket, event, ms = 8000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`Timeout: ${event}`)), ms);
    socket.once(event, (d) => { clearTimeout(t); resolve(d); });
  });
}

let stack;
beforeEach(async () => { stack = await makeStack(); }, 10_000);
afterEach(async  () => {
  stack.io.close();
  await new Promise((r) => stack.httpServer.close(r));
}, 10_000);

test('join_vs_cpu creates room immediately (no waiting for 2nd player)', async () => {
  const c = connect(stack.port);
  try {
    await new Promise((r) => c.once('connect', r));
    c.emit(EVENTS.JOIN_VS_CPU, { name: 'Alice', difficulty: 'easy' });
    const match = await waitFor(c, EVENTS.MATCH_FOUND);
    expect(match.vscpu).toBe(true);
    expect(match.roomId).toBeTruthy();
    expect(match.left).toBeDefined();
    expect(match.right).toBeDefined();
  } finally {
    c.disconnect();
  }
}, 10_000);

test('CPU game starts and emits game_state ticks', async () => {
  const c = connect(stack.port);
  try {
    await new Promise((r) => c.once('connect', r));
    c.emit(EVENTS.JOIN_VS_CPU, { name: 'Alice', difficulty: 'medium' });
    await waitFor(c, EVENTS.MATCH_FOUND);
    await waitFor(c, EVENTS.GAME_START, 8000);
    const state = await waitFor(c, EVENTS.GAME_STATE, 5000);
    expect(state.ball).toBeDefined();
    expect(state.paddles.left).toBeDefined();
    expect(state.paddles.right).toBeDefined();
  } finally {
    c.disconnect();
  }
}, 15_000);

test('match_found for CPU game has correct difficulty in payload', async () => {
  const c = connect(stack.port);
  try {
    await new Promise((r) => c.once('connect', r));
    c.emit(EVENTS.JOIN_VS_CPU, { name: 'Alice', difficulty: 'hard' });
    const match = await waitFor(c, EVENTS.MATCH_FOUND);
    expect(match.difficulty).toBe('hard');
  } finally {
    c.disconnect();
  }
}, 10_000);

test('human paddle_move is applied in CPU game', async () => {
  const c = connect(stack.port);
  try {
    await new Promise((r) => c.once('connect', r));
    c.emit(EVENTS.JOIN_VS_CPU, { name: 'Alice', difficulty: 'easy' });
    await waitFor(c, EVENTS.MATCH_FOUND);
    await waitFor(c, EVENTS.GAME_START, 8000);

    // Send a paddle move to a specific Y
    c.emit(EVENTS.PADDLE_MOVE, { y: 100 });

    // Read a few states until right paddle reflects our move
    let found = false;
    for (let i = 0; i < 20; i++) {
      const state = await waitFor(c, EVENTS.GAME_STATE, 2000);
      if (Math.abs(state.paddles.right.y - 100) < 20) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
  } finally {
    c.disconnect();
  }
}, 20_000);
