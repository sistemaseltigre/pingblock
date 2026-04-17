# Phase A Spec — Wager Mode

## Scope
Este documento congela el contrato técnico para iniciar la Phase B (implementación).

Incluye:
- protocolo Socket.IO de apuestas
- modelo de cuentas/instrucciones on-chain
- autoridad operativa inicial
- fórmula de distribución 90/10 en lamports

---

## 1) Socket.IO Contract (Wager)

### 1.1 Client -> Server

`join_wager_lobby`
```json
{
  "name": "4Nd1...nEKL",
  "lamports": 250000000,
  "wallet": "GTE1EWuMUNsTxjmAGSuKNRi7mCvga9WMoNinAMdJzuJR",
  "escrowTxSig": "5fY...abc"
}
```

Rules:
- `lamports` integer, `MIN_LAMPORTS <= lamports <= MAX_LAMPORTS`.
- `wallet` must match connected wallet identity.
- `escrowTxSig` must correspond to successful `init_wager_escrow`.

`cancel_wager_search`
```json
{}
```

---

### 1.2 Server -> Client

`wager_lobby_joined`
```json
{
  "position": 1,
  "lamports": 250000000
}
```

`wager_match_found`
```json
{
  "wagerId": "uuid-or-pda-seed",
  "roomId": "existing-game-room-id",
  "left": { "name": "A", "paddleType": "phoenix", "wallet": "..." },
  "right": { "name": "B", "paddleType": "frost", "wallet": "..." },
  "lamportsEach": 250000000,
  "potLamports": 500000000
}
```

`wager_refund_pending`
```json
{ "wagerId": "..." }
```

`wager_refund_done`
```json
{ "wagerId": "...", "refundTxSig": "..." }
```

`wager_settlement_pending`
```json
{ "wagerId": "..." }
```

`wager_settlement_done`
```json
{
  "wagerId": "...",
  "winnerWallet": "...",
  "winnerLamports": 450000000,
  "treasuryLamports": 50000000,
  "settlementTxSig": "..."
}
```

`wager_error`
```json
{
  "code": "WAGER_ESCROW_NOT_FOUND",
  "message": "Escrow transaction not confirmed for this wallet/amount."
}
```

---

## 2) On-chain Model (Anchor)

## 2.1 Accounts

### `WagerEscrow` PDA
Seeds proposal:
- `b"wager_escrow"`
- `player_pubkey`
- `intent_id` (u64 or random bytes)

Fields:
- `player: Pubkey`
- `amount_lamports: u64`
- `status: u8` (`Initiated=0, Matched=1, Cancelled=2, Settled=3`)
- `intent_id: u64`
- `match_id: Option<Pubkey>` (or `[u8; 32]`)
- `created_at: i64`

### `MatchEscrow` PDA
Seeds proposal:
- `b"match_escrow"`
- `wager_id` (bytes)

Fields:
- `player_a: Pubkey`
- `player_b: Pubkey`
- `amount_each_lamports: u64`
- `pot_lamports: u64`
- `treasury_bps: u16` (default 1000)
- `winner: Option<Pubkey>`
- `status: u8` (`Open=0, Settled=1, Refunded=2`)
- `created_at: i64`

---

## 2.2 Instructions

`init_wager_escrow(amount_lamports: u64, intent_id: u64)`
- signer: `player`
- transfers `amount_lamports` to escrow vault PDA
- creates/updates `WagerEscrow` with status `Initiated`

`cancel_wager_and_refund(intent_id: u64)`
- signer: `player`
- requires `status == Initiated` and not matched
- transfers full amount back to player
- marks `Cancelled`

`match_wagers(wager_a, wager_b, wager_id)`
- signer: `match_authority` (backend/relayer authority)
- requires both escrows `Initiated`, same amount, distinct players
- locks both under `MatchEscrow` and marks escrows `Matched`

`settle_match(wager_id, winner_pubkey)`
- signer: `match_authority`
- requires `MatchEscrow.status == Open`
- pays winner and treasury per formula
- marks `Settled`

---

## 3) Authority Model (Phase A decision)

Initial model (devnet/MVP):
- `match_authority` = backend wallet keypair (server signer).
- Program stores authorized `match_authority` in config PDA.

Rationale:
- Enables deterministic orchestration from Socket.IO server.
- Simplifies first end-to-end release.

Production evolution:
- Move to multisig authority.
- Optionally split authorities (matching vs settlement).

---

## 4) Distribution Formula (canonical)

All calculations in lamports (integers only).

Given:
- `amount_each`
- `pot = amount_each * 2`
- `treasury_bps = 1000`
- `bps_denom = 10000`

Formulas:
- `winner = floor(pot * (bps_denom - treasury_bps) / bps_denom)`
- `treasury = pot - winner`

This guarantees:
- no floating-point errors
- exact conservation (`winner + treasury == pot`)
- lamport remainder is assigned to treasury

---

## 5) Constants (locked for Phase B)

- `TREASURY_BPS = 1000`
- `BPS_DENOMINATOR = 10000`
- `MIN_LAMPORTS = 1_000_000` (0.001 SOL, devnet)
- `MAX_LAMPORTS = 5_000_000_000` (5 SOL, devnet)

These constants are already mirrored in:
- `apps/backend/src/constants.js`
- backend utility `apps/backend/src/wagerRules.js`

---

## 6) Exit criteria for Phase A

- [x] Socket event names/payloads definidos.
- [x] Estructuras on-chain definidas (cuentas + instrucciones).
- [x] Autoridad operativa inicial definida.
- [x] Fórmula canónica 90/10 definida y testeada con unit tests.
