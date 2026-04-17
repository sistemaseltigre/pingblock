# PingBlock — Betting Mode Tracking & Plan

## 1) Objetivo
Agregar una segunda modalidad de juego:
- `free` (actual): sin costo.
- `wager` (nueva): ambos jugadores bloquean SOL, se resuelve al final de partida.

Reglas objetivo:
- El jugador define monto en SOL (solo numérico, > 0, con precisión válida).
- Se valida balance disponible antes de entrar a cola.
- Al iniciar matchmaking de apuestas, fondos quedan en custodia del programa.
- Si cancela búsqueda antes de match, se devuelve 100%.
- Si hay partida:
  - Perdedor: 0%.
  - Ganador: 90% del pozo total.
  - Tesorería recompensas: 10% del pozo total.

---

## 2) Estado actual (base)
- Frontend Flutter/Flame con `LobbyScreen`, matchmaking y juego en tiempo real.
- Backend Node.js + Socket.IO con cola y creación de rooms.
- Programa Anchor `programs/ping_pong` actualmente orientado a estado de partida/VRF scaffold.
- Integración wallet móvil (SMWA) ya funcional para conexión/autorización.

Conclusión: hay base sólida para extender a economía on-chain, pero faltan:
- Modelo de apuestas en backend.
- Flujo UX en lobby.
- Instrucciones on-chain de custodia/settlement/refund.

---

## 3) Diseño funcional propuesto

### 3.1 UX / Frontend
- En `LobbyScreen` agregar selector de modo:
  - `Free`
  - `Apuestas (SOL)`
- Si `Apuestas`:
  - abrir overlay/modal con input numérico (`TextInputType.numberWithOptions(decimal: true)`).
  - validaciones:
    - requerido
    - parseable a decimal
    - `> 0`
    - límites configurables (ejemplo: min 0.01, max 5.0 para devnet)
    - máximo de decimales (recomendado 9 por lamports)
- Mostrar resumen previo:
  - Monto propio
  - Pozo estimado (2x)
  - Fee plataforma (10%)
  - Premio estimado ganador (90%)
- Flujo:
  1. Usuario confirma monto.
  2. Cliente solicita pre-validación de balance y firma de transacción de escrow.
  3. Solo al confirmar escrow entra a cola wager.

### 3.2 Backend / Matchmaking
- Extender protocolo Socket.IO con eventos nuevos:
  - `join_wager_lobby { lamports, escrow_tx_sig, wallet }`
  - `wager_lobby_joined`
  - `wager_match_found { wager_id, opponent, lamports_each, pot_lamports }`
  - `cancel_wager_search`
  - `wager_refund_pending|wager_refund_done`
  - `wager_settlement_pending|wager_settlement_done`
  - `wager_error { code, message }`
- En servidor:
  - cola independiente para apuestas por bucket de monto (evita match de montos distintos).
  - verificar on-chain/índice interno que el escrow está realmente bloqueado para ese jugador+monto.
  - crear `wager_id` canónico por partida.
  - al terminar partida, backend envía settlement on-chain (idealmente vía autoridad del programa o PDA signer model).
  - al cancelar búsqueda, disparar refund on-chain solo si no hubo match.

### 3.3 Programa Solana (Anchor recomendado)
- Mantener Anchor para esta fase (menor riesgo de integración).
- Nuevas cuentas/instrucciones:

1. `WagerEscrow` PDA por jugador y nonce/intent:
- `player`
- `amount_lamports`
- `status: Initiated|Matched|Cancelled|Settled`
- `created_at`
- `match_id` opcional

2. `MatchEscrow` PDA por `wager_id`:
- `player_a`, `player_b`
- `amount_each`
- `pot_total`
- `status`
- `winner` opcional
- `treasury_bps` (1000 = 10%)

3. Instrucciones:
- `init_wager_escrow(amount_lamports, intent_id)`
- `cancel_wager_and_refund(intent_id)`
- `match_wagers(wager_a, wager_b, wager_id)` (solo autoridad backend/relayer autorizada)
- `settle_match(wager_id, winner_pubkey)`:
  - transferir 90% al ganador
  - transferir 10% a treasury PDA/wallet
  - cerrar cuentas si aplica

4. Seguridad:
- checks estrictos de signer/authority
- constraints de estado para evitar doble settlement/refund
- anti-replay con `intent_id`
- validación de montos iguales al hacer match

---

## 4) Quasar vs Anchor (decisión)

Estado:
- Sí existe Quasar como framework Solana (alternativo, orientado a eficiencia/CU).
- El repositorio hoy ya está en Anchor.

Decisión recomendada para este sprint:
- Implementar modo apuestas en Anchor primero.

Razón:
- Reduce riesgo de cambio de stack en una funcionalidad crítica de fondos.
- Permite entregar más rápido y con menor superficie de bugs.
- Luego, fase opcional: benchmark Anchor vs Quasar para migración selectiva.

Plan opcional de evaluación Quasar (post-MVP):
- Reimplementar solo `settle_match` en branch experimental.
- Comparar:
  - tamaño binario
  - compute units
  - complejidad de mantenimiento

---

## 5) Plan por fases

## Phase A — Diseño de contratos y protocolo (1-2 días)
- [x] Definir eventos Socket.IO de wager.
- [x] Definir estructuras on-chain (`WagerEscrow`, `MatchEscrow`).
- [x] Definir autoridad operativa (backend signer / PDA signer strategy).
- [x] Definir fórmula exacta de distribución y redondeo lamports.

## Phase B — Smart contract (2-4 días)
- [x] Crear instrucciones escrow/match/settle/refund.
- [x] Implementar errores y guards de estado.
- [x] Crear tests de contrato iniciales (unit tests Rust con `cargo test`) para fórmula y validaciones base.

## Phase C — Backend (2-3 días)
- [x] Cola wager por monto.
- [x] Validación de escrow previa al match (vía `WagerCustodyService` mockable para swap por on-chain real).
- [x] Integrar cancelación con refund.
- [x] Integrar settlement al finalizar partida.
- [x] Idempotencia de settlement (flag `settled` por room wager).

## Phase D — Frontend (2-3 días)
- [x] Overlay de monto en lobby.
- [x] Validaciones numéricas y UX de errores.
- [x] Flujo firma wallet para escrow (hook inyectable + fallback mock para dev).
- [x] Vista de estado: buscando/cancelando/settling.

## Phase E — End-to-end + hardening (2-4 días)
- [ ] Pruebas E2E en dispositivo.
- [ ] Simulaciones de fallos de red/reintentos.
- [ ] Ajustes de telemetría y mensajes al usuario.

---

## 6) Plan de tests y simulaciones (obligatorio)

### 6.1 Smart Contract (Anchor tests)
Casos felices:
- [ ] Crear escrow válido.
- [ ] Cancelar y devolver 100%.
- [ ] Match de dos escrows iguales.
- [ ] Settlement ganador: 90/10 exacto.

Edge/seguridad:
- [ ] Monto 0 o inválido.
- [ ] Intento de match con montos distintos.
- [ ] Doble settlement bloqueado.
- [ ] Refund después de match (debe fallar).
- [ ] Settlement por actor no autorizado (debe fallar).
- [ ] Replay de `intent_id` (debe fallar).

Invariantes:
- [ ] Conservación de lamports: entrada = ganador + treasury (+ rent residual esperado).
- [ ] Ningún estado terminal permite transición adicional.

### 6.2 Backend (Jest)
- [ ] Unit tests de cola wager por bucket.
- [ ] Unit tests de cancelación antes/después de match.
- [ ] Integración Socket.IO para flujo completo wager.
- [ ] Idempotencia: reintento de settlement no duplica pagos.

### 6.3 Frontend (Flutter tests)
- [ ] Validación input numérico (decimales, vacío, negativo, texto).
- [ ] Render del overlay y estados de carga/error.
- [ ] Flujo cancelar búsqueda de apuestas.
- [ ] Bloqueo de botón mientras tx/confirmación en curso.

### 6.4 Simulaciones E2E
- [ ] Jugador A entra wager, cancela, recibe refund.
- [ ] A y B entran, juegan, gana A: A recibe 90%, treasury 10%.
- [ ] A y B entran, pierde A: B recibe 90%, treasury 10%.
- [ ] Caída temporal backend durante settlement + recuperación.
- [ ] Latencia alta en confirmación de tx (UX no se rompe).
- [ ] Wallet rechaza firma (no entra a cola).

---

## 7) Despliegue en devnet (con tu wallet local Solana CLI)

Precondiciones:
- `solana config get` apuntando a `https://api.devnet.solana.com`
- `solana address` usando `~/.config/solana/id.json`
- fondos devnet suficientes para deploy + tx fees

Checklist operativo:
- [ ] `anchor build`
- [ ] `anchor test` (local validator)
- [ ] `anchor deploy --provider.cluster devnet`
- [ ] registrar `PROGRAM_ID` en backend/frontend `.env`
- [ ] smoke test on-chain: init escrow -> cancel -> init+match+settle

Nota: si se requiere, crear script de airdrop/retry para wallet de deploy y cuentas de prueba.

---

## 8) Riesgos principales y mitigaciones
- Riesgo: inconsistencia backend/on-chain en estados.
  - Mitigación: backend orientado a estado on-chain como fuente de verdad, y operaciones idempotentes.
- Riesgo: redondeo de lamports en 90/10.
  - Mitigación: operar 100% en lamports enteros; definir regla de residuo fija (ej. residuo a treasury).
- Riesgo: abandono de jugador tras match.
  - Mitigación: reglas de abandono explícitas + settlement automático por backend.
- Riesgo: upgrade authority comprometida.
  - Mitigación: separar deploy authority de operación; plan de multisig para producción.

---

## 9) Criterios de aceptación (DoD)
- [ ] Usuario puede jugar `free` sin regresiones.
- [ ] Usuario puede jugar `wager` con monto válido y balance verificado.
- [ ] Fondos se custodian on-chain y se liquidan correctamente en fin de partida.
- [ ] Cancelación previa al match devuelve 100%.
- [ ] Distribución 90/10 validada por tests automáticos y simulación manual.
- [ ] Suite de tests (contract + backend + frontend) en verde.
- [ ] Flujo validado en dispositivo Android real.

---

## 10) Próxima ejecución sugerida (orden)
1. Diseñar cuentas/instrucciones Anchor para escrow/match/settle/refund.
2. Implementar tests Anchor primero.
3. Integrar backend con esas instrucciones y idempotencia.
4. Implementar overlay + flujo en frontend.
5. Correr simulaciones E2E y ajustar.
