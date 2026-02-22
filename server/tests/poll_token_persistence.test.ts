import test from "node:test";
import assert from "node:assert/strict";
import { RoomDO } from "../src/room_do";

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

async function readJson(response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  return JSON.parse(text) as Record<string, unknown>;
}

test("poll token is persistent across repeated /internal/poll calls", async () => {
  const fakeState = new FakeDurableObjectState();
  const roomDo = new RoomDO(fakeState as unknown as DurableObjectState, {});

  const createResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/create", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        roomCode: "ABCDEFGHJKLMNPQR",
        nickname: "Host"
      })
    })
  );
  const createBody = await readJson(createResponse);
  assert.equal(createBody.ok, true);
  const token = String(createBody.token ?? "");
  assert.ok(token.length > 0, "create must return persistent host token");

  const firstPollResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/poll", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        token,
        cursor: 0,
        timeoutMs: 0
      })
    })
  );
  const firstPollBody = await readJson(firstPollResponse);
  assert.equal(firstPollBody.ok, true);
  const firstEvents = Array.isArray(firstPollBody.events) ? firstPollBody.events as Array<{ type?: unknown }> : [];
  assert.ok(firstEvents.some((event) => event.type === "server.welcome"), "first poll must include server.welcome");
  assert.ok(firstEvents.some((event) => event.type === "room.state"), "first poll must include room.state");
  const firstCursor = Number(firstPollBody.nextCursor ?? -1);
  assert.ok(Number.isFinite(firstCursor) && firstCursor >= 0);

  const sendChatOneResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/send", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        token,
        envelope: {
          type: "client.chat.send",
          payload: {
            text: "hello-1"
          }
        }
      })
    })
  );
  const sendChatOneBody = await readJson(sendChatOneResponse);
  assert.equal(sendChatOneBody.ok, true);

  const sendChatTwoResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/send", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        token,
        envelope: {
          type: "client.chat.send",
          payload: {
            text: "hello-2"
          }
        }
      })
    })
  );
  const sendChatTwoBody = await readJson(sendChatTwoResponse);
  assert.equal(sendChatTwoBody.ok, true);

  const secondPollResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/poll", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        token,
        cursor: firstCursor,
        timeoutMs: 0
      })
    })
  );
  const secondPollBody = await readJson(secondPollResponse);
  assert.equal(secondPollBody.ok, true, "same token must not become invalid on repeated poll");
  assert.notEqual(secondPollBody.error, "invalid_token");
  const secondEvents = Array.isArray(secondPollBody.events) ? secondPollBody.events as Array<{ type?: unknown }> : [];
  assert.ok(secondEvents.length >= 2, "second poll must contain queued events after cursor");
  assert.ok(secondEvents.every((event) => event.type !== "server.welcome"), "server.welcome must not repeat after first poll");
  const secondCursor = Number(secondPollBody.nextCursor ?? -1);
  assert.ok(secondCursor >= firstCursor + 2, "nextCursor must advance by delivered queue events");

  const thirdPollResponse = await roomDo.fetch(
    new Request("https://room.internal/internal/poll", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8"
      },
      body: JSON.stringify({
        token,
        cursor: secondCursor,
        timeoutMs: 0
      })
    })
  );
  const thirdPollBody = await readJson(thirdPollResponse);
  assert.equal(thirdPollBody.ok, true, "token must stay valid for repeated poll");
  assert.notEqual(thirdPollBody.error, "invalid_token");
});
