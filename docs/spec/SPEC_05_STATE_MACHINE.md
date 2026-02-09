# SPEC_05_STATE_MACHINE - State Machine and Implementation Plan
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Protocol identifiers must follow `docs/spec/SPEC_03_PROTOCOL.md`.

## 1. High-Level Phase Flow
1. `WAITING`
2. `TURN_ORDER`
3. `PLACEMENT_PRIVATE`
4. `PLACEMENT_REVEAL`
5. `CARD_SELECT`
6. `PLAYING`
7. `RESULT`

## 2. Phase Authority Rules
- Server is authoritative for:
  - phase transitions
  - phase/turn timers
  - disconnect/surrender result routing
  - end-of-turn snapshot apply timing
- Client is authoritative only for local rendering/input simulation, then reconciles.

## 3. Turn Internal Subflow (`PLAYING`)
- Required turn subflow:
  - `CARD_ACTION -> AIM -> SHOT -> SIM -> SNAPSHOT_RECONCILE -> NEXT_TURN`

### 3.1 `CARD_ACTION`
- Active turn owner may use a card before shot.
- Per-turn card-use count is capped at 1.
- If no card use, transition directly to `AIM`.

### 3.2 `AIM`
- Drag-based aim UI and cancel handling.
- Shot budget starts from base turn shots and may be modified by card effects.

### 3.3 `SHOT`
- Player commits shot input.
- `agile` can increase shot budget for same turn.
- Card use count remains unchanged (still max 1).

### 3.4 `SIM`
- Clients run local physics until stabilization or timeout condition.

### 3.5 `SNAPSHOT_RECONCILE`
- Host submits exactly one authoritative snapshot at turn end.
- Server validates/normalizes and broadcasts.

### 3.6 `NEXT_TURN`
- Server decides next owner/index or transitions to `RESULT`.

## 4. Card-Related Invariants
- Card draft/pick timeout auto-pick uses front-first policy.
- Card use and card pick are distinct:
  - pick occurs in `CARD_SELECT`
  - use occurs in turn `CARD_ACTION`

## 5. Disconnect/Leave Handling
- `WAITING`:
  - host leave => room close
  - guest leave => host remains waiting
- `TURN_ORDER` and later gameplay:
  - disconnect/surrender routes to `RESULT` (server authoritative).

## 5.1 Result Post-Flow (`RESULT`)
- Client command:
  - `client.match.rematch.vote` with `action = rematch | to_lobby`
- Transition rules:
  - any `to_lobby` vote => room close + both lobby
  - both `rematch` votes => `RESULT -> WAITING`
- `room.state.result` carries vote mirror fields for UI:
  - `myVote`
  - `opponentVote`

## 6. Implementation Phases
### 6.1 Phase 1 - Server Minimum Skeleton
- Implement:
  - `GET /health`
  - `POST /room/create`
  - `POST /room/join`
  - `GET /ws?code=...&token=...`
- DO minimum state:
  - `roomCode`, `phase`, `hostToken`, `guestToken`
  - connection flags
  - timer fields
  - chat limiter buckets
- Required room events:
  - `room.state`, `room.joined`, `room.left`, `room.closed`
  - `chat.message`, `chat.denied`

### 6.2 Phase 2 - Client Matching to Waiting Room
- Lobby:
  - keep existing menu
  - add top `싱글플레이어` button (placeholder only)
- Add room create/join UI and waiting room view.
- Enable waiting-room chat through WS.
- Leave flow follows waiting-room rules.

### 6.3 Phase 3 - Match Flow
- Implement one-way flow:
  - `PLACEMENT_PRIVATE -> PLACEMENT_REVEAL -> CARD_SELECT -> PLAYING -> RESULT`
- Use turn subflow in Section 3.
- Placement:
  - click placement only
  - no remove/reposition in MVP
  - center strip + min distance validation
- Reveal:
  - 5s authoritative timer
- Card select:
  - role-based host/guest draft and pick
  - timeout auto-pick
- Playing:
  - turn timer 30s
  - drag shot + cancel + aim helper
  - card use is pre-shot and max 1 per turn
  - host snapshot settlement once per turn

### 6.4 Phase 4 - Card Effects
- `reinforcement` and `rockfall` spawn mechanics.
- `invincible` one-turn displacement immunity.
- `shockwave` on-collision radial push.
- `agile` extra shot by turn state extension.

## 7. DO State and Runtime Policy
- Suggested persisted fields:
  - `roomCode`, `phase`, `createdAtMs`
  - `host`, `guest` slots with token/nickname/connected
  - `turnOrder`, `placements`, `revealEndsAtMs`
  - `cardDraft`, `cardLocks`, `turnState`, `snapshotByTurn`
  - `chatLimiterByToken`
  - `result`
- Timer handling:
  - evaluated on inbound events and scheduled ticks/alarm.

## 8. Runtime Safety Rules
### 8.1 Non-blocking networking
- HTTP and WS integration must not block render/update loop.
- Use event queue pattern:
  - network callbacks enqueue events
  - scene update consumes queue per frame
- IME stutter after network activity is treated as architecture failure.

### 8.2 UTF-8/IME safety
- Support both:
  - `love.textinput`
  - `love.textedited`
- Backspace must use UTF-8 safe deletion via bridge policy:
  - prefer `love.utf8`
  - fallback `require("utf8")`
  - final fallback must never crash
- No byte-slicing (`string.sub`) for multibyte deletion.

### 8.3 Settings persistence
- Save settings to `settings.ini` under identity `project_r`.
- Persist:
  - display mode (`windowed_1280x720` or `fullscreen_native`)
  - nickname
- Must survive restart.
- Detailed INI contract:
  - `docs/spec/SPEC_07_TUNABLES.md`

## 9. Stop Rule
- After spec approval, implementation may begin.
- Before approval, no code changes outside `docs/spec`.

## 10. Cross-Reference
- Ability details:
  - `docs/spec/SPEC_06_CARDS_ABILITIES.md`
- Gameplay rule summary:
  - `docs/spec/SPEC_04_GAME_RULES.md`
