# SPEC_03_PROTOCOL - HTTP/WS Message Contract
Date: 2026-02-10

> NOTE: Message `type` strings are code-facing identifiers. Do not translate or rename them.

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Lua code implementing this protocol must follow that document.

## 1. HTTP Endpoints (Worker)
### 1.1 `GET /health`
- Response: `{ "ok": true }`

### 1.2 `POST /room/create`
- Request: `{ "nickname": string }` (nickname optional for compatibility)
- Success:
```json
{
  "ok": true,
  "roomCode": "16-char",
  "token": "opaque-token",
  "wsUrl": "/ws?code=...&token=..."
}
```
- Room code generation:
  - length: `16`
  - charset excludes ambiguous chars: `O, 0, I, 1`

### 1.3 `POST /room/join`
- Request:
```json
{ "roomCode": "string", "nickname": "string" }
```
- Errors:
  - `invalid_room_code`
  - `room_not_found`
  - `room_full`
  - `already_started` (policy dependent)

## 2. WebSocket Endpoint
- URL: `GET /ws?code={roomCode}&token={token}`
- Worker routes by room code to DO.
- DO authenticates token and player slot.

## 3. WS Envelope
```json
{
  "type": "string",
  "payload": {},
  "ts": 0
}
```
- `type` namespaces:
  - client -> server: `client.*`
  - server -> client: `server.*`, `room.*`, `match.*`, `chat.*`, `error.*`

## 4. Server -> Client Events (Required)
- `server.welcome`
- `room.state`
- `room.joined`
- `room.left`
- `room.closed`
- `chat.message`
- `chat.denied`
- `match.turnOrder`
- `match.phaseChanged`
- `match.placement.revealStart`
- `match.cards.dealt`
- `match.cards.locked`
- `match.turn.cardCue`
- `match.turn.cardApplied`
- `match.turn.start`
- `match.turn.shotAccepted`
- `match.turn.snapshotRequested`
- `match.turn.snapshotApplied`
- `match.result`
- `error.generic`

## 5. Client -> Server Commands (Required)
- `client.chat.send`
- `client.room.leave`
- `client.match.start`
- `client.match.placement.submit`
- `client.match.cards.pick`
- `client.match.turn.cardUse`
- `client.match.turn.shot`
- `client.match.turn.snapshot`
- `client.match.rematch.vote`
- `client.match.surrender`

## 6. Payload Rules
### 6.1 `client.match.placement.submit`
- Payload:
```json
{
  "stones": [
    { "id": "s1", "x": 100, "y": 520 }
  ]
}
```
- Validation:
  - phase must be `PLACEMENT_PRIVATE`
  - canonical zone + center no-place strip
  - minimum distance
  - exact count (`STONE_COUNT_PER_PLAYER`)

### 6.2 `client.match.cards.pick`
- Payload: `{ "picks": ["agile"] }` (host) or `{ "picks": ["agile", "rockfall"] }` (guest)
- Validation:
  - phase must be `CARD_SELECT`
  - role-specific pick count
  - pick from dealt list only
  - no duplicates
  - timeout -> auto-pick from front

### 6.3 `client.match.turn.cardUse`
- Payload:
```json
{
  "turnIndex": 3,
  "cardId": "rockfall",
  "target": { "x": 300, "y": 500 }
}
```
- `target` is optional by card type.
- Validation:
  - phase `PLAYING`
  - correct turn owner
  - per-turn card-use count <= 1
  - request timing is pre-shot (`CARD_ACTION` stage)
  - card belongs to requester

### 6.4 `client.match.turn.shot`
- Payload:
```json
{
  "turnIndex": 3,
  "stoneId": "s2",
  "dirX": -0.7,
  "dirY": -0.3,
  "power": 450
}
```
- Validation:
  - phase `PLAYING`
  - correct turn owner
  - turn not timed out
  - shot budget not exceeded
  - stone ownership / locked-stone constraints
  - `power` range and normalized direction validity

### 6.5 `client.match.turn.snapshot` (host only)
- Payload:
```json
{
  "turnIndex": 3,
  "stones": [
    {
      "id": "p1_s1",
      "ownerPlayerIndex": 1,
      "x": 120,
      "y": 488,
      "alive": true
    }
  ]
}
```
- Validation:
  - sender must be host
  - current turn index must match
  - snapshot must be requested state
- On success:
  - server normalizes and broadcasts authoritative snapshot
  - server starts next turn or finalizes `RESULT`

### 6.6 `client.match.rematch.vote` (result only)
- Payload:
```json
{
  "action": "rematch"
}
```
- Validation:
  - phase must be `RESULT`
  - action must be `rematch` or `to_lobby`
- Resolution:
  - any `to_lobby` vote => room closes and both clients return to lobby
  - both players vote `rematch` => server transitions `RESULT -> WAITING`

## 7. `room.state` Runtime Contract (Summary)
- `phase` is server-authoritative.
- `timers.phaseEndsAtMs` and `timers.turnEndsAtMs` are authoritative timer fields.
- `match` subtree includes:
  - placement submission/reveal state
  - card deal/pick/lock state
  - playing turn state (`shotBudget`, `shotUsed`, `hasCardUsedThisTurn`, `obstacles`, `invincibleTurnByPlayer`, `shockwaveOwnerPlayerIndex`)
- `result` subtree includes:
  - `reason`
  - `winnerPlayerIndex`
  - vote mirrors (`hostVote`, `guestVote`)

## 8. Error Events
- `error.generic`:
```json
{ "code": "string", "message": "optional" }
```
- Common codes:
  - `invalid_payload`
  - `not_in_phase`
  - `not_your_turn`
  - `host_only`
  - `timeout`
  - `turn_mismatch`
  - `invalid_placement`
  - `invalid_card_pick`
  - `card_already_used`
  - `card_use_window_closed`
  - `invalid_shot_stone`
  - `shot_budget_exceeded`
  - `snapshot_not_requested`

## 9. Chat Contract
- Server-side limiter only (authoritative).
- Defaults:
  - window `10s`
  - max `6`
  - burst `2`
  - max length `120`
