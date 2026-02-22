# PHASE_01_SERVER_LOCAL_TEST

## 1) Start local worker

```bash
npm install
npm run dev
```

Base URL: `http://127.0.0.1:8787`

## 2) Health check

```bash
curl -s http://127.0.0.1:8787/health
```

Expected:

```json
{"ok":true}
```

## 3) Create room

```bash
curl -s -X POST http://127.0.0.1:8787/room/create \
  -H "content-type: application/json" \
  -d "{\"nickname\":\"host\"}"
```

Expected fields:
- `ok: true`
- `roomCode` (16 chars)
- `token`

## 4) Join room

```bash
curl -s -X POST http://127.0.0.1:8787/room/join \
  -H "content-type: application/json" \
  -d "{\"roomCode\":\"<ROOM_CODE>\",\"nickname\":\"guest\"}"
```

Expected fields:
- `ok: true`
- `roomCode`
- `token`

## 5) Poll bootstrap (server.welcome + room.state)

Host first poll:

```bash
curl -s -X POST http://127.0.0.1:8787/room/poll \
  -H "content-type: application/json" \
  -d "{\"roomCode\":\"<ROOM_CODE>\",\"token\":\"<HOST_TOKEN>\",\"cursor\":0,\"timeoutMs\":1000}"
```

Expected:
- `ok: true`
- `events` includes `server.welcome`
- `events` includes `room.state`
- `nextCursor` is a number

## 6) Send + poll chat test

Send:

```bash
curl -s -X POST http://127.0.0.1:8787/room/send \
  -H "content-type: application/json" \
  -d "{\"roomCode\":\"<ROOM_CODE>\",\"token\":\"<HOST_TOKEN>\",\"envelope\":{\"type\":\"client.chat.send\",\"payload\":{\"text\":\"hello\"}}}"
```

Then poll host/guest token:
- expected `chat.message` in `events`.
- spam rapidly to verify `chat.denied` (`reason: "rate_limited"`).

## 7) Leave test (HTTP send path)

Guest leave:

```bash
curl -s -X POST http://127.0.0.1:8787/room/send \
  -H "content-type: application/json" \
  -d "{\"roomCode\":\"<ROOM_CODE>\",\"token\":\"<GUEST_TOKEN>\",\"envelope\":{\"type\":\"client.room.leave\",\"payload\":{}}}"
```

Expected:
- host poll receives `room.left` (`playerIndex: 2`)
- host poll receives updated `room.state` (guest empty)
- host leave 시 guest poll receives `room.closed`
