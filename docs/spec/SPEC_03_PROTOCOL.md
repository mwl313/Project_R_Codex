# SPEC_03_PROTOCOL - HTTP/WS Message Contract
Date: 2026-02-09

> NOTE: Message `type` strings are code-facing identifiers. Do not translate or rename them.


## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Lua code implementing this protocol must follow that document.

## 1. HTTP Endpoints (Worker)
### 1.1 `GET /health`
- Response: `{ "ok": true }`

### 1.2 `POST /room/create`
- Request: `{ "nickname": string }` (nickname optional for initial compatibility)
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
  - charset constant excludes ambiguous chars: `O, 0, I, 1`

### 1.3 `POST /room/join`
- Request:
```json
{ "roomCode": "string", "nickname": "string" }
```
- Errors:
  - `invalid_room_code`
  - `room_not_found`
  - `room_full`
  - `already_started` (optional policy)

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
- `match.turn.snapshotApplied`
- `match.result`

## 5. Client -> Server Commands (Required)
- `client.chat.send`
- `client.room.leave`
- `client.match.placement.submit`
- `client.match.cards.pick`
- `client.match.turn.cardUse`
- `client.match.turn.shot`
- `client.match.turn.snapshot`
- `client.match.rematch.vote`
- Optional for game-time exits:
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
  - canonical zone + no-place strip
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

### 6.3 `client.match.turn.shot`
- Payload:
```json
{
  "turnIndex": 3,
  "shotIndex": 1,
  "stoneId": "s2",
  "dirX": -0.7,
  "dirY": -0.3,
  "power": 450
}
```
- Validation:
  - phase `PLAYING`
  - correct turn owner
  - must be after optional `CARD_ACTION` step
  - turn not timed out
  - shot index allowed by current turn shot budget
  - power range valid

### 6.4 `client.match.turn.cardUse`
- Purpose:
  - request one card use in current turn before shot commit.
- Payload (example):
```json
{
  "turnIndex": 3,
  "cardId": "agile",
  "target": { "x": 300, "y": 500 }
}
```
- Validation:
  - phase `PLAYING`
  - correct turn owner
  - card belongs to requester
  - per-turn card-use count <= 1
  - request timing is pre-shot (`CARD_ACTION` stage)
- On success (recommended authoritative flow):
  - server emits `match.turn.cardCue` to both clients
  - server finalizes effect and emits `match.turn.cardApplied`
  - turn proceeds to `AIM/SHOT` with updated state

### 6.5 `client.match.turn.snapshot` (host only)
- Payload:
```json
{
  "turnIndex": 3,
  "stones": [
    { "id": "s2", "x": 120, "y": 488, "vx": 0, "vy": 0, "alive": true }
  ],
  "obstacles": [],
  "stateFlags": {}
}
```
- Validation:
  - sender must be host
  - current turn index match
  - payload numeric bounds sanity check
- On success:
  - server normalizes and broadcasts authoritative turn snapshot.

### 6.6 `client.match.rematch.vote` (result only)
- Purpose:
  - vote post-result action (`rematch` or `to_lobby`).
- Payload:
```json
{
  "action": "rematch"
}
```
- Validation:
  - phase must be `RESULT`
  - action must be one of: `rematch`, `to_lobby`
- Resolution:
  - any `to_lobby` vote => server closes room and both clients return to lobby
  - both players vote `rematch` => server transitions `RESULT -> WAITING`
  - vote progress is reflected via `room.state.result.myVote/opponentVote`

## 7. Error Events
- `error.generic`:
```json
{ "code": "string", "message": "optional" }
```
- Common codes:
  - `invalid_payload`
  - `not_in_phase`
  - `not_your_turn`
  - `host_only`
  - `rate_limited`
  - `timeout`
  - `invalid_placement`

## 8. Chat Contract
- Server-side limiter only (authoritative).
- Defaults in constants:
  - window `10s`
  - max `6` (generous baseline, tunable)
  - burst `2` (tunable)
  - max length `120`
