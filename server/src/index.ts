import { RoomDO } from "./room_do";
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH, RULES_VERSION } from "./rules";

export { RoomDO };

export interface Env {
  ROOM_DO: DurableObjectNamespace;
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8"
    }
  });
}

async function parseBodyJson(request: Request): Promise<unknown> {
  const text = await request.text();
  if (!text) {
    return {};
  }
  return JSON.parse(text);
}

function isValidRoomCode(roomCode: string): boolean {
  const pattern = new RegExp(`^[${ROOM_CODE_ALPHABET}]{${ROOM_CODE_LENGTH}}$`);
  return pattern.test(roomCode);
}

function generateRoomCode(): string {
  const bytes = new Uint8Array(ROOM_CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let value = "";
  for (let i = 0; i < ROOM_CODE_LENGTH; i += 1) {
    const index = bytes[i] % ROOM_CODE_ALPHABET.length;
    value += ROOM_CODE_ALPHABET[index];
  }
  return value;
}

function createDoInternalRequest(url: string, init: RequestInit): Request {
  return new Request(url, {
    method: init.method,
    headers: {
      "content-type": "application/json; charset=utf-8"
    },
    body: init.body
  });
}

async function readJsonResponse<T>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return jsonResponse({ ok: true, rulesVersion: RULES_VERSION });
    }

    if (request.method === "POST" && url.pathname === "/room/create") {
      let nickname = "Host";
      try {
        const body = (await parseBodyJson(request)) as { nickname?: unknown };
        if (typeof body.nickname === "string" && body.nickname.trim().length > 0) {
          nickname = body.nickname.trim();
        }
      } catch {
        return jsonResponse({ ok: false, error: "invalid_payload" }, 400);
      }

      for (let attempt = 0; attempt < 10; attempt += 1) {
        const roomCode = generateRoomCode();
        const id = env.ROOM_DO.idFromName(roomCode);
        const stub = env.ROOM_DO.get(id);
        const doResponse = await stub.fetch(
          createDoInternalRequest("https://room.internal/internal/create", {
            method: "POST",
            body: JSON.stringify({
              roomCode,
              nickname
            })
          })
        );

        const payload = (await doResponse.json()) as { ok: boolean; error?: string; token?: string };
        if (doResponse.status === 409) {
          if (payload.error === "room_exists") {
            continue;
          }
        }
        if (!payload.ok || !payload.token) {
          return jsonResponse({ ok: false, error: payload.error ?? "create_failed" }, doResponse.status);
        }

        return jsonResponse({
          ok: true,
          rulesVersion: RULES_VERSION,
          roomCode,
          token: payload.token,
          wsUrl: `/ws?code=${roomCode}&token=${payload.token}`
        });
      }

      return jsonResponse({ ok: false, error: "room_code_generation_failed" }, 500);
    }

    if (request.method === "POST" && url.pathname === "/room/join") {
      let body: { roomCode?: unknown; nickname?: unknown };
      try {
        body = (await parseBodyJson(request)) as { roomCode?: unknown; nickname?: unknown };
      } catch {
        return jsonResponse({ ok: false, error: "invalid_payload" }, 400);
      }

      if (typeof body.roomCode !== "string" || !isValidRoomCode(body.roomCode)) {
        return jsonResponse({ ok: false, error: "invalid_room_code" }, 400);
      }

      const roomCode = body.roomCode;
      const nickname =
        typeof body.nickname === "string" && body.nickname.trim().length > 0 ? body.nickname.trim() : "Guest";

      const id = env.ROOM_DO.idFromName(roomCode);
      const stub = env.ROOM_DO.get(id);

      const doResponse = await stub.fetch(
        createDoInternalRequest("https://room.internal/internal/join", {
          method: "POST",
          body: JSON.stringify({
            nickname
          })
        })
      );

      const payload = await readJsonResponse<{ ok: boolean; token?: string; error?: string }>(doResponse);
      if (!payload.ok || !payload.token) {
        return jsonResponse({ ok: false, error: payload.error ?? "join_failed" }, doResponse.status);
      }

      return jsonResponse({
        ok: true,
        rulesVersion: RULES_VERSION,
        roomCode,
        token: payload.token,
        wsUrl: `/ws?code=${roomCode}&token=${payload.token}`
      });
    }

    if (request.method === "GET" && url.pathname === "/ws") {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return jsonResponse({ ok: false, error: "expected_websocket_upgrade" }, 426);
      }

      const roomCode = url.searchParams.get("code");
      const token = url.searchParams.get("token");
      if (!roomCode || !isValidRoomCode(roomCode)) {
        return jsonResponse({ ok: false, error: "invalid_room_code" }, 400);
      }
      if (!token) {
        return jsonResponse({ ok: false, error: "invalid_token" }, 401);
      }

      const id = env.ROOM_DO.idFromName(roomCode);
      const stub = env.ROOM_DO.get(id);

      const internalUrl = new URL(request.url);
      internalUrl.protocol = "https:";
      internalUrl.hostname = "room.internal";
      internalUrl.pathname = "/internal/ws";

      return stub.fetch(new Request(internalUrl.toString(), request));
    }

    return jsonResponse({ ok: false, error: "not_found" }, 404);
  }
};
