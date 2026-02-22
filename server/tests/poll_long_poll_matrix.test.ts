import test from "node:test";
import assert from "node:assert/strict";
import { RoomDO } from "../src/room_do";
import {
  CHAT_RATE_BURST,
  CHAT_RATE_MAX_MSG,
  CHAT_RATE_WINDOW_SEC
} from "../src/rules";

class MemoryStorage {
  private readonly map = new Map<string, unknown>();
  public alarmAtMs: number | null = null;

  async get<T>(key: string): Promise<T | undefined> {
    return this.map.get(key) as T | undefined;
  }

  async put<T>(key: string, value: T): Promise<void> {
    this.map.set(key, value);
  }

  async setAlarm(alarmAtMs: number): Promise<void> {
    this.alarmAtMs = alarmAtMs;
  }
}

class FakeDurableObjectState {
  public readonly storage = new MemoryStorage();
  public readonly pending: Promise<unknown>[] = [];

  waitUntil(promise: Promise<unknown>): void {
    this.pending.push(promise);
  }
}

type Envelope = {
  type: string;
  payload?: unknown;
  ts?: number;
};

type PollResponse = {
  ok: boolean;
  error?: string;
  events?: Envelope[];
  nextCursor?: number;
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readJson(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  return JSON.parse(text) as Record<string, unknown>;
}

async function postJson(roomDo: RoomDO, path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const response = await roomDo.fetch(
    new Request(`https://room.internal${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify(body)
    })
  );
  return readJson(response);
}

async function createRoom(roomDo: RoomDO, nickname: string): Promise<{ roomCode: string; token: string }> {
  const body = await postJson(roomDo, "/internal/create", { roomCode: "ABCDEFGHJKLMNPQR", nickname });
  assert.equal(body.ok, true);
  return {
    roomCode: String(body.roomCode ?? ""),
    token: String(body.token ?? "")
  };
}

async function joinRoom(roomDo: RoomDO, nickname: string): Promise<{ token: string }> {
  const body = await postJson(roomDo, "/internal/join", { nickname });
  assert.equal(body.ok, true);
  return {
    token: String(body.token ?? "")
  };
}

async function pollRoom(roomDo: RoomDO, token: string, cursor: number, timeoutMs: number): Promise<PollResponse> {
  const body = await postJson(roomDo, "/internal/poll", {
    token,
    cursor,
    timeoutMs
  });
  return body as unknown as PollResponse;
}

async function sendEnvelope(roomDo: RoomDO, token: string, type: string, payload: Record<string, unknown>): Promise<void> {
  const body = await postJson(roomDo, "/internal/send", {
    token,
    envelope: {
      type,
      payload
    }
  });
  assert.equal(body.ok, true);
}

function findEnvelope(events: Envelope[] | undefined, type: string): Envelope | null {
  if (!Array.isArray(events)) {
    return null;
  }
  for (const event of events) {
    if (event && event.type === type) {
      return event;
    }
  }
  return null;
}

test("1) host/guest simultaneous initial poll returns correct welcome role/index", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");
  const guest = await joinRoom(roomDo, "Guest");

  const [hostPoll, guestPoll] = await Promise.all([
    pollRoom(roomDo, host.token, 0, 0),
    pollRoom(roomDo, guest.token, 0, 0)
  ]);

  assert.equal(hostPoll.ok, true);
  assert.equal(guestPoll.ok, true);

  const hostWelcome = findEnvelope(hostPoll.events, "server.welcome");
  const guestWelcome = findEnvelope(guestPoll.events, "server.welcome");
  assert.ok(hostWelcome, "host first poll must include server.welcome");
  assert.ok(guestWelcome, "guest first poll must include server.welcome");

  const hostPayload = (hostWelcome?.payload ?? {}) as Record<string, unknown>;
  const guestPayload = (guestWelcome?.payload ?? {}) as Record<string, unknown>;
  assert.equal(hostPayload.role, "host");
  assert.equal(hostPayload.playerIndex, 1);
  assert.equal(guestPayload.role, "guest");
  assert.equal(guestPayload.playerIndex, 2);
  assert.equal(hostPayload.roomCode, host.roomCode);
  assert.equal(guestPayload.roomCode, host.roomCode);
});

test("2) /room/send sender attribution is correct for both directions", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");
  const guest = await joinRoom(roomDo, "Guest");

  const hostInitial = await pollRoom(roomDo, host.token, 0, 0);
  const guestInitial = await pollRoom(roomDo, guest.token, 0, 0);
  let hostCursor = Number(hostInitial.nextCursor ?? 0);
  let guestCursor = Number(guestInitial.nextCursor ?? 0);

  await sendEnvelope(roomDo, guest.token, "client.chat.send", { text: "hello-from-guest" });
  const hostAfterGuest = await pollRoom(roomDo, host.token, hostCursor, 0);
  assert.equal(hostAfterGuest.ok, true);
  const guestChatAtHost = findEnvelope(hostAfterGuest.events, "chat.message");
  assert.ok(guestChatAtHost, "host must receive guest chat message");
  const guestChatPayload = (guestChatAtHost?.payload ?? {}) as Record<string, unknown>;
  assert.equal(guestChatPayload.playerIndex, 2);
  hostCursor = Number(hostAfterGuest.nextCursor ?? hostCursor);

  await sendEnvelope(roomDo, host.token, "client.chat.send", { text: "hello-from-host" });
  const guestAfterHost = await pollRoom(roomDo, guest.token, guestCursor, 0);
  assert.equal(guestAfterHost.ok, true);
  const guestEvents = Array.isArray(guestAfterHost.events) ? guestAfterHost.events : [];
  const hostChatAtGuest = guestEvents.find((event) => {
    if (event.type !== "chat.message") {
      return false;
    }
    const payload = (event.payload ?? {}) as Record<string, unknown>;
    return payload.text === "hello-from-host";
  });
  assert.ok(hostChatAtGuest, "guest must receive host chat message");
  const hostChatPayload = ((hostChatAtGuest?.payload) ?? {}) as Record<string, unknown>;
  assert.equal(hostChatPayload.playerIndex, 1);
  guestCursor = Number(guestAfterHost.nextCursor ?? guestCursor);
  assert.ok(hostCursor >= 0);
  assert.ok(guestCursor >= 0);
});

test("3) cursor is monotonic and no duplicate delivery for same cursor", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");

  const firstPoll = await pollRoom(roomDo, host.token, 0, 0);
  assert.equal(firstPoll.ok, true);
  const cursor0 = Number(firstPoll.nextCursor ?? 0);

  const secondPoll = await pollRoom(roomDo, host.token, cursor0, 0);
  assert.equal(secondPoll.ok, true);
  assert.equal(Array.isArray(secondPoll.events) ? secondPoll.events.length : 0, 0);
  assert.equal(Number(secondPoll.nextCursor ?? -1), cursor0);

  await sendEnvelope(roomDo, host.token, "client.chat.send", { text: "cursor-step" });
  const thirdPoll = await pollRoom(roomDo, host.token, cursor0, 0);
  assert.equal(thirdPoll.ok, true);
  const thirdEvents = Array.isArray(thirdPoll.events) ? thirdPoll.events : [];
  const chatEvents = thirdEvents.filter((event) => event.type === "chat.message");
  assert.equal(chatEvents.length, 1, "single new send must produce one delivered chat.message");
  const cursor1 = Number(thirdPoll.nextCursor ?? -1);
  assert.ok(cursor1 > cursor0, "nextCursor must advance when new event is delivered");

  const fourthPoll = await pollRoom(roomDo, host.token, cursor1, 0);
  assert.equal(fourthPoll.ok, true);
  assert.equal(Array.isArray(fourthPoll.events) ? fourthPoll.events.length : 0, 0);
  assert.equal(Number(fourthPoll.nextCursor ?? -1), cursor1);
});

test("4) long-poll timeout then immediate repoll does not lose session", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");

  const firstPoll = await pollRoom(roomDo, host.token, 0, 0);
  assert.equal(firstPoll.ok, true);
  const cursor = Number(firstPoll.nextCursor ?? 0);

  const timeoutPoll = await pollRoom(roomDo, host.token, cursor, 250);
  assert.equal(timeoutPoll.ok, true);
  assert.notEqual(timeoutPoll.error, "invalid_token");
  assert.equal(Array.isArray(timeoutPoll.events) ? timeoutPoll.events.length : 0, 0);
  assert.equal(Number(timeoutPoll.nextCursor ?? -1), cursor);

  const immediateRepoll = await pollRoom(roomDo, host.token, cursor, 0);
  assert.equal(immediateRepoll.ok, true);
  assert.notEqual(immediateRepoll.error, "invalid_token");
});

test("5) leave/room.closed semantics in waiting phase", async () => {
  {
    const fakeState = new FakeDurableObjectState();
    const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
    const host = await createRoom(roomDo, "Host");
    const guest = await joinRoom(roomDo, "Guest");
    const hostInitial = await pollRoom(roomDo, host.token, 0, 0);
    const hostCursor = Number(hostInitial.nextCursor ?? 0);
    await pollRoom(roomDo, guest.token, 0, 0);

    await sendEnvelope(roomDo, guest.token, "client.room.leave", {});
    const hostAfterGuestLeave = await pollRoom(roomDo, host.token, hostCursor, 0);
    assert.equal(hostAfterGuestLeave.ok, true);
    const leftEvent = findEnvelope(hostAfterGuestLeave.events, "room.left");
    assert.ok(leftEvent, "host must receive room.left when guest leaves");
    const leftPayload = (leftEvent?.payload ?? {}) as Record<string, unknown>;
    assert.equal(leftPayload.playerIndex, 2);
  }

  {
    const fakeState = new FakeDurableObjectState();
    const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
    const host = await createRoom(roomDo, "Host");
    const guest = await joinRoom(roomDo, "Guest");
    await pollRoom(roomDo, host.token, 0, 0);
    const guestInitial = await pollRoom(roomDo, guest.token, 0, 0);
    const guestCursor = Number(guestInitial.nextCursor ?? 0);

    const guestWaitPromise = pollRoom(roomDo, guest.token, guestCursor, 1200);
    await sleep(220);
    await sendEnvelope(roomDo, host.token, "client.room.leave", {});
    const guestAfterHostLeave = await guestWaitPromise;

    assert.equal(guestAfterHostLeave.ok, true, "guest active long-poll should receive host leave close event");
    const closedEvent = findEnvelope(guestAfterHostLeave.events, "room.closed");
    assert.ok(closedEvent, `guest must receive room.closed when host leaves waiting room: ${JSON.stringify(guestAfterHostLeave.events ?? [])}`);
  }
});

test("6) placement reveal timer alarm is not delayed by presence heartbeat", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");
  const guest = await joinRoom(roomDo, "Guest");

  const hostInitial = await pollRoom(roomDo, host.token, 0, 0);
  const guestInitial = await pollRoom(roomDo, guest.token, 0, 0);
  let hostCursor = Number(hostInitial.nextCursor ?? 0);
  let guestCursor = Number(guestInitial.nextCursor ?? 0);

  await sendEnvelope(roomDo, guest.token, "client.room.ready", {});
  const hostAfterReady = await pollRoom(roomDo, host.token, hostCursor, 0);
  hostCursor = Number(hostAfterReady.nextCursor ?? hostCursor);

  await sendEnvelope(roomDo, host.token, "client.match.start", {});
  const hostAfterStart = await pollRoom(roomDo, host.token, hostCursor, 0);
  hostCursor = Number(hostAfterStart.nextCursor ?? hostCursor);
  const guestAfterStart = await pollRoom(roomDo, guest.token, guestCursor, 0);
  guestCursor = Number(guestAfterStart.nextCursor ?? guestCursor);

  const hostStones: Array<{ id: string; x: number; y: number }> = [
    { id: "h1", x: 80, y: 500 },
    { id: "h2", x: 160, y: 500 },
    { id: "h3", x: 240, y: 500 },
    { id: "h4", x: 320, y: 500 },
    { id: "h5", x: 400, y: 500 },
    { id: "h6", x: 480, y: 500 },
    { id: "h7", x: 560, y: 500 }
  ];
  const guestStones: Array<{ id: string; x: number; y: number }> = [
    { id: "g1", x: 80, y: 100 },
    { id: "g2", x: 160, y: 100 },
    { id: "g3", x: 240, y: 100 },
    { id: "g4", x: 320, y: 100 },
    { id: "g5", x: 400, y: 100 },
    { id: "g6", x: 480, y: 100 },
    { id: "g7", x: 560, y: 100 }
  ];

  await sendEnvelope(roomDo, host.token, "client.match.placement.submit", { stones: hostStones });
  await sendEnvelope(roomDo, guest.token, "client.match.placement.submit", { stones: guestStones });

  const hostAfterSubmit = await pollRoom(roomDo, host.token, hostCursor, 0);
  hostCursor = Number(hostAfterSubmit.nextCursor ?? hostCursor);

  let revealEndsAtMs = 0;
  const hostSubmitEvents = Array.isArray(hostAfterSubmit.events) ? hostAfterSubmit.events : [];
  for (const event of hostSubmitEvents) {
    if (event.type !== "room.state") {
      continue;
    }
    const payload = (event.payload ?? {}) as Record<string, unknown>;
    if (payload.phase !== "PLACEMENT_REVEAL") {
      continue;
    }
    const timers = (payload.timers ?? {}) as Record<string, unknown>;
    if (typeof timers.phaseEndsAtMs === "number") {
      revealEndsAtMs = timers.phaseEndsAtMs;
    }
  }
  assert.ok(revealEndsAtMs > 0, "placement reveal state must expose phaseEndsAtMs");

  const alarmBeforeHeartbeat = fakeState.storage.alarmAtMs ?? 0;
  assert.ok(alarmBeforeHeartbeat > 0, "alarm must be scheduled for reveal timeout");
  assert.ok(alarmBeforeHeartbeat <= revealEndsAtMs, "alarm should target the reveal deadline");

  const hostHeartbeatPoll = await pollRoom(roomDo, host.token, hostCursor, 0);
  hostCursor = Number(hostHeartbeatPoll.nextCursor ?? hostCursor);
  const alarmAfterHeartbeat = fakeState.storage.alarmAtMs ?? 0;
  assert.ok(alarmAfterHeartbeat > 0, "alarm must stay scheduled after heartbeat poll");
  assert.ok(
    alarmAfterHeartbeat <= revealEndsAtMs,
    "presence heartbeat must not push alarm later than reveal deadline"
  );
  assert.ok(hostCursor >= 0);
});

test("7) chat rate-limit triggers denied and recovers after window", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});
  const host = await createRoom(roomDo, "Host");

  const firstPoll = await pollRoom(roomDo, host.token, 0, 0);
  let cursor = Number(firstPoll.nextCursor ?? 0);
  const burstCount = CHAT_RATE_MAX_MSG + CHAT_RATE_BURST + 3;
  for (let i = 0; i < burstCount; i += 1) {
    await sendEnvelope(roomDo, host.token, "client.chat.send", {
      text: `burst-${i + 1}`
    });
  }

  const afterBurstPoll = await pollRoom(roomDo, host.token, cursor, 0);
  assert.equal(afterBurstPoll.ok, true);
  const afterBurstEvents = Array.isArray(afterBurstPoll.events) ? afterBurstPoll.events : [];
  const deniedEvents = afterBurstEvents.filter((event) => event.type === "chat.denied");
  assert.ok(deniedEvents.length >= 1, "burst must produce at least one chat.denied event");
  cursor = Number(afterBurstPoll.nextCursor ?? cursor);

  await sleep((CHAT_RATE_WINDOW_SEC * 1000) + 150);
  await sendEnvelope(roomDo, host.token, "client.chat.send", {
    text: "after-window"
  });
  const afterWindowPoll = await pollRoom(roomDo, host.token, cursor, 0);
  assert.equal(afterWindowPoll.ok, true);
  const afterWindowEvents = Array.isArray(afterWindowPoll.events) ? afterWindowPoll.events : [];
  const recoveredChat = afterWindowEvents.find((event) => {
    if (event.type !== "chat.message") {
      return false;
    }
    const payload = (event.payload ?? {}) as Record<string, unknown>;
    return payload.text === "after-window";
  });
  assert.ok(recoveredChat, "chat rate-limit should recover after window");
});
