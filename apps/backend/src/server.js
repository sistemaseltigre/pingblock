// PingBlock — Socket.IO game server
'use strict';

const express = require('express');
const http    = require('http');
const cors    = require('cors');
const { Server } = require('socket.io');
const { GameManager } = require('./gameManager');
const { EVENTS } = require('./constants');

const PORT = process.env.PORT || 3000;

const app    = express();
const server = http.createServer(app);

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (_req, res) => res.json({ status: 'ok', ts: Date.now() }));

app.post('/wager/prepare-escrow', async (req, res) => {
  const { wallet, lamports, intentId } = req.body || {};
  try {
    const prepared = await gm.wagerCustody.prepareEscrowTransaction({
      wallet,
      lamports,
      intentId,
    });
    return res.json(prepared);
  } catch (e) {
    return res.status(400).json({
      error: e.message || String(e),
    });
  }
});

const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  pingInterval: 5000,
  pingTimeout:  10000,
});

const gm = new GameManager(io);

io.on('connection', (socket) => {
  console.log(`[+] connected  ${socket.id}`);

  socket.on(EVENTS.JOIN_LOBBY, ({ name } = {}) => {
    console.log(`[~] join_lobby ${socket.id} name=${name}`);
    gm.joinLobby(socket, name);
  });

  socket.on(
    EVENTS.JOIN_WAGER_LOBBY,
    async ({ name, wallet, lamports, escrowTxSig, intentId } = {}) => {
    console.log(
      `[~] join_wager_lobby ${socket.id} name=${name} wallet=${wallet} lamports=${lamports} intentId=${intentId}`,
    );
    try {
      await gm.joinWagerLobby(socket, {
        playerName: name,
        wallet,
        lamports,
        escrowTxSig,
        intentId,
      });
    } catch (e) {
      socket.emit(EVENTS.WAGER_ERROR, {
        code: 'JOIN_WAGER_FAILED',
        message: e.message || String(e),
      });
    }
    },
  );

  socket.on(EVENTS.CANCEL_WAGER_SEARCH, async () => {
    console.log(`[~] cancel_wager_search ${socket.id}`);
    try {
      await gm.cancelWagerSearch(socket);
    } catch (e) {
      socket.emit(EVENTS.WAGER_ERROR, {
        code: 'CANCEL_WAGER_FAILED',
        message: e.message || String(e),
      });
    }
  });

  socket.on(EVENTS.JOIN_VS_CPU, ({ name, difficulty } = {}) => {
    console.log(`[~] join_vs_cpu ${socket.id} name=${name} difficulty=${difficulty}`);
    gm.joinVsCpu(socket, name, difficulty || 'medium');
  });

  socket.on(EVENTS.PADDLE_MOVE, ({ y }) => {
    if (typeof y === 'number') gm.movePaddle(socket.id, y);
  });

  socket.on(EVENTS.USE_POWER, () => {
    gm.usePower(socket.id);
  });

  socket.on('disconnect', () => {
    console.log(`[-] disconnect ${socket.id}`);
    gm.playerDisconnected(socket.id);
  });
});

// Only start server when run directly (not when required in tests)
if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`PingBlock server listening on :${PORT}`);
  });
}

module.exports = { app, server, io, gm };
