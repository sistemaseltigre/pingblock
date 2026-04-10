# PingBlock

Multiplayer ping pong game on Solana. Each paddle is an NFT with unique powers, powered by on-chain VRF for provably fair randomness.

## Tech Stack
- **Frontend**: Flutter + Flame
- **Backend**: Node.js + Socket.IO  
- **Blockchain**: Solana (Anchor) + VRF

## Quick Start

```bash
# Install all dependencies
./scripts/setup.sh

# Start everything (backend + flutter on Seeker)
./scripts/dev.sh
```

## Project Structure
```
pingblock/
├── apps/
│   ├── frontend/          # Flutter + Flame game
│   └── backend/           # Node.js + Socket.IO server
├── programs/
│   └── ping_pong/         # Solana Anchor program
└── scripts/               # Dev & setup scripts
```

## Paddle Types
| Paddle | Power | Effect |
|--------|-------|--------|
| Phoenix | Fire Shot | +50% ball speed on hit |
| Frost | Ice Wall | Slows ball by 40% on hit |
| Thunder | Spark | Random angle deviation on hit |
| Shadow | Phantom | Ball invisible for 1s |
| Earth | Fortress | Extends paddle 50% for 3s |

## Multiplayer Flow
1. Player opens app → Lobby screen
2. Click "Find Match" → joins a Socket.IO room
3. When 2 players join → game starts
4. Game state synced via Socket.IO at 60 tick/s
5. On power activation → VRF call logged on Solana

## Solana Integration
- Each hit is recorded as a transaction (devnet)
- Power activation uses on-chain VRF for fairness
- Paddle NFTs determine available powers (future)
