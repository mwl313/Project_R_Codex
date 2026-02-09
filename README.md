# ProjectR Server (Phase 1)

Cloudflare Workers + Durable Objects server skeleton for ProjectR.

## Setup

```bash
npm install
npm run dev
```

Worker runs locally (default Wrangler port `8787`).

## Implemented in Phase 1

- `GET /health`
- `POST /room/create`
- `POST /room/join`
- `GET /ws?code=...&token=...` (WebSocket upgrade)
- Durable Object room state:
  - `roomCode`, `hostToken`, `guestToken`, `phase`, `timers`, `chatLimiter`
- Broadcast events:
  - `room.state`, `room.joined`, `room.left`, `room.closed`
  - `chat.message`, `chat.denied`

Detailed local test commands:
- `docs/spec/PHASE_01_SERVER_LOCAL_TEST.md`

## Phase 2 Client (LÖVE)

Client files are added in the repository root (`main.lua`, `app.lua`, `scenes/*`, `net/*`, `threads/*`).

Run client:

```bash
love .
```

Phase 2 test flow:
- `docs/spec/PHASE_02_CLIENT_LOCAL_TEST.md`

Phase 3 (partial: placement + reveal) test flow:
- `docs/spec/PHASE_03_PLACEMENT_REVEAL_LOCAL_TEST.md`

Phase 3 (partial: card select) test flow:
- `docs/spec/PHASE_03_CARD_SELECT_LOCAL_TEST.md`

Client network worker notes:
- HTTP worker and WS worker run in separate LÖVE threads.
- They require LuaSocket availability in the LÖVE runtime (`require("socket")`, `require("socket.http")`).
