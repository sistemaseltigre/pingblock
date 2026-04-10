// Unit tests for server-side physics
'use strict';

const { stepBall, resetBall, initialBall, initialPaddle } = require('../src/physics');
const { GAME } = require('../src/constants');

function makePaddles() {
  return {
    left:  { ...initialPaddle('left'),  power: null },
    right: { ...initialPaddle('right'), power: null },
  };
}

describe('resetBall', () => {
  test('ball starts at center', () => {
    const b = resetBall();
    expect(b.x).toBe(GAME.WIDTH / 2);
    expect(b.y).toBe(GAME.HEIGHT / 2);
  });

  test('ball has non-zero velocity', () => {
    const b = resetBall();
    expect(Math.abs(b.vx) + Math.abs(b.vy)).toBeGreaterThan(0);
  });
});

describe('stepBall — wall bounce', () => {
  test('bounces off top wall', () => {
    const paddles = makePaddles();
    // Ball near top wall, moving up
    const ball = { x: GAME.WIDTH / 2, y: GAME.BALL_RADIUS + 1, vx: 0, vy: -200 };
    const { ball: b2, scored } = stepBall(ball, paddles, 0.016);
    expect(scored).toBeNull();
    expect(b2.vy).toBeGreaterThan(0); // bounced downward
  });

  test('bounces off bottom wall', () => {
    const paddles = makePaddles();
    const ball = { x: GAME.WIDTH / 2, y: GAME.HEIGHT - GAME.BALL_RADIUS - 1, vx: 0, vy: 200 };
    const { ball: b2, scored } = stepBall(ball, paddles, 0.016);
    expect(scored).toBeNull();
    expect(b2.vy).toBeLessThan(0); // bounced upward
  });
});

describe('stepBall — scoring', () => {
  test('right player scores when ball passes left edge', () => {
    const paddles = makePaddles();
    // Place ball just past left edge moving left
    const ball = { x: GAME.BALL_RADIUS - 5, y: GAME.HEIGHT / 2, vx: -200, vy: 0 };
    const { scored } = stepBall(ball, paddles, 0.016);
    expect(scored).toBe('right');
  });

  test('left player scores when ball passes right edge', () => {
    const paddles = makePaddles();
    const ball = { x: GAME.WIDTH - GAME.BALL_RADIUS + 5, y: GAME.HEIGHT / 2, vx: 200, vy: 0 };
    const { scored } = stepBall(ball, paddles, 0.016);
    expect(scored).toBe('left');
  });

  test('ball resets to center after score', () => {
    const paddles = makePaddles();
    const ball = { x: 0, y: GAME.HEIGHT / 2, vx: -500, vy: 0 };
    const { ball: b2, scored } = stepBall(ball, paddles, 0.016);
    expect(scored).not.toBeNull();
    expect(b2.x).toBe(GAME.WIDTH / 2);
    expect(b2.y).toBe(GAME.HEIGHT / 2);
  });
});

describe('stepBall — paddle bounce', () => {
  test('bounces off left paddle', () => {
    const paddles = makePaddles();
    // Center paddle vertically
    paddles.left.y = GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2;
    const ball = {
      x: paddles.left.x + GAME.PADDLE_WIDTH + GAME.BALL_RADIUS + 2,
      y: GAME.HEIGHT / 2,
      vx: -300,
      vy: 0,
    };
    const { ball: b2, scored } = stepBall(ball, paddles, 0.02);
    expect(scored).toBeNull();
    expect(b2.vx).toBeGreaterThan(0); // bounced right
  });

  test('bounces off right paddle', () => {
    const paddles = makePaddles();
    paddles.right.y = GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2;
    const ball = {
      x: paddles.right.x - GAME.BALL_RADIUS - 2,
      y: GAME.HEIGHT / 2,
      vx: 300,
      vy: 0,
    };
    const { ball: b2, scored } = stepBall(ball, paddles, 0.02);
    expect(scored).toBeNull();
    expect(b2.vx).toBeLessThan(0); // bounced left
  });
});

describe('stepBall — paddle powers', () => {
  test('phoenix power increases ball speed', () => {
    const paddles = makePaddles();
    paddles.left.y = GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2;
    paddles.left.power = 'phoenix';

    const ball = {
      x: paddles.left.x + GAME.PADDLE_WIDTH + GAME.BALL_RADIUS + 2,
      y: GAME.HEIGHT / 2,
      vx: -300,
      vy: 0,
    };
    const { ball: b2 } = stepBall(ball, paddles, 0.02);
    const speedBefore = 300;
    const speedAfter = Math.sqrt(b2.vx ** 2 + b2.vy ** 2);
    expect(speedAfter).toBeGreaterThan(speedBefore);
  });

  test('frost power decreases ball speed', () => {
    const paddles = makePaddles();
    paddles.left.y = GAME.HEIGHT / 2 - GAME.PADDLE_HEIGHT / 2;
    paddles.left.power = 'frost';

    const ball = {
      x: paddles.left.x + GAME.PADDLE_WIDTH + GAME.BALL_RADIUS + 2,
      y: GAME.HEIGHT / 2,
      vx: -300,
      vy: 0,
    };
    const { ball: b2 } = stepBall(ball, paddles, 0.02);
    const speedAfter = Math.sqrt(b2.vx ** 2 + b2.vy ** 2);
    expect(speedAfter).toBeLessThan(300);
  });
});
