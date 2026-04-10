# PingBlock — Build Tracking

## Stack
- **Frontend**: Flutter 3.33 + Flame (game engine)
- **Backend**: Node.js 24 + Express + Socket.IO
- **Blockchain**: Solana (Anchor 0.32) + VRF scaffold
- **Target device**: Seeker Android (SM02G4061957251) via USB

---

## Phases

### Phase 1 — Monorepo Structure
- [x] Create directory skeleton
- [x] TRACKING.md
- [x] Root README.md

### Phase 2 — Backend (Node.js + Socket.IO)
- [x] package.json
- [x] src/constants.js — shared game constants
- [x] src/physics.js — server-side collision / ball math
- [x] src/gameManager.js — rooms, players, game loop
- [x] src/server.js — Express + Socket.IO entrypoint
- [x] __tests__/physics.test.js — Jest unit tests
- [x] __tests__/gameManager.test.js — room logic tests

### Phase 3 — Flutter + Flame Frontend
- [x] flutter create (bootstrap)
- [x] pubspec.yaml — flame, socket_io_client deps
- [x] lib/main.dart
- [x] lib/models/paddle_type.dart
- [x] lib/models/power.dart
- [x] lib/models/game_state.dart
- [x] lib/services/socket_service.dart
- [x] lib/game/components/ball.dart
- [x] lib/game/components/paddle.dart
- [x] lib/game/components/wall.dart
- [x] lib/game/overlays/hud_overlay.dart
- [x] lib/game/ping_pong_game.dart
- [x] lib/screens/lobby_screen.dart
- [x] lib/screens/game_screen.dart

### Phase 4 — Solana Program Scaffold
- [x] Anchor.toml
- [x] Cargo.toml (workspace)
- [x] programs/ping_pong/Cargo.toml
- [x] programs/ping_pong/src/lib.rs — game state + VRF hooks

### Phase 5 — Dev Scripts
- [x] scripts/dev.sh — starts backend, adb reverse, flutter run
- [x] scripts/setup.sh — installs deps for all sub-projects

### Phase 6 — Tests & Validation
- [x] Backend unit tests pass (Jest)
- [x] Flutter analyze passes
- [x] APK builds without errors

---

## Architecture Decision Log
| Decision | Reason |
|---|---|
| Server-authoritative ball | Prevents desync; server drives ball at 60 tick/s |
| ADB reverse tcp:3000 | Avoids LAN IP config — device connects to localhost:3000 forwarded to Mac |
| Landscape orientation locked | Standard ping pong layout; better on mobile |
| Paddle powers via VRF | Fairness — randomness provably on-chain |
| Flame 1.20 | Stable, well-documented, collision detection built-in |
