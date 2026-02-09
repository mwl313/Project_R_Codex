import {
  CHAT_ALLOWED_PHASES,
  CHAT_MAX_LENGTH,
  CHAT_RATE_BURST,
  CHAT_RATE_MAX_MSG,
  CHAT_RATE_WINDOW_SEC,
  DEFAULT_PHASE,
  NICKNAME_MAX_LENGTH
} from "./rules";
import { errorPayload, serializeEnvelope, type WsEnvelope } from "./protocol";

const STORAGE_KEY = "room_state_v1";

type LeaveReason = "leave" | "disconnect" | "kick" | "unknown";
type ChatDeniedReason = "rate_limited" | "too_long" | "not_allowed_phase";
type Role = "host" | "guest";

interface PlayerSlot {
  token: string | null;
  nickname: string | null;
  connected: boolean;
}

interface RoomState {
  roomCode: string | null;
  phase: string;
  host: PlayerSlot;
  guest: PlayerSlot;
  timers: {
    phaseEndsAtMs?: number;
    turnEndsAtMs?: number;
  };
  chatLimiter: Record<string, number[]>;
  isClosed: boolean;
  createdAtMs: number;
}

interface Session {
  socket: WebSocket;
  role: Role;
  playerIndex: 1 | 2;
  isClosing: boolean;
}

function createEmptySlot(): PlayerSlot {
  return {
    token: null,
    nickname: null,
    connected: false
  };
}

function createDefaultRoomState(): RoomState {
  return {
    roomCode: null,
    phase: DEFAULT_PHASE,
    host: createEmptySlot(),
    guest: createEmptySlot(),
    timers: {},
    chatLimiter: {},
    isClosed: false,
    createdAtMs: 0
  };
}

function createToken(): string {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);
  let result = "";
  for (const value of bytes) {
    result += value.toString(16).padStart(2, "0");
  }
  return result;
}

function sanitizeNickname(raw: unknown, fallback: string): string {
  if (typeof raw !== "string") {
    return fallback;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return fallback;
  }
  return trimmed.slice(0, NICKNAME_MAX_LENGTH);
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

export class RoomDO {
  private readonly state: DurableObjectState;
  private readonly sessions = new Map<string, Session>();
  private room: RoomState = createDefaultRoomState();
  private loadPromise: Promise<void> | null = null;

  constructor(state: DurableObjectState, _env: unknown) {
    this.state = state;
  }

  async fetch(request: Request): Promise<Response> {
    await this.ensureStateLoaded();

    const url = new URL(request.url);
    const { pathname } = url;

    if (pathname === "/internal/create" && request.method === "POST") {
      return this.handleInternalCreate(request);
    }
    if (pathname === "/internal/join" && request.method === "POST") {
      return this.handleInternalJoin(request);
    }
    if (pathname === "/internal/ws" && request.method === "GET") {
      return this.handleInternalWebSocket(request);
    }

    return jsonResponse({ ok: false, error: "not_found" }, 404);
  }

  private async ensureStateLoaded(): Promise<void> {
    if (!this.loadPromise) {
      this.loadPromise = this.loadState();
    }
    await this.loadPromise;
  }

  private async loadState(): Promise<void> {
    const stored = await this.state.storage.get<RoomState>(STORAGE_KEY);
    if (stored) {
      this.room = stored;
    }
  }

  private async saveState(): Promise<void> {
    await this.state.storage.put(STORAGE_KEY, this.room);
  }

  private buildRoomStatePayload(): Record<string, unknown> {
    return {
      roomCode: this.room.roomCode,
      phase: this.room.phase,
      host: {
        connected: this.room.host.connected,
        nickname: this.room.host.nickname ?? "Host"
      },
      guest: this.room.guest.token
        ? {
            connected: this.room.guest.connected,
            nickname: this.room.guest.nickname ?? "Guest"
          }
        : null,
      timers: this.room.timers
    };
  }

  private sendToSocket<T>(socket: WebSocket, type: string, payload: T): void {
    if (socket.readyState !== 1) {
      return;
    }
    socket.send(serializeEnvelope(type, payload));
  }

  private sendToToken<T>(token: string, type: string, payload: T): void {
    const session = this.sessions.get(token);
    if (!session) {
      return;
    }
    this.sendToSocket(session.socket, type, payload);
  }

  private broadcast<T>(type: string, payload: T): void {
    for (const session of this.sessions.values()) {
      this.sendToSocket(session.socket, type, payload);
    }
  }

  private broadcastRoomState(): void {
    this.broadcast("room.state", this.buildRoomStatePayload());
  }

  private getRoleByToken(token: string): Role | null {
    if (this.room.host.token && token === this.room.host.token) {
      return "host";
    }
    if (this.room.guest.token && token === this.room.guest.token) {
      return "guest";
    }
    return null;
  }

  private getPlayerIndex(role: Role): 1 | 2 {
    return role === "host" ? 1 : 2;
  }

  private async handleInternalCreate(request: Request): Promise<Response> {
    let body: unknown;
    try {
      body = await parseBodyJson(request);
    } catch {
      return jsonResponse({ ok: false, error: "invalid_payload" }, 400);
    }

    if (this.room.host.token && !this.room.isClosed) {
      return jsonResponse({ ok: false, error: "room_exists" }, 409);
    }

    const roomCode = typeof (body as { roomCode?: unknown }).roomCode === "string" ? (body as { roomCode: string }).roomCode : null;
    if (!roomCode) {
      return jsonResponse({ ok: false, error: "invalid_room_code" }, 400);
    }

    const nickname = sanitizeNickname((body as { nickname?: unknown }).nickname, "Host");
    const hostToken = createToken();

    this.room = {
      roomCode,
      phase: DEFAULT_PHASE,
      host: {
        token: hostToken,
        nickname,
        connected: false
      },
      guest: createEmptySlot(),
      timers: {},
      chatLimiter: {},
      isClosed: false,
      createdAtMs: Date.now()
    };

    await this.saveState();

    return jsonResponse({
      ok: true,
      roomCode,
      token: hostToken
    });
  }

  private async handleInternalJoin(request: Request): Promise<Response> {
    let body: unknown;
    try {
      body = await parseBodyJson(request);
    } catch {
      return jsonResponse({ ok: false, error: "invalid_payload" }, 400);
    }

    if (!this.room.host.token || this.room.isClosed) {
      return jsonResponse({ ok: false, error: "room_not_found" }, 404);
    }
    if (this.room.phase !== "WAITING") {
      return jsonResponse({ ok: false, error: "already_started" }, 409);
    }
    if (this.room.guest.token) {
      return jsonResponse({ ok: false, error: "room_full" }, 409);
    }

    const nickname = sanitizeNickname((body as { nickname?: unknown }).nickname, "Guest");
    const guestToken = createToken();

    this.room.guest = {
      token: guestToken,
      nickname,
      connected: false
    };

    await this.saveState();

    this.broadcast("room.joined", {
      playerIndex: 2,
      nickname
    });
    this.broadcastRoomState();

    return jsonResponse({
      ok: true,
      roomCode: this.room.roomCode,
      token: guestToken
    });
  }

  private async handleInternalWebSocket(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return jsonResponse({ ok: false, error: "expected_websocket_upgrade" }, 426);
    }

    if (!this.room.host.token || this.room.isClosed) {
      return jsonResponse({ ok: false, error: "room_not_found" }, 404);
    }

    const url = new URL(request.url);
    const token = url.searchParams.get("token");
    if (!token) {
      return jsonResponse({ ok: false, error: "invalid_token" }, 401);
    }

    const role = this.getRoleByToken(token);
    if (!role) {
      return jsonResponse({ ok: false, error: "invalid_token" }, 401);
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    this.openSession(token, role, server);

    return new Response(null, {
      status: 101,
      webSocket: client
    });
  }

  private openSession(token: string, role: Role, socket: WebSocket): void {
    const previous = this.sessions.get(token);
    if (previous) {
      previous.isClosing = true;
      previous.socket.close(1000, "replaced");
      this.sessions.delete(token);
    }

    socket.accept();

    const playerIndex = this.getPlayerIndex(role);
    const session: Session = {
      socket,
      role,
      playerIndex,
      isClosing: false
    };
    this.sessions.set(token, session);

    if (role === "host") {
      this.room.host.connected = true;
    } else {
      this.room.guest.connected = true;
    }
    void this.saveState();

    this.sendToSocket(socket, "server.welcome", {
      roomCode: this.room.roomCode,
      role,
      playerIndex
    });
    this.broadcastRoomState();

    socket.addEventListener("message", (event: MessageEvent) => {
      void this.handleMessage(token, event);
    });
    socket.addEventListener("close", () => {
      void this.handleSocketClose(token, "disconnect");
    });
    socket.addEventListener("error", () => {
      void this.handleSocketClose(token, "disconnect");
    });
  }

  private async handleMessage(token: string, event: MessageEvent): Promise<void> {
    const session = this.sessions.get(token);
    if (!session || session.isClosing) {
      return;
    }
    if (typeof event.data !== "string") {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }

    let envelope: WsEnvelope;
    try {
      envelope = JSON.parse(event.data) as WsEnvelope;
    } catch {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }

    if (!envelope || typeof envelope.type !== "string") {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }

    if (envelope.type === "client.chat.send") {
      await this.handleChatSend(token, session, envelope.payload);
      return;
    }
    if (envelope.type === "client.room.leave") {
      await this.handleLeave(token, "leave");
      return;
    }

    this.sendToToken(token, "error.generic", errorPayload("unsupported_command"));
  }

  private async handleChatSend(token: string, session: Session, payload: unknown): Promise<void> {
    if (!CHAT_ALLOWED_PHASES.has(this.room.phase)) {
      this.sendToToken(token, "chat.denied", {
        reason: "not_allowed_phase" satisfies ChatDeniedReason
      });
      return;
    }

    const text = typeof (payload as { text?: unknown }).text === "string" ? (payload as { text: string }).text.trim() : "";
    if (text.length === 0) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }
    if (text.length > CHAT_MAX_LENGTH) {
      this.sendToToken(token, "chat.denied", {
        reason: "too_long" satisfies ChatDeniedReason
      });
      return;
    }

    const nowMs = Date.now();
    if (!this.consumeChatQuota(token, nowMs)) {
      this.sendToToken(token, "chat.denied", {
        reason: "rate_limited" satisfies ChatDeniedReason
      });
      return;
    }

    await this.saveState();

    this.broadcast("chat.message", {
      playerIndex: session.playerIndex,
      nickname: session.role === "host" ? this.room.host.nickname : this.room.guest.nickname,
      text
    });
  }

  private consumeChatQuota(token: string, nowMs: number): boolean {
    const windowMs = CHAT_RATE_WINDOW_SEC * 1000;
    const hardLimit = CHAT_RATE_MAX_MSG + CHAT_RATE_BURST;
    const prior = this.room.chatLimiter[token] ?? [];
    const recent = prior.filter((timestamp) => nowMs - timestamp <= windowMs);
    if (recent.length >= hardLimit) {
      this.room.chatLimiter[token] = recent;
      return false;
    }
    recent.push(nowMs);
    this.room.chatLimiter[token] = recent;
    return true;
  }

  private async handleSocketClose(token: string, reason: LeaveReason): Promise<void> {
    const session = this.sessions.get(token);
    if (!session || session.isClosing) {
      return;
    }
    await this.handleLeave(token, reason);
  }

  private async handleLeave(token: string, reason: LeaveReason): Promise<void> {
    const session = this.sessions.get(token);
    const role = session?.role ?? this.getRoleByToken(token);
    if (!role) {
      return;
    }

    if (role === "host") {
      await this.handleHostDeparture(reason);
      return;
    }
    await this.handleGuestDeparture(reason);
  }

  private async handleHostDeparture(reason: LeaveReason): Promise<void> {
    if (this.room.isClosed) {
      return;
    }

    this.broadcast("room.left", {
      playerIndex: 1,
      reason
    });
    this.broadcast("room.closed", {
      reason: "host_left"
    });

    this.room.host = createEmptySlot();
    this.room.guest = createEmptySlot();
    this.room.isClosed = true;
    this.room.phase = DEFAULT_PHASE;
    this.room.timers = {};
    this.room.chatLimiter = {};
    await this.saveState();

    this.closeAllSockets("host_left");
  }

  private async handleGuestDeparture(reason: LeaveReason): Promise<void> {
    const guestToken = this.room.guest.token;
    if (!guestToken) {
      return;
    }

    this.broadcast("room.left", {
      playerIndex: 2,
      reason
    });

    const departingSession = this.sessions.get(guestToken);
    if (departingSession) {
      departingSession.isClosing = true;
      departingSession.socket.close(1000, reason);
      this.sessions.delete(guestToken);
    }

    this.room.guest = createEmptySlot();
    await this.saveState();

    this.broadcastRoomState();
  }

  private closeAllSockets(closeReason: string): void {
    for (const [token, session] of this.sessions.entries()) {
      session.isClosing = true;
      session.socket.close(1000, closeReason);
      this.sessions.delete(token);
    }
  }
}
