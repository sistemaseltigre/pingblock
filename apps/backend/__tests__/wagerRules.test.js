'use strict';

const { WAGER } = require('../src/constants');
const { computePayouts, isValidWagerAmountLamports } = require('../src/wagerRules');

describe('wagerRules.computePayouts', () => {
  test('splits 1 SOL each into 90/10 winner/treasury', () => {
    const oneSol = 1_000_000_000;
    const r = computePayouts(oneSol);

    expect(r.potLamports).toBe(2_000_000_000n);
    expect(r.winnerLamports).toBe(1_800_000_000n);
    expect(r.treasuryLamports).toBe(200_000_000n);
  });

  test('conserves lamports exactly for odd pot values', () => {
    const r = computePayouts(1); // pot = 2 lamports
    expect(r.winnerLamports + r.treasuryLamports).toBe(r.potLamports);
  });

  test('throws on invalid amount', () => {
    expect(() => computePayouts(0)).toThrow(/must be > 0/);
  });

  test('throws on invalid bps', () => {
    expect(() => computePayouts(1000, -1)).toThrow(/out of range/);
    expect(() => computePayouts(1000, 20_000)).toThrow(/out of range/);
  });
});

describe('wagerRules.isValidWagerAmountLamports', () => {
  test('accepts amount in configured range', () => {
    expect(isValidWagerAmountLamports(WAGER.MIN_LAMPORTS)).toBe(true);
    expect(isValidWagerAmountLamports(WAGER.MAX_LAMPORTS)).toBe(true);
  });

  test('rejects non-integer or out-of-range values', () => {
    expect(isValidWagerAmountLamports(1.2)).toBe(false);
    expect(isValidWagerAmountLamports(WAGER.MIN_LAMPORTS - 1)).toBe(false);
    expect(isValidWagerAmountLamports(WAGER.MAX_LAMPORTS + 1)).toBe(false);
    expect(isValidWagerAmountLamports(0)).toBe(false);
    expect(isValidWagerAmountLamports(-100)).toBe(false);
  });
});
