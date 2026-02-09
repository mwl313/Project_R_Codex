import {
  BOARD_H,
  BOARD_W,
  CARD_PICK_SEC,
  CARD_POOL,
  CHAT_ALLOWED_PHASES,
  CHAT_MAX_LENGTH,
  CHAT_RATE_BURST,
  CHAT_RATE_MAX_MSG,
  CHAT_RATE_WINDOW_SEC,
  DEFAULT_PHASE,
  GUEST_DEAL_COUNT,
  GUEST_PICK_COUNT,
  HOST_DEAL_COUNT,
  HOST_PICK_COUNT,
  MIN_PLACE_DISTANCE,
  NICKNAME_MAX_LENGTH,
  NO_PLACE_BUFFER,
  PHASE_CARD_SELECT,
  PHASE_PLAYING,
  PHASE_PLACEMENT_PRIVATE,
  PHASE_PLACEMENT_REVEAL,
  PHASE_RESULT,
  PHASE_TURN_ORDER,
  PHASE_WAITING,
  PLACEMENT_REVEAL_SEC,
  STONE_COUNT_PER_PLAYER,
  STONE_RADIUS,
  TURN_TIME_LIMIT_SEC,
  MAX_SHOT_POWER
} from "./rules";
import { errorPayload, serializeEnvelope, type WsEnvelope } from "./protocol";

const STORAGE_KEY = "room_state_v2";

type LeaveReason = "leave" | "disconnect" | "kick" | "unknown";
type ChatDeniedReason = "rate_limited" | "too_long" | "not_allowed_phase";
type Role = "host" | "guest";
type CardLockReason = "manual" | "timeout_auto";
type Phase =
  | typeof PHASE_WAITING
  | typeof PHASE_TURN_ORDER
  | typeof PHASE_PLACEMENT_PRIVATE
  | typeof PHASE_PLACEMENT_REVEAL
  | typeof PHASE_CARD_SELECT
  | typeof PHASE_PLAYING
  | typeof PHASE_RESULT;

interface StonePlacement {
  id: string;
  x: number;
  y: number;
}

interface PlayerSlot {
  token: string | null;
  nickname: string | null;
  connected: boolean;
}

interface MatchPlacementState {
  hostStones: StonePlacement[];
  guestStones: StonePlacement[];
  hostSubmitted: boolean;
  guestSubmitted: boolean;
  revealEndsAtMs: number | null;
}

interface MatchCardSelectState {
  hostDealtCards: string[];
  guestDealtCards: string[];
  hostPickedCards: string[];
  guestPickedCards: string[];
  hostLocked: boolean;
  guestLocked: boolean;
  selectEndsAtMs: number | null;
}

interface MatchPlayingStone {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  alive: boolean;
}

interface MatchPlayingState {
  turnIndex: number;
  activePlayerIndex: 1 | 2;
  turnEndsAtMs: number | null;
  shotCommitted: boolean;
  awaitingSnapshot: boolean;
  stones: MatchPlayingStone[];
}

interface MatchState {
  firstPlayerIndex: 1 | 2 | null;
  placement: MatchPlacementState;
  cardSelect: MatchCardSelectState;
  playing: MatchPlayingState;
}

interface RoomState {
  roomCode: string | null;
  phase: Phase;
  host: PlayerSlot;
  guest: PlayerSlot;
  timers: {
    phaseEndsAtMs?: number;
    turnEndsAtMs?: number;
  };
  chatLimiter: Record<string, number[]>;
  isClosed: boolean;
  createdAtMs: number;
  match: MatchState;
  result: {
    reason: string;
    winnerPlayerIndex: 1 | 2 | null;
    leftPlayerIndex?: 1 | 2;
  } | null;
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
    phase: DEFAULT_PHASE as Phase,
    host: createEmptySlot(),
    guest: createEmptySlot(),
    timers: {},
    chatLimiter: {},
    isClosed: false,
    createdAtMs: 0,
    match: {
      firstPlayerIndex: null,
      placement: {
        hostStones: [],
        guestStones: [],
        hostSubmitted: false,
        guestSubmitted: false,
        revealEndsAtMs: null
      },
      cardSelect: {
        hostDealtCards: [],
        guestDealtCards: [],
        hostPickedCards: [],
        guestPickedCards: [],
        hostLocked: false,
        guestLocked: false,
        selectEndsAtMs: null
      },
      playing: {
        turnIndex: 1,
        activePlayerIndex: 1,
        turnEndsAtMs: null,
        shotCommitted: false,
        awaitingSnapshot: false,
        stones: []
      }
    },
    result: null
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

function cloneStones(stoneList: StonePlacement[]): StonePlacement[] {
  return stoneList.map((stone) => ({
    id: stone.id,
    x: stone.x,
    y: stone.y
  }));
}

function clonePlayingStones(stoneList: MatchPlayingStone[]): MatchPlayingStone[] {
  return stoneList.map((stone) => ({
    id: stone.id,
    ownerPlayerIndex: stone.ownerPlayerIndex,
    x: stone.x,
    y: stone.y,
    alive: stone.alive
  }));
}

function isRevealVisiblePhase(phase: Phase): boolean {
  return phase === PHASE_PLACEMENT_REVEAL || phase === PHASE_CARD_SELECT || phase === "PLAYING" || phase === PHASE_RESULT;
}

function isGameplayPhase(phase: Phase): boolean {
  return phase !== PHASE_WAITING;
}

function parsePlacementStones(payload: unknown): StonePlacement[] | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  const value = payload as { stones?: unknown };
  if (!Array.isArray(value.stones)) {
    return null;
  }

  const parsed: StonePlacement[] = [];
  for (const rawStone of value.stones) {
    if (!rawStone || typeof rawStone !== "object") {
      return null;
    }

    const stone = rawStone as { id?: unknown; x?: unknown; y?: unknown };
    if (typeof stone.id !== "string" || stone.id.trim().length === 0) {
      return null;
    }

    if (typeof stone.x !== "number" || typeof stone.y !== "number") {
      return null;
    }

    if (!Number.isFinite(stone.x) || !Number.isFinite(stone.y)) {
      return null;
    }

    parsed.push({
      id: stone.id,
      x: stone.x,
      y: stone.y
    });
  }

  return parsed;
}

function parseCardPickList(payload: unknown): string[] | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const value = payload as { picks?: unknown };
  if (!Array.isArray(value.picks)) {
    return null;
  }

  const picks: string[] = [];
  for (const raw of value.picks) {
    if (typeof raw !== "string" || raw.trim().length === 0) {
      return null;
    }
    picks.push(raw);
  }
  return picks;
}

function parseShotPayload(payload: unknown): { turnIndex: number; stoneId: string; dirX: number; dirY: number; power: number } | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const value = payload as {
    turnIndex?: unknown;
    stoneId?: unknown;
    dirX?: unknown;
    dirY?: unknown;
    power?: unknown;
  };

  if (typeof value.turnIndex !== "number" || typeof value.stoneId !== "string" || typeof value.dirX !== "number" || typeof value.dirY !== "number" || typeof value.power !== "number") {
    return null;
  }
  if (!Number.isFinite(value.turnIndex) || !Number.isFinite(value.dirX) || !Number.isFinite(value.dirY) || !Number.isFinite(value.power)) {
    return null;
  }
  if (value.turnIndex < 1 || Math.floor(value.turnIndex) !== value.turnIndex) {
    return null;
  }
  if (value.stoneId.trim().length === 0) {
    return null;
  }

  return {
    turnIndex: value.turnIndex,
    stoneId: value.stoneId,
    dirX: value.dirX,
    dirY: value.dirY,
    power: value.power
  };
}

function parseSnapshotPayload(payload: unknown): { turnIndex: number; stones: MatchPlayingStone[] } | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const value = payload as { turnIndex?: unknown; stones?: unknown };
  if (typeof value.turnIndex !== "number" || !Array.isArray(value.stones)) {
    return null;
  }
  if (!Number.isFinite(value.turnIndex) || value.turnIndex < 1 || Math.floor(value.turnIndex) !== value.turnIndex) {
    return null;
  }

  const stoneList: MatchPlayingStone[] = [];
  for (const raw of value.stones) {
    if (!raw || typeof raw !== "object") {
      return null;
    }
    const stone = raw as { id?: unknown; ownerPlayerIndex?: unknown; x?: unknown; y?: unknown; alive?: unknown };
    if (typeof stone.id !== "string" || (stone.ownerPlayerIndex !== 1 && stone.ownerPlayerIndex !== 2)) {
      return null;
    }
    if (typeof stone.x !== "number" || typeof stone.y !== "number" || typeof stone.alive !== "boolean") {
      return null;
    }
    if (!Number.isFinite(stone.x) || !Number.isFinite(stone.y)) {
      return null;
    }
    stoneList.push({
      id: stone.id,
      ownerPlayerIndex: stone.ownerPlayerIndex,
      x: stone.x,
      y: stone.y,
      alive: stone.alive
    });
  }

  return {
    turnIndex: value.turnIndex,
    stones: stoneList
  };
}

function shuffleCards(cardList: string[]): string[] {
  const shuffled = [...cardList];
  for (let i = shuffled.length - 1; i > 0; i -= 1) {
    const randomByte = new Uint8Array(1);
    crypto.getRandomValues(randomByte);
    const j = randomByte[0] % (i + 1);
    const temp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = temp;
  }
  return shuffled;
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
    await this.processPhaseTimers(Date.now());

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

  async alarm(): Promise<void> {
    await this.ensureStateLoaded();
    await this.processPhaseTimers(Date.now());
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
      this.ensureRoomStateShape();
    }
  }

  private ensureRoomStateShape(): void {
    if (!this.room.timers) {
      this.room.timers = {};
    }
    if (!this.room.chatLimiter) {
      this.room.chatLimiter = {};
    }

    if (!this.room.match) {
      this.room.match = {
        firstPlayerIndex: null,
        placement: {
          hostStones: [],
          guestStones: [],
          hostSubmitted: false,
          guestSubmitted: false,
          revealEndsAtMs: null
        },
        cardSelect: {
          hostDealtCards: [],
          guestDealtCards: [],
          hostPickedCards: [],
          guestPickedCards: [],
          hostLocked: false,
          guestLocked: false,
          selectEndsAtMs: null
        },
        playing: {
          turnIndex: 1,
          activePlayerIndex: 1,
          turnEndsAtMs: null,
          shotCommitted: false,
          awaitingSnapshot: false,
          stones: []
        }
      };
      return;
    }

    if (!this.room.match.placement) {
      this.room.match.placement = {
        hostStones: [],
        guestStones: [],
        hostSubmitted: false,
        guestSubmitted: false,
        revealEndsAtMs: null
      };
    }

    if (!this.room.match.cardSelect) {
      this.room.match.cardSelect = {
        hostDealtCards: [],
        guestDealtCards: [],
        hostPickedCards: [],
        guestPickedCards: [],
        hostLocked: false,
        guestLocked: false,
        selectEndsAtMs: null
      };
    }

    if (!this.room.match.playing) {
      this.room.match.playing = {
        turnIndex: 1,
        activePlayerIndex: 1,
        turnEndsAtMs: null,
        shotCommitted: false,
        awaitingSnapshot: false,
        stones: []
      };
    }
  }

  private async saveState(): Promise<void> {
    await this.state.storage.put(STORAGE_KEY, this.room);
  }

  private getSlotByRole(role: Role): PlayerSlot {
    return role === "host" ? this.room.host : this.room.guest;
  }

  private getStonesByRole(role: Role): StonePlacement[] {
    return role === "host" ? this.room.match.placement.hostStones : this.room.match.placement.guestStones;
  }

  private setStonesByRole(role: Role, stoneList: StonePlacement[]): void {
    if (role === "host") {
      this.room.match.placement.hostStones = stoneList;
      this.room.match.placement.hostSubmitted = true;
      return;
    }
    this.room.match.placement.guestStones = stoneList;
    this.room.match.placement.guestSubmitted = true;
  }

  private getSubmittedByRole(role: Role): boolean {
    return role === "host" ? this.room.match.placement.hostSubmitted : this.room.match.placement.guestSubmitted;
  }

  private getDealtCardsByRole(role: Role): string[] {
    return role === "host" ? this.room.match.cardSelect.hostDealtCards : this.room.match.cardSelect.guestDealtCards;
  }

  private getPickedCardsByRole(role: Role): string[] {
    return role === "host" ? this.room.match.cardSelect.hostPickedCards : this.room.match.cardSelect.guestPickedCards;
  }

  private setPickedCardsByRole(role: Role, pickedCards: string[]): void {
    if (role === "host") {
      this.room.match.cardSelect.hostPickedCards = pickedCards;
      return;
    }
    this.room.match.cardSelect.guestPickedCards = pickedCards;
  }

  private isLockedByRole(role: Role): boolean {
    return role === "host" ? this.room.match.cardSelect.hostLocked : this.room.match.cardSelect.guestLocked;
  }

  private setLockedByRole(role: Role, isLocked: boolean): void {
    if (role === "host") {
      this.room.match.cardSelect.hostLocked = isLocked;
      return;
    }
    this.room.match.cardSelect.guestLocked = isLocked;
  }

  private getPickCountByRole(role: Role): number {
    return role === "host" ? HOST_PICK_COUNT : GUEST_PICK_COUNT;
  }

  private buildRoomStatePayload(role: Role): Record<string, unknown> {
    const myStones = cloneStones(this.getStonesByRole(role));
    const mySubmitted = this.getSubmittedByRole(role);
    const opponentSubmitted = this.getSubmittedByRole(role === "host" ? "guest" : "host");
    const revealStones = isRevealVisiblePhase(this.room.phase)
      ? {
          host: cloneStones(this.room.match.placement.hostStones),
          guest: cloneStones(this.room.match.placement.guestStones)
        }
      : null;

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
      timers: this.room.timers,
      match: {
        firstPlayerIndex: this.room.match.firstPlayerIndex,
        placement: {
          myStones,
          mySubmitted,
          opponentSubmitted,
          hostSubmitted: this.room.match.placement.hostSubmitted,
          guestSubmitted: this.room.match.placement.guestSubmitted,
          revealStones,
          revealEndsAtMs: this.room.match.placement.revealEndsAtMs
        },
        cardSelect: {
          myDealtCards: [...this.getDealtCardsByRole(role)],
          myPickedCards: [...this.getPickedCardsByRole(role)],
          myPickCount: this.getPickCountByRole(role),
          myLocked: this.isLockedByRole(role),
          opponentLocked: this.isLockedByRole(role === "host" ? "guest" : "host"),
          hostLocked: this.room.match.cardSelect.hostLocked,
          guestLocked: this.room.match.cardSelect.guestLocked,
          selectEndsAtMs: this.room.match.cardSelect.selectEndsAtMs
        },
        playing: {
          turnIndex: this.room.match.playing.turnIndex,
          activePlayerIndex: this.room.match.playing.activePlayerIndex,
          turnEndsAtMs: this.room.match.playing.turnEndsAtMs,
          shotCommitted: this.room.match.playing.shotCommitted,
          awaitingSnapshot: this.room.match.playing.awaitingSnapshot,
          stones: clonePlayingStones(this.room.match.playing.stones)
        }
      },
      result: this.room.result
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
    for (const [token, session] of this.sessions.entries()) {
      this.sendToToken(token, "room.state", this.buildRoomStatePayload(session.role));
    }
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
      phase: DEFAULT_PHASE as Phase,
      host: {
        token: hostToken,
        nickname,
        connected: false
      },
      guest: createEmptySlot(),
      timers: {},
      chatLimiter: {},
      isClosed: false,
      createdAtMs: Date.now(),
      match: {
        firstPlayerIndex: null,
        placement: {
          hostStones: [],
          guestStones: [],
          hostSubmitted: false,
          guestSubmitted: false,
          revealEndsAtMs: null
        },
        cardSelect: {
          hostDealtCards: [],
          guestDealtCards: [],
          hostPickedCards: [],
          guestPickedCards: [],
          hostLocked: false,
          guestLocked: false,
          selectEndsAtMs: null
        },
        playing: {
          turnIndex: 1,
          activePlayerIndex: 1,
          turnEndsAtMs: null,
          shotCommitted: false,
          awaitingSnapshot: false,
          stones: []
        }
      },
      result: null
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
    if (this.room.phase !== PHASE_WAITING) {
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

    const slot = this.getSlotByRole(role);
    slot.connected = true;
    void this.saveState();

    this.sendToSocket(socket, "server.welcome", {
      roomCode: this.room.roomCode,
      role,
      playerIndex
    });
    this.broadcastRoomState();
    if (this.room.phase === PHASE_CARD_SELECT && this.room.match.cardSelect.selectEndsAtMs) {
      this.sendToSocket(socket, "match.cards.dealt", {
        dealtCards: [...this.getDealtCardsByRole(role)],
        pickCount: this.getPickCountByRole(role),
        selectEndsAtMs: this.room.match.cardSelect.selectEndsAtMs
      });
    }

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

  private async startMatchFlow(): Promise<void> {
    if (this.room.phase !== PHASE_WAITING) {
      return;
    }
    if (!this.room.host.connected || !this.room.guest.connected) {
      return;
    }

    this.room.result = null;
    this.room.match.placement.hostStones = [];
    this.room.match.placement.guestStones = [];
    this.room.match.placement.hostSubmitted = false;
    this.room.match.placement.guestSubmitted = false;
    this.room.match.placement.revealEndsAtMs = null;

    this.room.match.cardSelect.hostDealtCards = [];
    this.room.match.cardSelect.guestDealtCards = [];
    this.room.match.cardSelect.hostPickedCards = [];
    this.room.match.cardSelect.guestPickedCards = [];
    this.room.match.cardSelect.hostLocked = false;
    this.room.match.cardSelect.guestLocked = false;
    this.room.match.cardSelect.selectEndsAtMs = null;

    this.room.match.playing.turnIndex = 1;
    this.room.match.playing.activePlayerIndex = 1;
    this.room.match.playing.turnEndsAtMs = null;
    this.room.match.playing.shotCommitted = false;
    this.room.match.playing.awaitingSnapshot = false;
    this.room.match.playing.stones = [];

    const firstPlayerIndex: 1 | 2 = Math.random() < 0.5 ? 1 : 2;
    this.room.match.firstPlayerIndex = firstPlayerIndex;

    const fromWaiting = this.room.phase;
    this.room.phase = PHASE_TURN_ORDER;
    this.broadcast("match.turnOrder", {
      firstPlayerIndex
    });
    this.broadcast("match.phaseChanged", {
      from: fromWaiting,
      to: PHASE_TURN_ORDER
    });

    const fromTurnOrder = this.room.phase;
    this.room.phase = PHASE_PLACEMENT_PRIVATE;
    this.room.timers = {};
    this.broadcast("match.phaseChanged", {
      from: fromTurnOrder,
      to: PHASE_PLACEMENT_PRIVATE
    });

    await this.saveState();
    this.broadcastRoomState();
  }

  private async handleMessage(token: string, event: MessageEvent): Promise<void> {
    await this.processPhaseTimers(Date.now());

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
    if (envelope.type === "client.match.start") {
      await this.handleMatchStart(token, session);
      return;
    }
    if (envelope.type === "client.match.placement.submit") {
      await this.handlePlacementSubmit(token, session, envelope.payload);
      return;
    }
    if (envelope.type === "client.match.cards.pick") {
      await this.handleCardPick(token, session, envelope.payload);
      return;
    }
    if (envelope.type === "client.match.turn.shot") {
      await this.handleTurnShot(token, session, envelope.payload);
      return;
    }
    if (envelope.type === "client.match.turn.snapshot") {
      await this.handleTurnSnapshot(token, session, envelope.payload);
      return;
    }

    this.sendToToken(token, "error.generic", errorPayload("unsupported_command"));
  }

  private async handleMatchStart(token: string, session: Session): Promise<void> {
    if (this.room.phase !== PHASE_WAITING) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }
    if (session.role !== "host") {
      this.sendToToken(token, "error.generic", errorPayload("host_only"));
      return;
    }
    if (!this.room.host.connected || !this.room.guest.connected) {
      this.sendToToken(token, "error.generic", errorPayload("player_not_ready"));
      return;
    }

    await this.startMatchFlow();
  }

  private async handlePlacementSubmit(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_PLACEMENT_PRIVATE) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }

    const slot = this.getSlotByRole(session.role);
    if (!slot.token || slot.token !== token) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_token"));
      return;
    }
    if (this.getSubmittedByRole(session.role)) {
      this.sendToToken(token, "error.generic", errorPayload("already_submitted"));
      return;
    }

    const stoneList = parsePlacementStones(payload);
    if (!stoneList || !this.validatePlacementStones(stoneList, session.role)) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_placement"));
      return;
    }

    this.setStonesByRole(session.role, cloneStones(stoneList));
    await this.saveState();
    this.broadcastRoomState();

    if (this.room.match.placement.hostSubmitted && this.room.match.placement.guestSubmitted) {
      await this.startPlacementReveal();
    }
  }

  private isValidCardPick(role: Role, picks: string[]): boolean {
    if (picks.length !== this.getPickCountByRole(role)) {
      return false;
    }

    const dealtCards = this.getDealtCardsByRole(role);
    const dealtSet = new Set(dealtCards);
    const pickSet = new Set<string>();
    for (const pick of picks) {
      if (!dealtSet.has(pick)) {
        return false;
      }
      if (pickSet.has(pick)) {
        return false;
      }
      pickSet.add(pick);
    }
    return true;
  }

  private lockCards(role: Role, pickedCards: string[], reason: CardLockReason): void {
    this.setPickedCardsByRole(role, [...pickedCards]);
    this.setLockedByRole(role, true);
    this.broadcast("match.cards.locked", {
      playerIndex: this.getPlayerIndex(role),
      pickedCards: [...pickedCards],
      reason
    });
  }

  private async finalizeCardSelectIfReady(): Promise<void> {
    if (this.room.phase !== PHASE_CARD_SELECT) {
      return;
    }
    if (!this.room.match.cardSelect.hostLocked || !this.room.match.cardSelect.guestLocked) {
      return;
    }

    const fromPhase = this.room.phase;
    this.room.phase = PHASE_PLAYING;
    this.room.timers.phaseEndsAtMs = undefined;
    this.room.match.cardSelect.selectEndsAtMs = null;
    this.initializePlayingStateFromPlacements();
    this.startNewTurn(this.room.match.firstPlayerIndex ?? 1);

    await this.saveState();
    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_PLAYING
    });
    this.broadcastTurnStart();
    this.broadcastRoomState();
    if (this.room.match.playing.turnEndsAtMs) {
      await this.state.storage.setAlarm(this.room.match.playing.turnEndsAtMs);
    }
  }

  private initializePlayingStateFromPlacements(): void {
    const hostStones = this.room.match.placement.hostStones.map((stone) => ({
      id: stone.id,
      ownerPlayerIndex: 1 as 1 | 2,
      x: stone.x,
      y: stone.y,
      alive: true
    }));
    const guestStones = this.room.match.placement.guestStones.map((stone) => ({
      id: stone.id,
      ownerPlayerIndex: 2 as 1 | 2,
      x: stone.x,
      y: stone.y,
      alive: true
    }));
    this.room.match.playing.stones = [...hostStones, ...guestStones];
  }

  private startNewTurn(activePlayerIndex: 1 | 2): void {
    const turnEndsAtMs = Date.now() + TURN_TIME_LIMIT_SEC * 1000;
    this.room.match.playing.turnIndex = this.room.match.playing.turnIndex > 0 ? this.room.match.playing.turnIndex : 1;
    this.room.match.playing.activePlayerIndex = activePlayerIndex;
    this.room.match.playing.turnEndsAtMs = turnEndsAtMs;
    this.room.match.playing.shotCommitted = false;
    this.room.match.playing.awaitingSnapshot = false;
    this.room.timers.turnEndsAtMs = turnEndsAtMs;
  }

  private broadcastTurnStart(): void {
    this.broadcast("match.turn.start", {
      turnIndex: this.room.match.playing.turnIndex,
      activePlayerIndex: this.room.match.playing.activePlayerIndex,
      turnEndsAtMs: this.room.match.playing.turnEndsAtMs
    });
  }

  private getAliveCount(playerIndex: 1 | 2): number {
    let count = 0;
    for (const stone of this.room.match.playing.stones) {
      if (stone.ownerPlayerIndex === playerIndex && stone.alive) {
        count += 1;
      }
    }
    return count;
  }

  private async settleResultIfNeeded(): Promise<boolean> {
    const hostAlive = this.getAliveCount(1);
    const guestAlive = this.getAliveCount(2);

    let winnerPlayerIndex: 1 | 2 | null = null;
    let reason = "";
    if (hostAlive <= 0 && guestAlive <= 0) {
      reason = "draw";
    } else if (hostAlive <= 0) {
      winnerPlayerIndex = 2;
      reason = "stone_zero";
    } else if (guestAlive <= 0) {
      winnerPlayerIndex = 1;
      reason = "stone_zero";
    } else {
      return false;
    }

    const fromPhase = this.room.phase;
    this.room.phase = PHASE_RESULT;
    this.room.result = {
      reason,
      winnerPlayerIndex
    };
    this.room.timers.phaseEndsAtMs = undefined;
    this.room.timers.turnEndsAtMs = undefined;
    this.room.match.playing.turnEndsAtMs = null;

    await this.saveState();
    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_RESULT
    });
    this.broadcast("match.result", {
      reason,
      winnerPlayerIndex
    });
    this.broadcastRoomState();
    return true;
  }

  private normalizeSnapshotStones(snapshotStones: MatchPlayingStone[]): MatchPlayingStone[] {
    const byId = new Map<string, MatchPlayingStone>();
    for (const stone of snapshotStones) {
      byId.set(stone.id, stone);
    }

    const normalized: MatchPlayingStone[] = [];
    for (const baseStone of this.room.match.playing.stones) {
      const incoming = byId.get(baseStone.id);
      if (!incoming) {
        normalized.push({
          ...baseStone
        });
      } else {
        const isInside = incoming.x >= 0 && incoming.x <= BOARD_W && incoming.y >= 0 && incoming.y <= BOARD_H;
        normalized.push({
          id: baseStone.id,
          ownerPlayerIndex: baseStone.ownerPlayerIndex,
          x: incoming.x,
          y: incoming.y,
          alive: incoming.alive && isInside
        });
      }
    }
    return normalized;
  }

  private async requestSnapshotFromHost(reason: "shot_committed" | "turn_timeout"): Promise<void> {
    if (this.room.phase !== PHASE_PLAYING) {
      return;
    }
    this.room.match.playing.awaitingSnapshot = true;
    this.room.match.playing.turnEndsAtMs = null;
    this.room.timers.turnEndsAtMs = undefined;

    await this.saveState();
    this.broadcast("match.turn.snapshotRequested", {
      turnIndex: this.room.match.playing.turnIndex,
      reason
    });
    this.broadcastRoomState();
  }

  private async handleTurnShot(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_PLAYING) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }

    const shotPayload = parseShotPayload(payload);
    if (!shotPayload) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }
    if (shotPayload.turnIndex !== this.room.match.playing.turnIndex) {
      this.sendToToken(token, "error.generic", errorPayload("turn_mismatch"));
      return;
    }
    if (session.playerIndex !== this.room.match.playing.activePlayerIndex) {
      this.sendToToken(token, "error.generic", errorPayload("not_your_turn"));
      return;
    }
    if (this.room.match.playing.shotCommitted) {
      this.sendToToken(token, "error.generic", errorPayload("already_shot"));
      return;
    }
    if (this.room.match.playing.awaitingSnapshot) {
      this.sendToToken(token, "error.generic", errorPayload("awaiting_snapshot"));
      return;
    }
    if (shotPayload.power < 0 || shotPayload.power > MAX_SHOT_POWER) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_shot_power"));
      return;
    }

    const dirLength = Math.sqrt(shotPayload.dirX * shotPayload.dirX + shotPayload.dirY * shotPayload.dirY);
    if (!Number.isFinite(dirLength) || dirLength <= 0) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_shot_dir"));
      return;
    }

    const turnEndsAtMs = this.room.match.playing.turnEndsAtMs;
    if (!turnEndsAtMs || Date.now() > turnEndsAtMs) {
      this.sendToToken(token, "error.generic", errorPayload("timeout"));
      return;
    }

    const shotStone = this.room.match.playing.stones.find((stone) => stone.id === shotPayload.stoneId);
    if (!shotStone || !shotStone.alive || shotStone.ownerPlayerIndex !== session.playerIndex) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_shot_stone"));
      return;
    }

    this.room.match.playing.shotCommitted = true;
    await this.saveState();

    this.broadcast("match.turn.shotAccepted", {
      turnIndex: this.room.match.playing.turnIndex,
      playerIndex: session.playerIndex,
      stoneId: shotPayload.stoneId,
      dirX: shotPayload.dirX / dirLength,
      dirY: shotPayload.dirY / dirLength,
      power: shotPayload.power
    });

    await this.requestSnapshotFromHost("shot_committed");
  }

  private async handleTurnSnapshot(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_PLAYING) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }
    if (session.role !== "host") {
      this.sendToToken(token, "error.generic", errorPayload("host_only"));
      return;
    }

    const snapshotPayload = parseSnapshotPayload(payload);
    if (!snapshotPayload) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }
    if (snapshotPayload.turnIndex !== this.room.match.playing.turnIndex) {
      this.sendToToken(token, "error.generic", errorPayload("turn_mismatch"));
      return;
    }
    if (!this.room.match.playing.awaitingSnapshot) {
      this.sendToToken(token, "error.generic", errorPayload("snapshot_not_requested"));
      return;
    }

    this.room.match.playing.stones = this.normalizeSnapshotStones(snapshotPayload.stones);
    this.room.match.playing.awaitingSnapshot = false;

    this.broadcast("match.turn.snapshotApplied", {
      turnIndex: this.room.match.playing.turnIndex,
      stones: clonePlayingStones(this.room.match.playing.stones)
    });

    if (await this.settleResultIfNeeded()) {
      return;
    }

    this.room.match.playing.turnIndex += 1;
    const nextPlayerIndex: 1 | 2 = this.room.match.playing.activePlayerIndex === 1 ? 2 : 1;
    this.startNewTurn(nextPlayerIndex);

    await this.saveState();
    this.broadcastTurnStart();
    this.broadcastRoomState();
    if (this.room.match.playing.turnEndsAtMs) {
      await this.state.storage.setAlarm(this.room.match.playing.turnEndsAtMs);
    }
  }

  private async handleCardPick(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_CARD_SELECT) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }
    if (this.isLockedByRole(session.role)) {
      this.sendToToken(token, "error.generic", errorPayload("already_locked"));
      return;
    }

    const picks = parseCardPickList(payload);
    if (!picks || !this.isValidCardPick(session.role, picks)) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_card_pick"));
      return;
    }

    this.lockCards(session.role, picks, "manual");
    await this.saveState();
    this.broadcastRoomState();
    await this.finalizeCardSelectIfReady();
  }

  private validatePlacementStones(stoneList: StonePlacement[], role: Role): boolean {
    if (stoneList.length !== STONE_COUNT_PER_PLAYER) {
      return false;
    }

    const centerY = BOARD_H * 0.5;
    const minX = STONE_RADIUS;
    const maxX = BOARD_W - STONE_RADIUS;
    const minY = STONE_RADIUS;
    const maxY = BOARD_H - STONE_RADIUS;

    const idSet = new Set<string>();
    for (const stone of stoneList) {
      if (idSet.has(stone.id)) {
        return false;
      }
      idSet.add(stone.id);

      if (stone.x < minX || stone.x > maxX || stone.y < minY || stone.y > maxY) {
        return false;
      }

      if (role === "host" && stone.y < centerY + NO_PLACE_BUFFER) {
        return false;
      }
      if (role === "guest" && stone.y > centerY - NO_PLACE_BUFFER) {
        return false;
      }
    }

    for (let i = 0; i < stoneList.length; i += 1) {
      for (let j = i + 1; j < stoneList.length; j += 1) {
        const dx = stoneList[i].x - stoneList[j].x;
        const dy = stoneList[i].y - stoneList[j].y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        if (distance < MIN_PLACE_DISTANCE) {
          return false;
        }
      }
    }

    return true;
  }

  private async startPlacementReveal(): Promise<void> {
    if (this.room.phase !== PHASE_PLACEMENT_PRIVATE) {
      return;
    }

    const phaseEndsAtMs = Date.now() + PLACEMENT_REVEAL_SEC * 1000;
    const fromPhase = this.room.phase;

    this.room.phase = PHASE_PLACEMENT_REVEAL;
    this.room.timers.phaseEndsAtMs = phaseEndsAtMs;
    this.room.match.placement.revealEndsAtMs = phaseEndsAtMs;

    await this.saveState();

    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_PLACEMENT_REVEAL
    });
    this.broadcast("match.placement.revealStart", {
      endsAtMs: phaseEndsAtMs,
      stones: {
        host: cloneStones(this.room.match.placement.hostStones),
        guest: cloneStones(this.room.match.placement.guestStones)
      }
    });
    this.broadcastRoomState();

    await this.state.storage.setAlarm(phaseEndsAtMs);
  }

  private initializeCardSelectDraft(): void {
    if (this.room.match.cardSelect.hostDealtCards.length > 0 && this.room.match.cardSelect.guestDealtCards.length > 0) {
      return;
    }

    const shuffledPool = shuffleCards([...CARD_POOL]);
    this.room.match.cardSelect.hostDealtCards = shuffledPool.slice(0, HOST_DEAL_COUNT);
    this.room.match.cardSelect.guestDealtCards = shuffledPool.slice(HOST_DEAL_COUNT, HOST_DEAL_COUNT + GUEST_DEAL_COUNT);
    this.room.match.cardSelect.hostPickedCards = [];
    this.room.match.cardSelect.guestPickedCards = [];
    this.room.match.cardSelect.hostLocked = false;
    this.room.match.cardSelect.guestLocked = false;
  }

  private sendCardDealsToConnectedClients(selectEndsAtMs: number): void {
    for (const [token, session] of this.sessions.entries()) {
      this.sendToToken(token, "match.cards.dealt", {
        dealtCards: [...this.getDealtCardsByRole(session.role)],
        pickCount: this.getPickCountByRole(session.role),
        selectEndsAtMs
      });
    }
  }

  private async startCardSelectPhase(): Promise<void> {
    if (this.room.phase !== PHASE_PLACEMENT_REVEAL) {
      return;
    }

    const fromPhase = this.room.phase;
    const selectEndsAtMs = Date.now() + CARD_PICK_SEC * 1000;
    this.room.phase = PHASE_CARD_SELECT;
    this.room.timers.phaseEndsAtMs = selectEndsAtMs;
    this.room.match.cardSelect.selectEndsAtMs = selectEndsAtMs;
    this.initializeCardSelectDraft();

    await this.saveState();

    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_CARD_SELECT
    });
    this.sendCardDealsToConnectedClients(selectEndsAtMs);
    this.broadcastRoomState();
    await this.state.storage.setAlarm(selectEndsAtMs);
  }

  private autoLockMissingCardPicksOnTimeout(): void {
    const roleList: Role[] = ["host", "guest"];
    for (const role of roleList) {
      if (this.isLockedByRole(role)) {
        continue;
      }
      const dealtCards = this.getDealtCardsByRole(role);
      const pickCount = this.getPickCountByRole(role);
      const autoPickedCards = dealtCards.slice(0, pickCount);
      this.lockCards(role, autoPickedCards, "timeout_auto");
    }
  }

  private async processPhaseTimers(nowMs: number): Promise<void> {
    if (this.room.phase === PHASE_PLAYING) {
      const turnEndsAtMs = this.room.timers.turnEndsAtMs;
      if (turnEndsAtMs) {
        if (nowMs < turnEndsAtMs) {
          await this.state.storage.setAlarm(turnEndsAtMs);
          return;
        }
        if (!this.room.match.playing.awaitingSnapshot) {
          await this.requestSnapshotFromHost("turn_timeout");
        }
        return;
      }
    }

    const phaseEndsAtMs = this.room.timers.phaseEndsAtMs;
    if (!phaseEndsAtMs) {
      return;
    }

    if (nowMs < phaseEndsAtMs) {
      await this.state.storage.setAlarm(phaseEndsAtMs);
      return;
    }

    if (this.room.phase === PHASE_PLACEMENT_REVEAL) {
      await this.startCardSelectPhase();
      return;
    }

    if (this.room.phase === PHASE_CARD_SELECT) {
      this.autoLockMissingCardPicksOnTimeout();
      await this.saveState();
      this.broadcastRoomState();
      await this.finalizeCardSelectIfReady();
    }
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

    if (!isGameplayPhase(this.room.phase)) {
      if (role === "host") {
        await this.handleHostDepartureInWaiting(reason);
        return;
      }
      await this.handleGuestDepartureInWaiting(reason);
      return;
    }

    await this.handleDepartureInGameplay(role, reason);
  }

  private async handleHostDepartureInWaiting(reason: LeaveReason): Promise<void> {
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
    this.room.phase = DEFAULT_PHASE as Phase;
    this.room.timers = {};
    this.room.chatLimiter = {};
    await this.saveState();

    this.closeAllSockets("host_left");
  }

  private async handleGuestDepartureInWaiting(reason: LeaveReason): Promise<void> {
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

  private async handleDepartureInGameplay(role: Role, reason: LeaveReason): Promise<void> {
    const playerIndex = this.getPlayerIndex(role);

    this.broadcast("room.left", {
      playerIndex,
      reason
    });

    const token = this.getSlotByRole(role).token;
    if (token) {
      const departingSession = this.sessions.get(token);
      if (departingSession) {
        departingSession.isClosing = true;
        departingSession.socket.close(1000, reason);
        this.sessions.delete(token);
      }
    }

    const slot = this.getSlotByRole(role);
    slot.connected = false;

    const fromPhase = this.room.phase;
    if (this.room.phase !== PHASE_RESULT) {
      const winnerPlayerIndex: 1 | 2 = role === "host" ? 2 : 1;
      this.room.phase = PHASE_RESULT;
      this.room.result = {
        reason: "player_left",
        winnerPlayerIndex,
        leftPlayerIndex: playerIndex
      };
      this.room.timers = {};

      await this.saveState();

      this.broadcast("match.phaseChanged", {
        from: fromPhase,
        to: PHASE_RESULT
      });
      this.broadcast("match.result", {
        reason: "player_left",
        winnerPlayerIndex,
        leftPlayerIndex: playerIndex
      });
      this.broadcastRoomState();
      return;
    }

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
