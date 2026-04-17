'use strict';

const { GameManager } = require('../src/gameManager');
const { EVENTS } = require('../src/constants');

class FakeSocket {
  constructor(id) {
    this.id = id;
    this.data = {};
    this.emitted = [];
    this.rooms = [];
  }

  emit(event, payload) {
    this.emitted.push({ event, payload });
  }

  join(roomId) {
    this.rooms.push(roomId);
  }
}

class FakeIO {
  constructor() {
    this.sockets = { sockets: new Map() };
    this.roomEvents = new Map();
  }

  addSocket(socket) {
    this.sockets.sockets.set(socket.id, socket);
  }

  to(roomId) {
    return {
      emit: (event, payload) => {
        if (!this.roomEvents.has(roomId)) this.roomEvents.set(roomId, []);
        this.roomEvents.get(roomId).push({ event, payload });
      },
    };
  }
}

describe('GameManager wager flow', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
  });

  test('joinWagerLobby enqueues player and emits wager_lobby_joined', async () => {
    const io = new FakeIO();
    const custody = {
      verifyEscrow: jest.fn().mockResolvedValue(true),
      refundSearchCancel: jest.fn(),
      settleMatch: jest.fn(),
    };
    const gm = new GameManager(io, { wagerCustody: custody });
    gm._startGame = jest.fn();

    const s1 = new FakeSocket('s1');
    io.addSocket(s1);

    await gm.joinWagerLobby(s1, {
      playerName: 'P1',
      wallet: 'Wallet111111111111111111111111111111111',
      lamports: 1_000_000_000,
      escrowTxSig: 'escrow_tx_signature_12345',
      intentId: '1001',
    });

    expect(custody.verifyEscrow).toHaveBeenCalledTimes(1);
    expect(gm.getWagerQueue(1_000_000_000)).toEqual(['s1']);
    expect(s1.emitted.some((e) => e.event === EVENTS.WAGER_LOBBY_JOINED)).toBe(true);
  });

  test('two wager players with same lamports are matched', async () => {
    const io = new FakeIO();
    const custody = {
      verifyEscrow: jest.fn().mockResolvedValue(true),
      refundSearchCancel: jest.fn(),
      settleMatch: jest.fn(),
    };
    const gm = new GameManager(io, { wagerCustody: custody });
    gm._startGame = jest.fn();

    const s1 = new FakeSocket('s1');
    const s2 = new FakeSocket('s2');
    io.addSocket(s1);
    io.addSocket(s2);

    await gm.joinWagerLobby(s1, {
      playerName: 'P1',
      wallet: 'Wallet111111111111111111111111111111111',
      lamports: 500_000_000,
      escrowTxSig: 'escrow_sig_111111111111',
      intentId: '2001',
    });
    await gm.joinWagerLobby(s2, {
      playerName: 'P2',
      wallet: 'Wallet222222222222222222222222222222222',
      lamports: 500_000_000,
      escrowTxSig: 'escrow_sig_222222222222',
      intentId: '2002',
    });

    expect(gm.getWagerQueue(500_000_000)).toEqual([]);
    expect(gm.roomWagers.size).toBe(1);

    const [[roomId, events]] = [...io.roomEvents.entries()];
    expect(roomId).toBeTruthy();
    expect(events.some((e) => e.event === EVENTS.MATCH_FOUND)).toBe(true);
    expect(events.some((e) => e.event === EVENTS.WAGER_MATCH_FOUND)).toBe(true);
  });

  test('cancelWagerSearch refunds and dequeues', async () => {
    const io = new FakeIO();
    const custody = {
      verifyEscrow: jest.fn().mockResolvedValue(true),
      refundSearchCancel: jest.fn().mockResolvedValue({
        refundTxSig: 'refund_abc123',
      }),
      settleMatch: jest.fn(),
    };
    const gm = new GameManager(io, { wagerCustody: custody });
    gm._startGame = jest.fn();

    const s1 = new FakeSocket('s1');
    io.addSocket(s1);

    await gm.joinWagerLobby(s1, {
      playerName: 'P1',
      wallet: 'Wallet111111111111111111111111111111111',
      lamports: 1_000_000_000,
      escrowTxSig: 'escrow_tx_signature_12345',
      intentId: '3001',
    });

    await gm.cancelWagerSearch(s1);

    expect(custody.refundSearchCancel).toHaveBeenCalledTimes(1);
    expect(gm.getWagerQueue(1_000_000_000)).toEqual([]);
    expect(s1.emitted.some((e) => e.event === EVENTS.WAGER_REFUND_PENDING)).toBe(true);
    expect(s1.emitted.some((e) => e.event === EVENTS.WAGER_REFUND_DONE)).toBe(true);
  });
});
