// AI opponent for local / debug mode
'use strict';

const { v4: uuidv4 } = require('uuid');
const { GAME } = require('./constants');

/**
 * Difficulty presets (0.0–1.0 reaction ratio)
 *
 * easy   → reacts to 40% of max speed, +high noise, no lookahead
 * medium → reacts to 70% of max speed, moderate noise, basic lookahead
 * hard   → reacts to 95% of max speed, low noise, full lookahead + power usage
 */
const DIFFICULTY = {
  easy:   { reactionRatio: 0.40, noisePx: 60,  lookahead: false, powerChance: 0.00 },
  medium: { reactionRatio: 0.70, noisePx: 25,  lookahead: true,  powerChance: 0.008 },
  hard:   { reactionRatio: 0.95, noisePx: 6,   lookahead: true,  powerChance: 0.020 },
};

class AiPlayer {
  /**
   * @param {string} side       'left' | 'right'
   * @param {string} difficulty 'easy' | 'medium' | 'hard'
   */
  constructor(side, difficulty = 'medium') {
    this.id         = `ai_${uuidv4().slice(0, 8)}`;
    this.name       = `CPU (${difficulty})`;
    this.side       = side;
    this.difficulty = difficulty;
    this._cfg       = DIFFICULTY[difficulty] || DIFFICULTY.medium;

    // Throttle noise updates so the AI doesn't jitter every tick
    this._noiseY        = 0;
    this._noiseTicksLeft = 0;
    this._powerCooldownUntil = 0;
  }

  // ── Main tick ─────────────────────────────────────────────────────────────

  /**
   * Compute the new paddle Y for this tick.
   * @param {{ x, y, vx, vy }}   ball
   * @param {{ y, height }}       paddle
   * @returns {number}            clamped paddle Y
   */
  computeMove(ball, paddle) {
    const { reactionRatio, noisePx, lookahead } = this._cfg;

    // Determine target Y
    let targetY;
    if (lookahead && this._ballComingToward(ball)) {
      targetY = this._predictLandingY(ball) - paddle.height / 2;
    } else {
      // Default: track current ball Y (center of paddle on ball)
      targetY = ball.y - paddle.height / 2;
    }

    // Add persistent noise (refresh every ~12 ticks ≈ 200ms)
    if (this._noiseTicksLeft <= 0) {
      this._noiseY        = (Math.random() - 0.5) * 2 * noisePx;
      this._noiseTicksLeft = 10 + Math.floor(Math.random() * 8);
    }
    this._noiseTicksLeft--;
    targetY += this._noiseY;

    // Max pixels per tick
    const maxMovePx = GAME.PADDLE_SPEED * reactionRatio * GAME.TICK_MS / 1000;

    const diff    = targetY - paddle.y;
    const move    = Math.sign(diff) * Math.min(Math.abs(diff), maxMovePx);
    const newY    = paddle.y + move;

    return Math.max(0, Math.min(GAME.HEIGHT - paddle.height, newY));
  }

  /**
   * Returns true if the AI should attempt to use its power this tick.
   * Uses a random chance so the AI isn't perfectly timed.
   */
  shouldUsePower(now) {
    if (now < this._powerCooldownUntil) return false;
    if (Math.random() < this._cfg.powerChance) {
      // cooldown applied externally by GameManager (same as human)
      return true;
    }
    return false;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  _ballComingToward(ball) {
    if (this.side === 'left')  return ball.vx < 0;
    if (this.side === 'right') return ball.vx > 0;
    return false;
  }

  /**
   * Predict the Y coordinate where the ball will cross the AI's paddle X.
   * Accounts for top/bottom wall bounces.
   */
  _predictLandingY(ball) {
    const paddleX = this.side === 'left'
      ? GAME.PADDLE_MARGIN + GAME.PADDLE_WIDTH
      : GAME.WIDTH - GAME.PADDLE_MARGIN - GAME.PADDLE_WIDTH;

    if (ball.vx === 0) return ball.y;

    // How many logical pixels until ball reaches our paddle line
    const dx = paddleX - ball.x;
    if (Math.sign(dx) !== Math.sign(ball.vx)) return ball.y; // moving away

    const ticks = dx / ball.vx; // dt in ticks
    let   y     = ball.y + ball.vy * ticks;

    // Simulate wall bounces
    const height = GAME.HEIGHT;
    const r      = GAME.BALL_RADIUS;
    // Fold the Y into the [r, height-r] range
    const range = (height - 2 * r);
    y -= r;
    // Normalize into positive
    y = ((y % (2 * range)) + 2 * range) % (2 * range);
    if (y > range) y = 2 * range - y;
    y += r;

    return y;
  }
}

module.exports = { AiPlayer, DIFFICULTY };
