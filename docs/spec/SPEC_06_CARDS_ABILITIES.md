# SPEC_06_CARDS_ABILITIES - Card Abilities and Use Contract
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Message `type` strings follow `docs/spec/SPEC_03_PROTOCOL.md` and must not be renamed.

## 1. Scope
- This document is the SSOT for card ability behavior and card-use timing.
- Card draft/pick transport schema is defined in `docs/spec/SPEC_03_PROTOCOL.md`.
- Turn state integration is defined in `docs/spec/SPEC_05_STATE_MACHINE.md`.

## 2. Card Pool (MVP)
- `reinforcement` (신병)
- `shockwave` (충격파)
- `invincible` (무적)
- `rockfall` (낙석)
- `agile` (날렵함)

## 3. Card Use Common Rules
### 3.1 Per-turn card use limit
- Card use itself is limited to **max 1 card per turn**.
- This limit applies regardless of the card effect result.
- Example:
  - `agile` increases shot count in the same turn.
  - Even then, card use count is still 1 for that turn.

### 3.2 Timing relative to shot
- Card use is allowed in the pre-shot stage of the active turn.
- Required order in turn subflow:
  - `CARD_ACTION -> AIM -> SHOT -> SIM -> SNAPSHOT_RECONCILE -> NEXT_TURN`.

### 3.3 Draft/pick timeout policy
- Card pick timeout auto-selects from the front of dealt list.
- This rule is mandatory and must stay consistent with:
  - `docs/spec/SPEC_03_PROTOCOL.md`
  - `docs/spec/SPEC_04_GAME_RULES.md`

## 4. Network-Authoritative Card Resolution Flow (Recommended)
- Goal: both clients see consistent pre-shot card state.
1. Active player sends card-use request (turn/card/target payload).
2. Server validates:
  - phase/turn owner
  - per-turn card-use limit (= 1)
  - card possession and payload validity
3. Server emits card cue event to both clients (visual pre-effect sync point).
4. Server finalizes card effect state and emits applied event to both clients.
5. Clients render synchronized effect result before entering `AIM`.

## 5. Ability Definitions (MVP)
### 5.1 `reinforcement`
- Spawn 1 friendly stone at valid target position.
- Spawned stone cannot move in the same turn.

### 5.2 `shockwave`
- On qualifying collision, apply radial push around collision boundary point.
- Radius/strength are tunable constants.

### 5.3 `invincible`
- Friendly stones ignore displacement effects for configured turn count.

### 5.4 `rockfall`
- Spawn one rock obstacle at valid target position.

### 5.5 `agile`
- Grants additional shot budget in current turn.
- Does not increase per-turn card-use count.

## 6. Cross-Reference
- Phase-level flow and result rules:
  - `docs/spec/SPEC_04_GAME_RULES.md`
- Turn subflow and state-machine detail:
  - `docs/spec/SPEC_05_STATE_MACHINE.md`
- Network message contract:
  - `docs/spec/SPEC_03_PROTOCOL.md`
- Tunables:
  - `docs/spec/SPEC_07_TUNABLES.md`

## 7. Validation Plan
### 7.1 Server API smoke
- `GET /health` -> `{"ok":true}`
- `POST /room/create` -> `roomCode(16), token, wsUrl`
- `POST /room/join` -> join success / `invalid_room_code` / `room_full`

### 7.2 Waiting room functional
- Two clients join same room.
- Both receive:
  - `server.welcome`
  - `room.state`
  - `room.joined`
- Waiting-room chat works both ways.

### 7.3 Chat rate limit
- Send many messages rapidly.
- Expect:
  - accepted messages are broadcast
  - overflow gets `chat.denied` only to sender

### 7.4 Leave rules
- Guest leave:
  - host remains waiting
- Host leave:
  - room closes
  - guest returns to lobby

### 7.5 Gameplay end-to-end with card rules
1. `TURN_ORDER` entered.
2. Valid placements from both players.
3. 10s reveal transition.
4. Host/guest draft and pick lock (timeout auto-pick from front).
5. Turn subflow order:
   - `CARD_ACTION -> AIM -> SHOT -> SIM -> SNAPSHOT_RECONCILE`
6. Per-turn card use cap:
   - max 1 use even with extra-shot effects.
7. Turn timer and shot cancel behavior.
8. Host snapshot exactly once per turn end.
9. Win/draw result payload validation.
10. Rematch/lobby vote behavior.

### 7.6 Coordinate/display
- Toggle `windowed_1280x720` and `fullscreen_native`.
- Validate screen->world hit test.
- Validate guest lower-side local view rule.

### 7.7 IME/UTF-8 regression
- Korean IME in nickname/chat.
- `textedited` composition visible.
- Backspace on multibyte text does not crash.
- No frame stutter during WS activity.

### 7.8 Persistence validation
- Save nickname/display settings.
- Restart client and verify:
  - values reloaded from `settings.ini`
  - windowed 1280x720 fixed
  - fullscreen current monitor resolution
  - unknown keys ignored safely.

### 7.9 Failure checklist
- Capture on failure:
  - current phase
  - last 10 WS events
  - room code and role
  - local log timestamp
  - expected vs actual.
