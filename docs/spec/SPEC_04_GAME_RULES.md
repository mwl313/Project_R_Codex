# SPEC_04_GAME_RULES - Phase, Turn, Card, Result Rules
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- All Lua naming and file-header comment rules must follow that document.

## 1. Phase Definitions and Transitions
### 1.1 `WAITING`
- Two players can chat.
- Transition condition: host triggers start (or auto-start policy once 2 connected).
- Transition to: `TURN_ORDER`.

### 1.2 `TURN_ORDER`
- Server decides first/second player and broadcasts.
- Transition immediately to: `PLACEMENT_PRIVATE`.

### 1.3 `PLACEMENT_PRIVATE`
- Each player places exactly 7 stones by click.
- Placement cannot be removed/repositioned in MVP.
- Constraints:
  - own side only
  - center no-place strip
  - minimum inter-stone distance
- Each player submits once.
- Both submitted -> `PLACEMENT_REVEAL`.

### 1.4 `PLACEMENT_REVEAL`
- Server starts authoritative 10-second reveal timer.
- On timeout -> `CARD_SELECT`.

### 1.5 `CARD_SELECT`
- Card pool (5): `reinforcement`, `shockwave`, `invincible`, `rockfall`, `agile`.
- Distribution is by role, not by turn order:
  - Host: receive 2, pick 1.
  - Guest: receive 3, pick 2.
- No overlap between players in a round.
- Timeout policy: auto-pick from front.
- Both locked (or timeout lock) -> `PLAYING`.

### 1.6 `PLAYING`
- Turn time limit: 30s (server timer).
- Base shots per turn: 1.
- `agile` grants one additional shot in same turn.
- Turn sequence:
  1. server emits `match.turn.start`
  2. active player optional card action (pre-shot, max 1 use per turn)
  3. active player aims by drag; cancel allowed
  4. local physics runs on both clients after shot commit
  5. turn ends on timeout or stabilization
  6. host sends end-of-turn snapshot once
  7. server validates/normalizes/broadcasts snapshot
  8. next turn or `RESULT`

### 1.7 `RESULT`
- End reason shown with winner/draw metadata.
- Vote handling:
  - any `to_lobby` => both to lobby
  - both `rematch` => return to waiting/rematch-ready state

## 2. Shot Input and Power
- Input: drag vector from selected stone.
- Aim helper line must be visible during drag.
- Cancel is allowed before commit.
- Power is proportional to drag distance and clamped.
- Card use, if any, happens before shot in `CARD_ACTION` step.

## 3. Turn End/Stabilization Rule
- A turn ends when one of these happens:
  - turn timer expires
  - all movable stones stay below `STOP_SPEED_THRESHOLD` for `STOP_FRAMES_REQUIRED`
- End-of-turn snapshot is then required from host.

## 4. Win/Loss/Draw Rules
- Win: opponent has zero alive stones after authoritative settlement.
- Draw conditions for MVP:
  - both players reach zero alive stones in same authoritative snapshot
  - maximum turn count reached without win (`MAX_TURN_COUNT`)
  - both players disconnected before winner can be determined

## 5. Card Effect Definitions
### 5.0 Common card-use constraints
- Card use itself is limited to max 1 per turn.
- This cap remains 1 even if `agile` adds extra shot count.
- Card pick timeout policy remains front-first auto-pick.

### 5.1 `reinforcement` (신병)
- Spawn one new friendly stone at chosen valid position.
- Spawned stone cannot move in the current turn.

### 5.2 `shockwave` (충격파)
- On collision after movement, emit radial push around collision boundary point.
- Radius and strength are constants.

### 5.3 `invincible` (무적)
- For next 1 turn, all friendly stones ignore displacement from attacks.

### 5.4 `rockfall` (낙석)
- Spawn one rock obstacle at chosen valid position.

### 5.5 `agile` (날렵함)
- Grants one extra shot in the same turn.

## 6. Leave/Disconnect/Surrender Rules
### 6.1 In `WAITING`
- Host leaves: room closes, guest returns to lobby.
- Guest leaves: host stays in waiting room, slot reopens.

### 6.2 In gameplay phases (`TURN_ORDER` onward)
- Any leave/disconnect/surrender immediately transitions to `RESULT`.
- Default resolution:
  - leaving player loses
  - remaining player wins
  - simultaneous unresolved disconnect can resolve to draw.

## 7. Cross-Reference
- Turn state-machine detail:
  - `docs/spec/SPEC_05_STATE_MACHINE.md`
- Card ability/use detail:
  - `docs/spec/SPEC_06_CARDS_ABILITIES.md`

