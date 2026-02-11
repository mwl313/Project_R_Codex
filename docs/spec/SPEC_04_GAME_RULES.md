# SPEC_04_GAME_RULES - Phase, Turn, Card, Result Rules
Date: 2026-02-10

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
- Server starts authoritative 5-second reveal timer.
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
- Vote handling (server authoritative):
  - action choices: `rematch`, `to_lobby`
  - any `to_lobby` => room closes, both clients return to lobby
  - both `rematch` => phase transitions to `WAITING` in same room
  - vote progress is exposed in room state (`result.myVote`, `result.opponentVote`)

## 2. Shot Input and Power
- Input: drag vector from selected stone.
- Aim helper line must be visible during drag.
- Cancel is allowed before commit.
- Power is proportional to drag distance and clamped.
- Card use, if any, happens before shot in `CARD_ACTION` step.

## 3. Turn End/Stabilization Rule
- A turn ends when one of these happens:
  - turn timer expires (server authoritative)
  - shot budget is exhausted and server requests snapshot settlement
- Client-side simulation stop heuristic uses `PHYSICS_STOP_SPEED` + fixed-step loop.
- End-of-turn authoritative settlement is always via host snapshot request/submit flow.

## 4. Win/Loss/Draw Rules
- Win: opponent has zero alive stones after authoritative settlement.
- Draw conditions for MVP:
  - both players reach zero alive stones in same authoritative snapshot
- Non-draw terminal reasons:
  - `player_left` (disconnect/leave during gameplay)
  - `surrender`

## 5. Card Effect Definitions
### 5.0 Common card-use constraints
- Card use itself is limited to max 1 per turn.
- This cap remains 1 even if `agile` adds extra shot count.
- Card pick timeout policy remains front-first auto-pick.

### 5.1 `reinforcement` (신병)
- Spawn one new friendly stone at chosen valid position.
- Placement UX is cursor-follow preview + board click commit.
- Placement validation:
  - inside board bounds
  - min-distance vs existing stones
  - no overlap with obstacles
- Spawned stone cannot move in the current turn.

### 5.2 `shockwave` (충격파)
- Source is the shot stone center (not collision boundary midpoint).
- Triggered only when the shot source stone collides with:
  - board boundary
  - obstacle
  - stone (ally/enemy)
- Chained collisions in one shot can trigger multiple pulses.
- Shockwave excludes:
  - shot source stone itself
  - invincible stones
- Radius/strength use tunable constants and flat impulse (no distance falloff).

### 5.3 `invincible` (무적)
- For next 1 turn, friendly stones become immovable targets.
- Collision response with non-invincible stones:
  - invincible stone stays fixed
  - moving stone reflects/bounces away (no full freeze)

### 5.4 `rockfall` (낙석)
- Spawn one rock obstacle at chosen valid position.
- Placement UX is cursor-follow preview + board click commit.
- Placement validation:
  - obstacle bounds respect margin (`ROCK_OBSTACLE_MARGIN`)
  - no overlap with stones
  - no overlap with existing obstacles

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

## 8. Change Log
- 2026-02-10:
  - Synced card behavior details to current implementation:
    - reinforcement/rockfall cursor-preview placement flow
    - shockwave center-origin + shot-source-only multi-trigger + flat impulse
    - invincible reflection-style collision response
  - Replaced outdated turn-stop wording with current snapshot-request flow.

