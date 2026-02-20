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
  NO_PLACE_BUFFER,
  PHASE_CARD_SELECT,
  PHASE_PLAYING,
  PHASE_PLACEMENT_PRIVATE,
  PHASE_PLACEMENT_REVEAL,
  PHASE_RESULT,
  PHASE_TURN_ORDER,
  PHASE_WAITING,
  PLACEMENT_REVEAL_SEC,
  RULES_VERSION,
  STONE_COUNT_PER_PLAYER,
  STONE_RADIUS,
  SNAPSHOT_TIMEOUT_SEC,
  TURN_TIME_LIMIT_SEC,
  MAX_SHOT_POWER,
  ROCK_OBSTACLE_HEIGHT,
  ROCK_OBSTACLE_MARGIN,
  ROCK_OBSTACLE_WIDTH
} from "./rules";
import { errorPayload, serializeEnvelope, type WsEnvelope } from "./protocol";
import { applyTurnCardAbility } from "./abilities";
import {
  cloneObstacles,
  clonePlacementStones,
  clonePlayingStones,
  createResultState,
  createToken,
  isGameplayPhase,
  isRevealVisiblePhase,
  parseCardPickList,
  parseCardUsePayload,
  parsePlacementStones,
  parseRematchVotePayload,
  parseShotPayload,
  parseSnapshotPayload,
  sanitizeNickname,
  shuffleCards
} from "./room_do_helpers";

const STORAGE_KEY = "room_state_v2";

type LeaveReason = "leave" | "disconnect" | "kick" | "unknown";
type ChatDeniedReason = "rate_limited" | "too_long" | "not_allowed_phase";
type Role = "host" | "guest";
type ResultVoteChoice = "rematch" | "to_lobby";
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

interface MatchObstacle {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface MatchPlayingState {
  turnIndex: number;
  activePlayerIndex: 1 | 2;
  turnEndsAtMs: number | null;
  shotBudget: number;
  shotUsed: number;
  hasCardUsedThisTurn: boolean;
  lockedStoneIds: string[];
  obstacles: MatchObstacle[];
  invincibleTurnByPlayer: {
    1: number | null;
    2: number | null;
  };
  shockwaveOwnerPlayerIndex: 1 | 2 | null;
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

interface ResultState {
  reason: string;
  winnerPlayerIndex: 1 | 2 | null;
  leftPlayerIndex?: 1 | 2;
  hostVote: ResultVoteChoice | null;
  guestVote: ResultVoteChoice | null;
}

interface RoomState {
  roomCode: string | null;
  phase: Phase;
  host: PlayerSlot;
  guest: PlayerSlot;
  guestReady: boolean;
  timers: {
    phaseEndsAtMs?: number;
    turnEndsAtMs?: number;
    snapshotEndsAtMs?: number;
  };
  chatLimiter: Record<string, number[]>;
  isClosed: boolean;
  createdAtMs: number;
  match: MatchState;
  result: ResultState | null;
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
    guestReady: false,
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
        shotBudget: 1,
        shotUsed: 0,
        hasCardUsedThisTurn: false,
        lockedStoneIds: [],
        obstacles: [],
        invincibleTurnByPlayer: {
          1: null,
          2: null
        },
        shockwaveOwnerPlayerIndex: null,
        shotCommitted: false,
        awaitingSnapshot: false,
        stones: []
      }
    },
    result: null
  };
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
    if (typeof this.room.guestReady !== "boolean") {
      this.room.guestReady = false;
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
          shotBudget: 1,
          shotUsed: 0,
          hasCardUsedThisTurn: false,
          lockedStoneIds: [],
          obstacles: [],
          invincibleTurnByPlayer: {
            1: null,
            2: null
          },
          shockwaveOwnerPlayerIndex: null,
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
        shotBudget: 1,
        shotUsed: 0,
        hasCardUsedThisTurn: false,
        lockedStoneIds: [],
        obstacles: [],
        invincibleTurnByPlayer: {
          1: null,
          2: null
        },
        shockwaveOwnerPlayerIndex: null,
        shotCommitted: false,
        awaitingSnapshot: false,
        stones: []
      };
      return;
    }

    if (typeof this.room.match.playing.shotBudget !== "number" || this.room.match.playing.shotBudget < 1) {
      this.room.match.playing.shotBudget = 1;
    }
    if (typeof this.room.match.playing.shotUsed !== "number" || this.room.match.playing.shotUsed < 0) {
      this.room.match.playing.shotUsed = 0;
    }
    if (typeof this.room.match.playing.hasCardUsedThisTurn !== "boolean") {
      this.room.match.playing.hasCardUsedThisTurn = false;
    }
    if (!Array.isArray(this.room.match.playing.lockedStoneIds)) {
      this.room.match.playing.lockedStoneIds = [];
    }
    if (!Array.isArray(this.room.match.playing.obstacles)) {
      this.room.match.playing.obstacles = [];
    } else {
      this.room.match.playing.obstacles = this.room.match.playing.obstacles
        .map((raw) => {
          const obstacle = raw as Partial<MatchObstacle> & { radius?: unknown };
          if (typeof obstacle?.id !== "string" || typeof obstacle?.x !== "number" || typeof obstacle?.y !== "number") {
            return null;
          }

          const width = typeof obstacle.width === "number" ? obstacle.width : ROCK_OBSTACLE_WIDTH;
          const height = typeof obstacle.height === "number" ? obstacle.height : ROCK_OBSTACLE_HEIGHT;
          return {
            id: obstacle.id,
            x: obstacle.x,
            y: obstacle.y,
            width,
            height
          };
        })
        .filter((obstacle): obstacle is MatchObstacle => obstacle !== null);
    }
    if (!this.room.match.playing.invincibleTurnByPlayer) {
      this.room.match.playing.invincibleTurnByPlayer = {
        1: null,
        2: null
      };
    }
    if (this.room.match.playing.invincibleTurnByPlayer[1] !== null && typeof this.room.match.playing.invincibleTurnByPlayer[1] !== "number") {
      this.room.match.playing.invincibleTurnByPlayer[1] = null;
    }
    if (this.room.match.playing.invincibleTurnByPlayer[2] !== null && typeof this.room.match.playing.invincibleTurnByPlayer[2] !== "number") {
      this.room.match.playing.invincibleTurnByPlayer[2] = null;
    }
    if (this.room.match.playing.shockwaveOwnerPlayerIndex !== null && this.room.match.playing.shockwaveOwnerPlayerIndex !== 1 && this.room.match.playing.shockwaveOwnerPlayerIndex !== 2) {
      this.room.match.playing.shockwaveOwnerPlayerIndex = null;
    }
    if (this.room.match.playing.shotUsed > this.room.match.playing.shotBudget) {
      this.room.match.playing.shotUsed = this.room.match.playing.shotBudget;
    }

    if (this.room.result) {
      if (this.room.result.hostVote !== "rematch" && this.room.result.hostVote !== "to_lobby") {
        this.room.result.hostVote = null;
      }
      if (this.room.result.guestVote !== "rematch" && this.room.result.guestVote !== "to_lobby") {
        this.room.result.guestVote = null;
      }
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

  private isFirstTurnRole(role: Role): boolean {
    const firstPlayerIndex = this.room.match.firstPlayerIndex ?? 1;
    return this.getPlayerIndex(role) === firstPlayerIndex;
  }

  private getDealCountByRole(role: Role): number {
    const requestedCount = this.isFirstTurnRole(role) ? HOST_DEAL_COUNT : GUEST_DEAL_COUNT;
    return Math.max(0, Math.floor(requestedCount));
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
    const requestedCount = this.isFirstTurnRole(role) ? HOST_PICK_COUNT : GUEST_PICK_COUNT;
    const safeRequestedCount = Math.max(0, Math.floor(requestedCount));
    const dealtCards = this.getDealtCardsByRole(role);
    if (dealtCards.length > 0) {
      return Math.min(safeRequestedCount, dealtCards.length);
    }
    return Math.min(safeRequestedCount, this.getDealCountByRole(role));
  }

  private getTotalCardPoolCount(): number {
    return CARD_POOL.length;
  }

  private getOpponentDealtCountByRole(role: Role): number {
    return this.getDealtCardsByRole(role === "host" ? "guest" : "host").length;
  }

  private getResultVoteByRole(role: Role): ResultVoteChoice | null {
    if (!this.room.result) {
      return null;
    }
    return role === "host" ? this.room.result.hostVote : this.room.result.guestVote;
  }

  private setResultVoteByRole(role: Role, vote: ResultVoteChoice): void {
    if (!this.room.result) {
      return;
    }
    if (role === "host") {
      this.room.result.hostVote = vote;
      return;
    }
    this.room.result.guestVote = vote;
  }

  private createPlayingEntityId(prefix: string): string {
    return `${prefix}_${createToken().slice(0, 10)}`;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private intersectsStoneAndObstacle(stoneX: number, stoneY: number, obstacle: MatchObstacle): boolean {
    const halfW = obstacle.width * 0.5;
    const halfH = obstacle.height * 0.5;
    const left = obstacle.x - halfW;
    const right = obstacle.x + halfW;
    const top = obstacle.y - halfH;
    const bottom = obstacle.y + halfH;

    const closestX = this.clamp(stoneX, left, right);
    const closestY = this.clamp(stoneY, top, bottom);
    const dx = stoneX - closestX;
    const dy = stoneY - closestY;
    return dx * dx + dy * dy < STONE_RADIUS * STONE_RADIUS;
  }

  private intersectsObstacleAndObstacle(x: number, y: number, width: number, height: number, other: MatchObstacle): boolean {
    const halfW = width * 0.5;
    const halfH = height * 0.5;
    const otherHalfW = other.width * 0.5;
    const otherHalfH = other.height * 0.5;
    return Math.abs(x - other.x) < halfW + otherHalfW && Math.abs(y - other.y) < halfH + otherHalfH;
  }

  private canPlaceStoneAt(x: number, y: number, minDistance: number): boolean {
    const minX = STONE_RADIUS;
    const maxX = BOARD_W - STONE_RADIUS;
    const minY = STONE_RADIUS;
    const maxY = BOARD_H - STONE_RADIUS;
    if (x < minX || x > maxX || y < minY || y > maxY) {
      return false;
    }

    for (const stone of this.room.match.playing.stones) {
      if (!stone.alive) {
        continue;
      }
      const dx = stone.x - x;
      const dy = stone.y - y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (distance < minDistance) {
        return false;
      }
    }

    for (const obstacle of this.room.match.playing.obstacles) {
      if (this.intersectsStoneAndObstacle(x, y, obstacle)) {
        return false;
      }
    }
    return true;
  }

  private canPlaceObstacleAt(x: number, y: number, width: number, height: number, margin = ROCK_OBSTACLE_MARGIN): boolean {
    const halfW = width * 0.5;
    const halfH = height * 0.5;
    const left = x - halfW;
    const right = x + halfW;
    const top = y - halfH;
    const bottom = y + halfH;

    if (left < margin || right > BOARD_W - margin || top < margin || bottom > BOARD_H - margin) {
      return false;
    }

    for (const obstacle of this.room.match.playing.obstacles) {
      if (this.intersectsObstacleAndObstacle(x, y, width, height, obstacle)) {
        return false;
      }
    }

    for (const stone of this.room.match.playing.stones) {
      if (!stone.alive) {
        continue;
      }
      if (this.intersectsStoneAndObstacle(stone.x, stone.y, { id: "__tmp", x, y, width, height })) {
        return false;
      }
    }
    return true;
  }

  private removePickedCardByRole(role: Role, cardId: string): void {
    const pickedCards = this.getPickedCardsByRole(role).filter((value) => value !== cardId);
    this.setPickedCardsByRole(role, pickedCards);
  }

  private buildRoomStatePayload(role: Role): Record<string, unknown> {
    const myStones = clonePlacementStones(this.getStonesByRole(role));
    const mySubmitted = this.getSubmittedByRole(role);
    const opponentSubmitted = this.getSubmittedByRole(role === "host" ? "guest" : "host");
    const revealStones = isRevealVisiblePhase(this.room.phase)
      ? {
          host: clonePlacementStones(this.room.match.placement.hostStones),
          guest: clonePlacementStones(this.room.match.placement.guestStones)
        }
      : null;

    return {
      rulesVersion: RULES_VERSION,
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
      guestReady: this.room.guestReady,
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
          myDealtCount: this.getDealtCardsByRole(role).length,
          opponentDealtCount: this.getOpponentDealtCountByRole(role),
          totalPoolCount: this.getTotalCardPoolCount(),
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
          shotBudget: this.room.match.playing.shotBudget,
          shotUsed: this.room.match.playing.shotUsed,
          hasCardUsedThisTurn: this.room.match.playing.hasCardUsedThisTurn,
          lockedStoneIds: [...this.room.match.playing.lockedStoneIds],
          obstacles: cloneObstacles(this.room.match.playing.obstacles),
          invincibleTurnByPlayer: {
            1: this.room.match.playing.invincibleTurnByPlayer[1],
            2: this.room.match.playing.invincibleTurnByPlayer[2]
          },
          shockwaveOwnerPlayerIndex: this.room.match.playing.shockwaveOwnerPlayerIndex,
          shotCommitted: this.room.match.playing.shotCommitted,
          awaitingSnapshot: this.room.match.playing.awaitingSnapshot,
          stones: clonePlayingStones(this.room.match.playing.stones)
        }
      },
      result: this.room.result
        ? {
            ...this.room.result,
            myVote: this.getResultVoteByRole(role),
            opponentVote: this.getResultVoteByRole(role === "host" ? "guest" : "host")
          }
        : null
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

  private getRoleByPlayerIndex(playerIndex: 1 | 2): Role {
    return playerIndex === 1 ? "host" : "guest";
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
      guestReady: false,
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
          shotBudget: 1,
          shotUsed: 0,
          hasCardUsedThisTurn: false,
          lockedStoneIds: [],
          obstacles: [],
          invincibleTurnByPlayer: {
            1: null,
            2: null
          },
          shockwaveOwnerPlayerIndex: null,
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
    this.room.guestReady = false;

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
      rulesVersion: RULES_VERSION,
      roomCode: this.room.roomCode,
      role,
      playerIndex
    });
    this.broadcastRoomState();
    if (this.room.phase === PHASE_CARD_SELECT && this.room.match.cardSelect.selectEndsAtMs) {
      this.sendToSocket(socket, "match.cards.dealt", {
        dealtCards: [...this.getDealtCardsByRole(role)],
        pickCount: this.getPickCountByRole(role),
        myDealtCount: this.getDealtCardsByRole(role).length,
        opponentDealtCount: this.getOpponentDealtCountByRole(role),
        totalPoolCount: this.getTotalCardPoolCount(),
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

  private resetMatchStateForNewRound(): void {
    this.room.result = null;
    this.room.guestReady = false;
    this.room.match.firstPlayerIndex = null;

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
    this.room.match.playing.shotBudget = 1;
    this.room.match.playing.shotUsed = 0;
    this.room.match.playing.hasCardUsedThisTurn = false;
    this.room.match.playing.lockedStoneIds = [];
    this.room.match.playing.obstacles = [];
    this.room.match.playing.invincibleTurnByPlayer = {
      1: null,
      2: null
    };
    this.room.match.playing.shockwaveOwnerPlayerIndex = null;
    this.room.match.playing.shotCommitted = false;
    this.room.match.playing.awaitingSnapshot = false;
    this.room.match.playing.stones = [];
  }

  private async startMatchFlow(): Promise<void> {
    if (this.room.phase !== PHASE_WAITING) {
      return;
    }
    if (!this.room.host.connected || !this.room.guest.connected) {
      return;
    }
    if (!this.room.guestReady) {
      return;
    }

    this.resetMatchStateForNewRound();

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
    if (envelope.type === "client.room.ready") {
      await this.handleGuestReady(token, session);
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
    if (envelope.type === "client.match.turn.cardUse") {
      await this.handleTurnCardUse(token, session, envelope.payload);
      return;
    }
    if (envelope.type === "client.match.surrender") {
      await this.handleSurrender(token, session);
      return;
    }
    if (envelope.type === "client.match.rematch.vote") {
      await this.handleResultVote(token, session, envelope.payload);
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
    if (!this.room.guestReady) {
      this.sendToToken(token, "error.generic", errorPayload("guest_not_ready"));
      return;
    }

    await this.startMatchFlow();
  }

  private async handleGuestReady(token: string, session: Session): Promise<void> {
    if (this.room.phase !== PHASE_WAITING) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }
    if (session.role !== "guest") {
      this.sendToToken(token, "error.generic", errorPayload("guest_only"));
      return;
    }

    const slot = this.getSlotByRole("guest");
    if (!slot.token || slot.token !== token) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_token"));
      return;
    }
    if (!slot.connected || !this.room.host.connected) {
      this.sendToToken(token, "error.generic", errorPayload("player_not_ready"));
      return;
    }
    if (this.room.guestReady) {
      this.sendToToken(token, "error.generic", errorPayload("already_ready"));
      return;
    }

    this.room.guestReady = true;
    await this.saveState();
    this.broadcast("room.ready", {
      playerIndex: 2,
      nickname: slot.nickname ?? "Guest",
      ready: true
    });
    this.broadcastRoomState();
  }

  private async handleSurrender(token: string, session: Session): Promise<void> {
    const slot = this.getSlotByRole(session.role);
    if (!slot.token || slot.token !== token) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_token"));
      return;
    }
    if (!isGameplayPhase(this.room.phase) || this.room.phase === PHASE_RESULT) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }

    const surrenderPlayerIndex = session.playerIndex;
    const winnerPlayerIndex: 1 | 2 = surrenderPlayerIndex === 1 ? 2 : 1;
    const fromPhase = this.room.phase;

    this.room.phase = PHASE_RESULT;
    this.room.result = createResultState("surrender", winnerPlayerIndex, surrenderPlayerIndex);
    this.room.timers.phaseEndsAtMs = undefined;
    this.room.timers.turnEndsAtMs = undefined;
    this.room.timers.snapshotEndsAtMs = undefined;
    this.room.match.playing.turnEndsAtMs = null;
    this.room.match.playing.awaitingSnapshot = false;
    this.room.match.playing.shotCommitted = false;

    await this.saveState();
    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_RESULT
    });
    this.broadcast("match.result", {
      reason: "surrender",
      winnerPlayerIndex,
      surrenderPlayerIndex
    });
    this.broadcastRoomState();
  }

  private async handleResultVote(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_RESULT || !this.room.result) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }
    const slot = this.getSlotByRole(session.role);
    if (!slot.token || slot.token !== token) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_token"));
      return;
    }

    const votePayload = parseRematchVotePayload(payload);
    if (!votePayload) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }

    this.setResultVoteByRole(session.role, votePayload.action);

    if (votePayload.action === "to_lobby") {
      await this.saveState();
      this.broadcast("room.closed", {
        reason: "result_to_lobby",
        byPlayerIndex: session.playerIndex
      });

      this.room.host = createEmptySlot();
      this.room.guest = createEmptySlot();
      this.room.isClosed = true;
      this.room.phase = DEFAULT_PHASE as Phase;
      this.room.timers = {};
      this.room.chatLimiter = {};
      await this.saveState();
      this.closeAllSockets("result_to_lobby");
      return;
    }

    await this.saveState();
    this.broadcastRoomState();

    if (this.room.result.hostVote === "rematch" && this.room.result.guestVote === "rematch") {
      const fromPhase = this.room.phase;
      this.room.phase = PHASE_WAITING;
      this.room.timers = {};
      this.resetMatchStateForNewRound();

      await this.saveState();
      this.broadcast("match.phaseChanged", {
        from: fromPhase,
        to: PHASE_WAITING
      });
      this.broadcastRoomState();
    }
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

    this.setStonesByRole(session.role, clonePlacementStones(stoneList));
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
    this.room.match.playing.shotBudget = 1;
    this.room.match.playing.shotUsed = 0;
    this.room.match.playing.hasCardUsedThisTurn = false;
    this.room.match.playing.lockedStoneIds = [];
    this.room.match.playing.shockwaveOwnerPlayerIndex = null;
    this.room.match.playing.shotCommitted = false;
    this.room.match.playing.awaitingSnapshot = false;
    this.room.timers.turnEndsAtMs = turnEndsAtMs;
    this.room.timers.snapshotEndsAtMs = undefined;
  }

  private broadcastTurnStart(): void {
    this.broadcast("match.turn.start", {
      turnIndex: this.room.match.playing.turnIndex,
      activePlayerIndex: this.room.match.playing.activePlayerIndex,
      turnEndsAtMs: this.room.match.playing.turnEndsAtMs,
      shotBudget: this.room.match.playing.shotBudget,
      shotUsed: this.room.match.playing.shotUsed,
      hasCardUsedThisTurn: this.room.match.playing.hasCardUsedThisTurn
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
    this.room.result = createResultState(reason, winnerPlayerIndex);
    this.room.timers.phaseEndsAtMs = undefined;
    this.room.timers.turnEndsAtMs = undefined;
    this.room.timers.snapshotEndsAtMs = undefined;
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
        const minX = STONE_RADIUS;
        const maxX = BOARD_W - STONE_RADIUS;
        const minY = STONE_RADIUS;
        const maxY = BOARD_H - STONE_RADIUS;
        const isInside = incoming.x >= minX && incoming.x <= maxX && incoming.y >= minY && incoming.y <= maxY;
        normalized.push({
          id: baseStone.id,
          ownerPlayerIndex: baseStone.ownerPlayerIndex,
          x: this.clamp(incoming.x, minX, maxX),
          y: this.clamp(incoming.y, minY, maxY),
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
    const snapshotEndsAtMs = Date.now() + SNAPSHOT_TIMEOUT_SEC * 1000;
    this.room.match.playing.awaitingSnapshot = true;
    this.room.match.playing.turnEndsAtMs = null;
    this.room.timers.turnEndsAtMs = undefined;
    this.room.timers.snapshotEndsAtMs = snapshotEndsAtMs;

    await this.saveState();
    this.broadcast("match.turn.snapshotRequested", {
      turnIndex: this.room.match.playing.turnIndex,
      reason,
      snapshotEndsAtMs
    });
    this.broadcastRoomState();
    await this.state.storage.setAlarm(snapshotEndsAtMs);
  }

  private async handleSnapshotTimeout(): Promise<void> {
    if (this.room.phase !== PHASE_PLAYING || !this.room.match.playing.awaitingSnapshot) {
      return;
    }

    const fromPhase = this.room.phase;
    const timedOutPlayerIndex: 1 | 2 = 1; // host is authoritative snapshot owner
    const winnerPlayerIndex: 1 | 2 = 2;

    this.room.phase = PHASE_RESULT;
    this.room.result = createResultState("snapshot_timeout", winnerPlayerIndex, timedOutPlayerIndex);
    this.room.match.playing.awaitingSnapshot = false;
    this.room.match.playing.turnEndsAtMs = null;
    this.room.timers.phaseEndsAtMs = undefined;
    this.room.timers.turnEndsAtMs = undefined;
    this.room.timers.snapshotEndsAtMs = undefined;

    await this.saveState();
    this.broadcast("match.phaseChanged", {
      from: fromPhase,
      to: PHASE_RESULT
    });
    this.broadcast("match.result", {
      reason: "snapshot_timeout",
      winnerPlayerIndex,
      timedOutPlayerIndex
    });
    this.broadcastRoomState();
  }

  private async handleTurnCardUse(token: string, session: Session, payload: unknown): Promise<void> {
    if (this.room.phase !== PHASE_PLAYING) {
      this.sendToToken(token, "error.generic", errorPayload("not_in_phase"));
      return;
    }

    const cardUsePayload = parseCardUsePayload(payload);
    if (!cardUsePayload) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_payload"));
      return;
    }
    if (cardUsePayload.turnIndex !== this.room.match.playing.turnIndex) {
      this.sendToToken(token, "error.generic", errorPayload("turn_mismatch"));
      return;
    }
    if (session.playerIndex !== this.room.match.playing.activePlayerIndex) {
      this.sendToToken(token, "error.generic", errorPayload("not_your_turn"));
      return;
    }
    if (this.room.match.playing.awaitingSnapshot) {
      this.sendToToken(token, "error.generic", errorPayload("awaiting_snapshot"));
      return;
    }
    const turnEndsAtMs = this.room.match.playing.turnEndsAtMs;
    if (!turnEndsAtMs || Date.now() > turnEndsAtMs) {
      this.sendToToken(token, "error.generic", errorPayload("timeout"));
      return;
    }
    if (this.room.match.playing.hasCardUsedThisTurn) {
      this.sendToToken(token, "error.generic", errorPayload("card_already_used"));
      return;
    }
    if (this.room.match.playing.shotUsed > 0) {
      this.sendToToken(token, "error.generic", errorPayload("card_use_window_closed"));
      return;
    }
    if (!(CARD_POOL as readonly string[]).includes(cardUsePayload.cardId)) {
      this.sendToToken(token, "error.generic", errorPayload("invalid_card_id"));
      return;
    }

    const pickedCards = this.getPickedCardsByRole(session.role);
    if (!pickedCards.includes(cardUsePayload.cardId)) {
      this.sendToToken(token, "error.generic", errorPayload("card_not_owned"));
      return;
    }

    const abilityResult = applyTurnCardAbility({
      payload: cardUsePayload,
      playerIndex: session.playerIndex,
      playing: this.room.match.playing,
      createPlayingEntityId: (prefix) => this.createPlayingEntityId(prefix),
      canPlaceStoneAt: (x, y, minDistance) => this.canPlaceStoneAt(x, y, minDistance),
      canPlaceObstacleAt: (x, y, width, height, margin) => this.canPlaceObstacleAt(x, y, width, height, margin)
    });
    if (!abilityResult.ok || !abilityResult.appliedCardId) {
      this.sendToToken(token, "error.generic", errorPayload(abilityResult.errorCode ?? "card_not_implemented"));
      return;
    }
    const effectPayload = abilityResult.effectPayload;

    this.room.match.playing.hasCardUsedThisTurn = true;
    this.removePickedCardByRole(session.role, abilityResult.appliedCardId);

    await this.saveState();
    this.broadcast("match.turn.cardCue", {
      turnIndex: this.room.match.playing.turnIndex,
      playerIndex: session.playerIndex,
      cardId: abilityResult.appliedCardId,
      target: cardUsePayload.target
    });
    this.broadcast("match.turn.cardApplied", {
      turnIndex: this.room.match.playing.turnIndex,
      playerIndex: session.playerIndex,
      cardId: abilityResult.appliedCardId,
      effect: effectPayload
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
    if (this.room.match.playing.shotUsed >= this.room.match.playing.shotBudget) {
      this.sendToToken(token, "error.generic", errorPayload("shot_budget_exceeded"));
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
    if (this.room.match.playing.lockedStoneIds.includes(shotPayload.stoneId)) {
      this.sendToToken(token, "error.generic", errorPayload("stone_locked_this_turn"));
      return;
    }

    this.room.match.playing.shotUsed += 1;
    this.room.match.playing.shotCommitted = this.room.match.playing.shotUsed >= this.room.match.playing.shotBudget;
    await this.saveState();

    this.broadcast("match.turn.shotAccepted", {
      turnIndex: this.room.match.playing.turnIndex,
      playerIndex: session.playerIndex,
      stoneId: shotPayload.stoneId,
      dirX: shotPayload.dirX / dirLength,
      dirY: shotPayload.dirY / dirLength,
      power: shotPayload.power,
      shotUsed: this.room.match.playing.shotUsed,
      shotBudget: this.room.match.playing.shotBudget
    });

    if (this.room.match.playing.shotCommitted) {
      await this.requestSnapshotFromHost("shot_committed");
      return;
    }

    this.broadcastRoomState();
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
    this.room.timers.snapshotEndsAtMs = undefined;

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
        host: clonePlacementStones(this.room.match.placement.hostStones),
        guest: clonePlacementStones(this.room.match.placement.guestStones)
      }
    });
    this.broadcastRoomState();

    await this.state.storage.setAlarm(phaseEndsAtMs);
  }

  private initializeCardSelectDraft(): void {
    if (this.room.match.cardSelect.hostDealtCards.length > 0 && this.room.match.cardSelect.guestDealtCards.length > 0) {
      return;
    }

    const firstPlayerRole = this.getRoleByPlayerIndex(this.room.match.firstPlayerIndex ?? 1);
    const secondPlayerRole: Role = firstPlayerRole === "host" ? "guest" : "host";
    let firstDealCount = this.getDealCountByRole(firstPlayerRole);
    let secondDealCount = this.getDealCountByRole(secondPlayerRole);
    const totalPoolCount = this.getTotalCardPoolCount();
    if (firstDealCount + secondDealCount > totalPoolCount) {
      secondDealCount = Math.max(0, totalPoolCount - firstDealCount);
      if (firstDealCount + secondDealCount > totalPoolCount) {
        firstDealCount = Math.max(0, totalPoolCount - secondDealCount);
      }
    }

    const shuffledPool = shuffleCards([...CARD_POOL]);
    const firstDealCards = shuffledPool.slice(0, firstDealCount);
    const secondDealCards = shuffledPool.slice(firstDealCount, firstDealCount + secondDealCount);

    if (firstPlayerRole === "host") {
      this.room.match.cardSelect.hostDealtCards = firstDealCards;
      this.room.match.cardSelect.guestDealtCards = secondDealCards;
    } else {
      this.room.match.cardSelect.hostDealtCards = secondDealCards;
      this.room.match.cardSelect.guestDealtCards = firstDealCards;
    }
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
        myDealtCount: this.getDealtCardsByRole(session.role).length,
        opponentDealtCount: this.getOpponentDealtCountByRole(session.role),
        totalPoolCount: this.getTotalCardPoolCount(),
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
      if (this.room.match.playing.awaitingSnapshot) {
        let snapshotEndsAtMs = this.room.timers.snapshotEndsAtMs;
        if (!snapshotEndsAtMs) {
          snapshotEndsAtMs = nowMs + SNAPSHOT_TIMEOUT_SEC * 1000;
          this.room.timers.snapshotEndsAtMs = snapshotEndsAtMs;
          await this.saveState();
        }
        if (nowMs < snapshotEndsAtMs) {
          await this.state.storage.setAlarm(snapshotEndsAtMs);
          return;
        }
        await this.handleSnapshotTimeout();
        return;
      }

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
    this.room.guestReady = false;
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
    this.room.guestReady = false;
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
      this.room.result = createResultState("player_left", winnerPlayerIndex, playerIndex);
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
