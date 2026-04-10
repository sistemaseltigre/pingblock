// Server-side physics engine for PingBlock
'use strict';

const { GAME } = require('./constants');

/**
 * Advances ball position by `dt` seconds and resolves wall/paddle collisions.
 * Returns updated { ball, scored } where scored is null | 'left' | 'right'.
 */
function stepBall(ball, paddles, dt) {
  let { x, y, vx, vy } = ball;

  x += vx * dt;
  y += vy * dt;

  // Top/bottom wall bounce
  if (y - GAME.BALL_RADIUS <= 0) {
    y = GAME.BALL_RADIUS;
    vy = Math.abs(vy);
  }
  if (y + GAME.BALL_RADIUS >= GAME.HEIGHT) {
    y = GAME.HEIGHT - GAME.BALL_RADIUS;
    vy = -Math.abs(vy);
  }

  let scored = null;

  // Left paddle collision
  const lp = paddles.left;
  if (
    vx < 0 &&
    x - GAME.BALL_RADIUS <= lp.x + GAME.PADDLE_WIDTH &&
    x + GAME.BALL_RADIUS >= lp.x &&
    y >= lp.y &&
    y <= lp.y + lp.height
  ) {
    x = lp.x + GAME.PADDLE_WIDTH + GAME.BALL_RADIUS;
    vx = Math.abs(vx);
    vy = applyPaddleAngle(y, lp, vy);
    ({ vx, vy } = applyPaddlePower(lp.power, vx, vy));
  }

  // Right paddle collision
  const rp = paddles.right;
  if (
    vx > 0 &&
    x + GAME.BALL_RADIUS >= rp.x &&
    x - GAME.BALL_RADIUS <= rp.x + GAME.PADDLE_WIDTH &&
    y >= rp.y &&
    y <= rp.y + rp.height
  ) {
    x = rp.x - GAME.BALL_RADIUS;
    vx = -Math.abs(vx);
    vy = applyPaddleAngle(y, rp, vy);
    ({ vx, vy } = applyPaddlePower(rp.power, vx, vy));
  }

  // Score — ball passed left edge
  if (x - GAME.BALL_RADIUS < 0) {
    scored = 'right'; // right player scores
    return { ball: resetBall(), scored };
  }

  // Score — ball passed right edge
  if (x + GAME.BALL_RADIUS > GAME.WIDTH) {
    scored = 'left';  // left player scores
    return { ball: resetBall(), scored };
  }

  return { ball: { x, y, vx, vy }, scored };
}

/**
 * Angle modifier based on where the ball hits the paddle.
 * Hitting center → mostly horizontal; edge → steep angle.
 */
function applyPaddleAngle(ballY, paddle, vy) {
  const center = paddle.y + paddle.height / 2;
  const relativeIntersect = (ballY - center) / (paddle.height / 2);
  const bounceAngle = relativeIntersect * (Math.PI / 3); // max ±60°
  const speed = Math.sqrt(vy * vy + (GAME.BALL_INITIAL_SPEED * GAME.BALL_INITIAL_SPEED));
  return Math.sin(bounceAngle) * Math.max(speed, GAME.BALL_INITIAL_SPEED);
}

/**
 * Applies paddle-type power effects to ball velocity on hit.
 */
function applyPaddlePower(power, vx, vy) {
  if (!power) return { vx, vy };
  const speed = Math.sqrt(vx * vx + vy * vy);
  const nx = vx / speed;
  const ny = vy / speed;

  switch (power) {
    case 'phoenix': {
      // +50% speed
      const newSpeed = Math.min(speed * 1.5, GAME.BALL_INITIAL_SPEED * 3);
      return { vx: nx * newSpeed, vy: ny * newSpeed };
    }
    case 'frost': {
      // -40% speed, min 150
      const newSpeed = Math.max(speed * 0.6, 150);
      return { vx: nx * newSpeed, vy: ny * newSpeed };
    }
    case 'thunder': {
      // random ±30° deviation
      const angle = Math.atan2(vy, vx) + (Math.random() - 0.5) * (Math.PI / 3);
      return { vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed };
    }
    case 'earth':
    case 'shadow':
    default:
      return { vx, vy };
  }
}

function resetBall() {
  // Serve toward a random side
  const angle = (Math.random() * Math.PI) / 4 - Math.PI / 8;
  const dir = Math.random() < 0.5 ? 1 : -1;
  return {
    x: GAME.WIDTH / 2,
    y: GAME.HEIGHT / 2,
    vx: dir * GAME.BALL_INITIAL_SPEED * Math.cos(angle),
    vy: GAME.BALL_INITIAL_SPEED * Math.sin(angle),
  };
}

function initialBall() {
  return resetBall();
}

function initialPaddle(side) {
  const x =
    side === 'left'
      ? GAME.PADDLE_MARGIN
      : GAME.WIDTH - GAME.PADDLE_MARGIN - GAME.PADDLE_WIDTH;
  return {
    x,
    y: GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2,
    height: GAME.PADDLE_HEIGHT,
    power: null,
  };
}

module.exports = { stepBall, resetBall, initialBall, initialPaddle };
