'use strict';

const { WAGER } = require('./constants');

/**
 * Returns canonical payout split for a matched wager room.
 *
 * Distribution rule:
 * - winner_share = floor(pot * (1 - treasury_bps))
 * - treasury_share = pot - winner_share
 *
 * This intentionally assigns any lamport remainder to treasury, preserving
 * conservation while avoiding overpayment.
 *
 * @param {number|bigint} amountEachLamports
 * @param {number} treasuryBps
 */
function computePayouts(amountEachLamports, treasuryBps = WAGER.TREASURY_BPS) {
  const each = BigInt(amountEachLamports);
  const bps = BigInt(treasuryBps);
  const denom = BigInt(WAGER.BPS_DENOMINATOR);

  if (each <= 0n) {
    throw new Error('amountEachLamports must be > 0');
  }
  if (bps < 0n || bps > denom) {
    throw new Error('treasuryBps out of range');
  }

  const potLamports = each * 2n;
  const winnerLamports = (potLamports * (denom - bps)) / denom;
  const treasuryLamports = potLamports - winnerLamports;

  return {
    amountEachLamports: each,
    potLamports,
    winnerLamports,
    treasuryLamports,
  };
}

function isValidWagerAmountLamports(
  amountLamports,
  minLamports = WAGER.MIN_LAMPORTS,
  maxLamports = WAGER.MAX_LAMPORTS,
) {
  if (!Number.isSafeInteger(amountLamports)) return false;
  if (amountLamports <= 0) return false;
  return amountLamports >= minLamports && amountLamports <= maxLamports;
}

module.exports = {
  computePayouts,
  isValidWagerAmountLamports,
};
