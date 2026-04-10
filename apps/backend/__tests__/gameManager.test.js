// Integration tests for GameManager (room / matchmaking logic)
'use strict';

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
    socket.on(EVENTS.JOIN_LOBBY,  ({ name } = {}) => gm.joinLobby(socket, name));
    socket.on(EVENTS.PADDLE_MOVE, ({ y })          => gm.movePaddle(socket.id, y));
    socket.on(EVENTS.USE_POWER,   ()               => gm.usePower(socket.id));
    socket.on('disconnect',       ()               => gm.playerDisconnected(socket.id));
  });

  return new Promise((resolve) => {
    httpServer.listen(0, () => {
      const { port } = httpServer.address();
      resolve({ io, gm, httpServer, port });
    });
  });
}

function connect(port) {
  // Force WebSocket to avoid HTTP-polling timeout in test env
  return Client(`http://localhost:${port}`, {
    forceNew: true,
    transports: ['websocket'],
  });
}

function waitFor(socket, event, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timeout waiting for "${event}"`)), timeoutMs);
    socket.once(event, (data) => {
      clearTimeout(timer);
      resolve(data);
    });
  });
}

function waitConnect(socket) {
  if (socket.connected) return Promise.resolve();
  return new Promise((res) => socket.once('connect', res));
}

let stack;

beforeEach(async () => {
  stack = await makeStack();
}, 10_000);

afterEach(async () => {
  stack.io.close();
  await new Promise((res) => stack.httpServer.close(res));
}, 10_000);

// ── Matchmaking ─────────────────────────────────────────────────────────────

test('single player gets lobby_joined after emitting join_lobby', async () => {
  const c1 = connect(stack.port);
  try {
    await waitConnect(c1);
    c1.emit(EVENTS.JOIN_LOBBY, { name: 'Alice' });
    const payload = await waitFor(c1, EVENTS.LOBBY_JOINED);
    expect(payload.position).toBe(1);
    expect(stack.gm.getQueue().length).toBe(1);
  } finally {
    c1.disconnect();
  }
}, 10_000);

test('two players are matched and receive match_found', async () => {
  const [c1, c2] = [connect(stack.port), connect(stack.port)];
  try {
    await Promise.all([waitConnect(c1), waitConnect(c2)]);
    c1.emit(EVENTS.JOIN_LOBBY, { name: 'Alice' });
    c2.emit(EVENTS.JOIN_LOBBY, { name: 'Bob' });

    const [p1, p2] = await Promise.all([
      waitFor(c1, EVENTS.MATCH_FOUND),
      waitFor(c2, EVENTS.MATCH_FOUND),
    ]);
    expect(p1.roomId).toBe(p2.roomId);
    expect(p1.left).toBeDefined();
    expect(p1.right).toBeDefined();
    expect(stack.gm.getQueue().length).toBe(0);
  } finally {
    c1.disconnect();
    c2.disconnect();
  }
}, 15_000);

test('match_found includes paddle types for both players', async () => {
  const [c1, c2] = [connect(stack.port), connect(stack.port)];
  try {
    await Promise.all([waitConnect(c1), waitConnect(c2)]);
    c1.emit(EVENTS.JOIN_LOBBY, { name: 'Alice' });
    c2.emit(EVENTS.JOIN_LOBBY, { name: 'Bob' });

    const [match] = await Promise.all([
      waitFor(c1, EVENTS.MATCH_FOUND),
      waitFor(c2, EVENTS.MATCH_FOUND),
    ]);
    expect(match.left.paddleType).toBeTruthy();
    expect(match.right.paddleType).toBeTruthy();
  } finally {
    c1.disconnect();
    c2.disconnect();
  }
}, 15_000);

// ── Disconnect cleanup ───────────────────────────────────────────────────────

test('disconnecting player removes them from queue', async () => {
  const c1 = connect(stack.port);
  await waitConnect(c1);
  c1.emit(EVENTS.JOIN_LOBBY, { name: 'Alice' });
  await waitFor(c1, EVENTS.LOBBY_JOINED);
  expect(stack.gm.getQueue().length).toBe(1);
  c1.disconnect();
  await new Promise((r) => setTimeout(r, 300));
  expect(stack.gm.getQueue().length).toBe(0);
}, 10_000);

test('opponent_left emitted when in-game player disconnects', async () => {
  const [c1, c2] = [connect(stack.port), connect(stack.port)];
  try {
    await Promise.all([waitConnect(c1), waitConnect(c2)]);
    c1.emit(EVENTS.JOIN_LOBBY, { name: 'Alice' });
    c2.emit(EVENTS.JOIN_LOBBY, { name: 'Bob' });

    await Promise.all([
      waitFor(c1, EVENTS.MATCH_FOUND),
      waitFor(c2, EVENTS.MATCH_FOUND),
    ]);
    const opLeft = waitFor(c2, EVENTS.OPPONENT_LEFT);
    c1.disconnect();
    await opLeft;
  } finally {
    c2.disconnect();
  }
}, 15_000);
