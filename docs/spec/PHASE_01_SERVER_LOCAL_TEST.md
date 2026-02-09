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
- `wsUrl`

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
- `wsUrl`

## 5) WS connect check with wscat

Install once:

```bash
npm i -g wscat
```

Host connection:

```bash
wscat -c "ws://127.0.0.1:8787/ws?code=<ROOM_CODE>&token=<HOST_TOKEN>"
```

Guest connection:

```bash
wscat -c "ws://127.0.0.1:8787/ws?code=<ROOM_CODE>&token=<GUEST_TOKEN>"
```

Expected server events after connect:
- `server.welcome`
- `room.state`
- host side should also receive `room.joined` when guest has joined.

## 6) Chat test

Send in wscat:

```json
{"type":"client.chat.send","payload":{"text":"hello"}}
```

Expected:
- both clients receive `chat.message`.

Rate limit check:
- send many messages quickly (20+) within 10 seconds.
- expected: sender receives `chat.denied` with `reason: "rate_limited"`.

## 7) Leave test

Guest leave command:

```json
{"type":"client.room.leave","payload":{}}
```

Expected:
- host receives `room.left` with `playerIndex: 2`
- host receives updated `room.state` with `guest: null`

Host leave command:

```json
{"type":"client.room.leave","payload":{}}
```

Expected:
- connected guest receives `room.closed` with `reason: "host_left"`
- room becomes unusable for join.
