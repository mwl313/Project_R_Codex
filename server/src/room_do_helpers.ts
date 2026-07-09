import {
  NICKNAME_MAX_LENGTH,
  PHASE_PLACEMENT_REVEAL,
  PHASE_RESULT,
  PHASE_WAITING,
  PHASE_PLAYING
} from "./rules";

export interface StonePlacement {
  id: string;
  x: number;
  y: number;
}

export interface PlayingStoneSnapshot {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  alive: boolean;
}

export interface ObstacleSnapshot {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ParsedShotPayload {
  turnIndex: number;
  stoneId: string;
  dirX: number;
  dirY: number;
  power: number;
}

export interface ParsedSnapshotPayload {
  turnIndex: number;
  stones: PlayingStoneSnapshot[];
}

export interface ParsedCardUsePayload {
  turnIndex: number;
  cardId: string;
  target: { x: number; y: number } | null;
}

export interface ParsedRematchVotePayload {
  action: "rematch" | "to_lobby";
}

export interface ResultStateLike {
  reason: string;
  winnerPlayerIndex: 1 | 2 | null;
  leftPlayerIndex?: 1 | 2;
  hostVote: "rematch" | "to_lobby" | null;
  guestVote: "rematch" | "to_lobby" | null;
}

export function createToken(): string {
  const bytes = new Uint8Array(18);
  crypto.getRandomValues(bytes);
  let result = "";
  for (const value of bytes) {
    result += value.toString(16).padStart(2, "0");
  }
  return result;
}

export function sanitizeNickname(raw: unknown, fallback: string): string {
  if (typeof raw !== "string") {
    return fallback;
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return fallback;
  }
  return trimmed.slice(0, NICKNAME_MAX_LENGTH);
}

export function clonePlacementStones(stoneList: StonePlacement[]): StonePlacement[] {
  return stoneList.map((stone) => ({
    id: stone.id,
    x: stone.x,
    y: stone.y
  }));
}

export function clonePlayingStones(stoneList: PlayingStoneSnapshot[]): PlayingStoneSnapshot[] {
  return stoneList.map((stone) => ({
    id: stone.id,
    ownerPlayerIndex: stone.ownerPlayerIndex,
    x: stone.x,
    y: stone.y,
    alive: stone.alive
  }));
}

export function cloneObstacles(obstacleList: ObstacleSnapshot[]): ObstacleSnapshot[] {
  return obstacleList.map((obstacle) => ({
    id: obstacle.id,
    x: obstacle.x,
    y: obstacle.y,
    width: obstacle.width,
    height: obstacle.height
  }));
}

export function isRevealVisiblePhase(phase: string): boolean {
  return phase === PHASE_PLACEMENT_REVEAL || phase === PHASE_PLAYING || phase === PHASE_RESULT;
}

export function isGameplayPhase(phase: string): boolean {
  return phase !== PHASE_WAITING;
}

export function parsePlacementStones(payload: unknown): StonePlacement[] | null {
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

export function parseCardPickList(payload: unknown): string[] | null {
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

export function parseShotPayload(payload: unknown): ParsedShotPayload | null {
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

export function parseSnapshotPayload(payload: unknown): ParsedSnapshotPayload | null {
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

  const stoneList: PlayingStoneSnapshot[] = [];
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

export function parseCardUsePayload(payload: unknown): ParsedCardUsePayload | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const value = payload as {
    turnIndex?: unknown;
    cardId?: unknown;
    target?: unknown;
  };
  if (typeof value.turnIndex !== "number" || typeof value.cardId !== "string") {
    return null;
  }
  if (!Number.isFinite(value.turnIndex) || value.turnIndex < 1 || Math.floor(value.turnIndex) !== value.turnIndex) {
    return null;
  }
  const cardId = value.cardId.trim();
  if (cardId.length === 0) {
    return null;
  }

  let target: { x: number; y: number } | null = null;
  if (value.target && typeof value.target === "object") {
    const targetValue = value.target as { x?: unknown; y?: unknown };
    if (typeof targetValue.x !== "number" || typeof targetValue.y !== "number") {
      return null;
    }
    if (!Number.isFinite(targetValue.x) || !Number.isFinite(targetValue.y)) {
      return null;
    }
    target = {
      x: targetValue.x,
      y: targetValue.y
    };
  }

  return {
    turnIndex: value.turnIndex,
    cardId,
    target
  };
}

export function parseRematchVotePayload(payload: unknown): ParsedRematchVotePayload | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const value = payload as { action?: unknown };
  if (value.action !== "rematch" && value.action !== "to_lobby") {
    return null;
  }
  return {
    action: value.action
  };
}

export function createResultState(reason: string, winnerPlayerIndex: 1 | 2 | null, leftPlayerIndex?: 1 | 2): ResultStateLike {
  return {
    reason,
    winnerPlayerIndex,
    leftPlayerIndex,
    hostVote: null,
    guestVote: null
  };
}

export function shuffleCards(cardList: string[]): string[] {
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
