import { BOARD_H, BOARD_W, CARD_POOL, STONE_RADIUS } from "./rules";
import { CARD_RULES, isTurnCardEnabled } from "./card_rules";

export interface AbilityTargetPoint {
  x: number;
  y: number;
}

export interface AbilityCardUsePayload {
  turnIndex: number;
  cardId: string;
  target: AbilityTargetPoint | null;
  sourceStoneId: string | null;
  targetStoneId: string | null;
}

export interface AbilityPlayingStone {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  alive: boolean;
}

export interface AbilityObstacle {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface AbilityStoneStatus {
  ghostUntilTurn: number | null;
  isGhost: boolean;
  invisibleToOpponentUntilTurn: number | null;
  isInvisibleToOpponent: boolean;
  boundUntilTurn: number | null;
  powerMoveCharges: number;
  powerMoveUntilTurn: number | null;
  nongaeUntilTurn: number | null;
  isNongae: boolean;
  spawnLockedThisTurn: boolean;
}

export interface AbilityPlayerStatus {
  abilitySealUntilTurn: number | null;
  reverseUntilTurn: number | null;
  cannotUseAbilityUntilTurn: number | null;
  suddenDeathEndTurn: number | null;
  drawOneRandomCardPerTurnUntilTurn: number | null;
  nextShotPowerMultiplier: number;
  pendingNongaeUntilTurn: number | null;
  reversalRewardPending: boolean;
  reversalRewardCount: number;
  quickFinishActive: boolean;
  quickFinishActivationTurn: number | null;
  quickFinishDeadlineTurn: number | null;
  quickFinishCardsPerTurn: number;
}

export interface AbilityIceZone {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  radius: number;
  dampingMultiplier: number;
  expiresAtTurn: number;
}

export interface AbilityBoardEffects {
  iceZones: AbilityIceZone[];
  bombs: AbilityBombEffect[];
  blackholeEffects: AbilityBlackholeEffect[];
}

export interface AbilityTurnHistory {
  lastOpponentTurnDeaths: string[];
  spawnPositionByStoneId: Record<string, { x: number; y: number }>;
}

export interface AbilityBombEffect {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  explodeAtTurn: number;
  radius: number;
  impulse: number;
}

export interface AbilityBlackholeEffect {
  id: string;
  ownerPlayerIndex: 1 | 2;
  x: number;
  y: number;
  radius: number;
  durationMs: number;
  accelPxPerSec2: number;
  createdAtMs: number;
}

export interface AbilityPlayingState {
  turnIndex: number;
  personalTurnCountByPlayer: {
    1: number;
    2: number;
  };
  shotBudget: number;
  lockedStoneIds: string[];
  obstacles: AbilityObstacle[];
  invincibleTurnByPlayer: {
    1: number | null;
    2: number | null;
  };
  shockwaveOwnerPlayerIndex: 1 | 2 | null;
  stones: AbilityPlayingStone[];
  stoneStatusById: Record<string, AbilityStoneStatus>;
  playerStatusByIndex: {
    1: AbilityPlayerStatus;
    2: AbilityPlayerStatus;
  };
  boardEffects: AbilityBoardEffects;
  turnHistory: AbilityTurnHistory;
}

export interface AbilityApplyContext {
  payload: AbilityCardUsePayload;
  playerIndex: 1 | 2;
  playing: AbilityPlayingState;
  currentHandCount: number;
  currentPersonalTurnCount: number;
  createPlayingEntityId: (prefix: string) => string;
  canPlaceStoneAt: (x: number, y: number, minDistance: number) => boolean;
  canPlaceStoneAtExcludingStone: (excludeStoneId: string, x: number, y: number, minDistance: number) => boolean;
  canPlaceObstacleAt: (x: number, y: number, width: number, height: number, margin: number) => boolean;
}

export interface AbilityApplyResult {
  ok: boolean;
  errorCode?: string;
  appliedCardId?: string;
  effectPayload: Record<string, unknown>;
}

const CARD_SET = new Set<string>(CARD_POOL as readonly string[]);
type AbilityHandler = (context: AbilityApplyContext, effectPayload: Record<string, unknown>) => AbilityApplyResult;
const DEBUG_ABILITY_LOG = false;

function getCardRule(cardId: string) {
  const fallback = CARD_RULES.cards.agile;
  return CARD_RULES.cards[cardId] ?? fallback;
}

function readTunablesNumber(cardId: string, key: string, fallback: number): number {
  const rule = getCardRule(cardId);
  const tunables = typeof rule.tunables === "object" && rule.tunables ? (rule.tunables as Record<string, unknown>) : {};
  const raw = tunables[key] ?? (rule as Record<string, unknown>)[key];
  return typeof raw === "number" && Number.isFinite(raw) ? raw : fallback;
}

function readTunablesBoolean(cardId: string, key: string, fallback: boolean): boolean {
  const rule = getCardRule(cardId);
  const tunables = typeof rule.tunables === "object" && rule.tunables ? (rule.tunables as Record<string, unknown>) : {};
  const raw = tunables[key] ?? (rule as Record<string, unknown>)[key];
  return typeof raw === "boolean" ? raw : fallback;
}

function clampNumber(value: number, minValue: number, maxValue: number): number {
  if (value < minValue) {
    return minValue;
  }
  if (value > maxValue) {
    return maxValue;
  }
  return value;
}

function getDefaultStoneStatus(): AbilityStoneStatus {
  return {
    ghostUntilTurn: null,
    isGhost: false,
    invisibleToOpponentUntilTurn: null,
    isInvisibleToOpponent: false,
    boundUntilTurn: null,
    powerMoveCharges: 0,
    powerMoveUntilTurn: null,
    nongaeUntilTurn: null,
    isNongae: false,
    spawnLockedThisTurn: false
  };
}

function getDefaultPlayerStatus(): AbilityPlayerStatus {
  return {
    abilitySealUntilTurn: null,
    reverseUntilTurn: null,
    cannotUseAbilityUntilTurn: null,
    suddenDeathEndTurn: null,
    drawOneRandomCardPerTurnUntilTurn: null,
    nextShotPowerMultiplier: 1,
    pendingNongaeUntilTurn: null,
    reversalRewardPending: false,
    reversalRewardCount: 0,
    quickFinishActive: false,
    quickFinishActivationTurn: null,
    quickFinishDeadlineTurn: null,
    quickFinishCardsPerTurn: 0
  };
}

function ensureStatusContainers(playing: AbilityPlayingState): void {
  if (!playing.stoneStatusById || typeof playing.stoneStatusById !== "object") {
    playing.stoneStatusById = {};
  }
  if (!playing.playerStatusByIndex || typeof playing.playerStatusByIndex !== "object") {
    playing.playerStatusByIndex = {
      1: getDefaultPlayerStatus(),
      2: getDefaultPlayerStatus()
    };
  }
  if (!playing.playerStatusByIndex[1]) {
    playing.playerStatusByIndex[1] = getDefaultPlayerStatus();
  }
  if (!playing.playerStatusByIndex[2]) {
    playing.playerStatusByIndex[2] = getDefaultPlayerStatus();
  }
  if (!playing.boardEffects || typeof playing.boardEffects !== "object") {
    playing.boardEffects = {
      iceZones: [],
      bombs: [],
      blackholeEffects: []
    };
  }
  if (!Array.isArray(playing.boardEffects.iceZones)) {
    playing.boardEffects.iceZones = [];
  }
  if (!Array.isArray(playing.boardEffects.bombs)) {
    playing.boardEffects.bombs = [];
  }
  if (!Array.isArray(playing.boardEffects.blackholeEffects)) {
    playing.boardEffects.blackholeEffects = [];
  }
  if (!playing.turnHistory || typeof playing.turnHistory !== "object") {
    playing.turnHistory = {
      lastOpponentTurnDeaths: [],
      spawnPositionByStoneId: {}
    };
  }
  if (!Array.isArray(playing.turnHistory.lastOpponentTurnDeaths)) {
    playing.turnHistory.lastOpponentTurnDeaths = [];
  }
  if (!playing.turnHistory.spawnPositionByStoneId || typeof playing.turnHistory.spawnPositionByStoneId !== "object") {
    playing.turnHistory.spawnPositionByStoneId = {};
  }
}

function getStoneById(playing: AbilityPlayingState, stoneId: string | null): AbilityPlayingStone | null {
  if (!stoneId) {
    return null;
  }
  for (const stone of playing.stones) {
    if (stone.id === stoneId) {
      return stone;
    }
  }
  return null;
}

function getStoneStatus(playing: AbilityPlayingState, stoneId: string): AbilityStoneStatus {
  ensureStatusContainers(playing);
  const existing = playing.stoneStatusById[stoneId];
  if (existing) {
    return existing;
  }
  const next = getDefaultStoneStatus();
  playing.stoneStatusById[stoneId] = next;
  return next;
}

function getPlayerStatus(playing: AbilityPlayingState, playerIndex: 1 | 2): AbilityPlayerStatus {
  ensureStatusContainers(playing);
  return playing.playerStatusByIndex[playerIndex];
}

function logAbilityDebug(message: string, payload?: Record<string, unknown>): void {
  if (!DEBUG_ABILITY_LOG) {
    return;
  }
  if (payload) {
    console.log(`[ability] ${message}`, payload);
    return;
  }
  console.log(`[ability] ${message}`);
}

function isPointInsideBoard(x: number, y: number): boolean {
  return x >= 0 && x <= BOARD_W && y >= 0 && y <= BOARD_H;
}

function isStoneBound(playing: AbilityPlayingState, stoneId: string): boolean {
  const stoneStatus = getStoneStatus(playing, stoneId);
  return typeof stoneStatus.boundUntilTurn === "number" && stoneStatus.boundUntilTurn >= playing.turnIndex;
}

function buildStoneStatusPatch(playing: AbilityPlayingState, stoneIdList: string[]): Record<string, AbilityStoneStatus> {
  const patch: Record<string, AbilityStoneStatus> = {};
  for (const stoneId of stoneIdList) {
    patch[stoneId] = { ...getStoneStatus(playing, stoneId) };
  }
  return patch;
}

function buildPlayerStatusPatch(playing: AbilityPlayingState): AbilityPlayingState["playerStatusByIndex"] {
  return {
    1: { ...getPlayerStatus(playing, 1) },
    2: { ...getPlayerStatus(playing, 2) }
  };
}

function isStoneOverlappingObstacle(x: number, y: number, obstacle: AbilityObstacle): boolean {
  const halfW = (obstacle.width || 0) * 0.5;
  const halfH = (obstacle.height || 0) * 0.5;
  const left = obstacle.x - halfW;
  const right = obstacle.x + halfW;
  const top = obstacle.y - halfH;
  const bottom = obstacle.y + halfH;
  const closestX = Math.max(left, Math.min(right, x));
  const closestY = Math.max(top, Math.min(bottom, y));
  const dx = x - closestX;
  const dy = y - closestY;
  return dx * dx + dy * dy < STONE_RADIUS * STONE_RADIUS;
}

function findFallbackRebirthPosition(
  context: AbilityApplyContext,
  anchorX: number,
  anchorY: number,
  minDistance: number
): { x: number; y: number } | null {
  if (context.canPlaceStoneAt(anchorX, anchorY, minDistance)) {
    return { x: anchorX, y: anchorY };
  }
  const radiusStep = 18;
  const maxRadius = 180;
  for (let radius = radiusStep; radius <= maxRadius; radius += radiusStep) {
    const sampleCount = Math.max(8, Math.floor((Math.PI * 2 * radius) / 24));
    for (let index = 0; index < sampleCount; index += 1) {
      const theta = (Math.PI * 2 * index) / sampleCount;
      const candidateX = anchorX + Math.cos(theta) * radius;
      const candidateY = anchorY + Math.sin(theta) * radius;
      if (context.canPlaceStoneAt(candidateX, candidateY, minDistance)) {
        return { x: candidateX, y: candidateY };
      }
    }
  }
  return null;
}

function tryGenerateValidRepositionSet(
  context: AbilityApplyContext,
  stoneList: AbilityPlayingStone[],
  minDistance: number
): Array<{ id: string; x: number; y: number }> | null {
  const placed: Array<{ id: string; x: number; y: number }> = [];
  const minX = STONE_RADIUS;
  const maxX = BOARD_W - STONE_RADIUS;
  const minY = STONE_RADIUS;
  const maxY = BOARD_H - STONE_RADIUS;

  const isValid = (x: number, y: number): boolean => {
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return false;
    }
    if (x < minX || x > maxX || y < minY || y > maxY) {
      return false;
    }
    for (const obstacle of context.playing.obstacles) {
      if (isStoneOverlappingObstacle(x, y, obstacle)) {
        return false;
      }
    }
    for (const other of placed) {
      const dx = other.x - x;
      const dy = other.y - y;
      if (Math.sqrt(dx * dx + dy * dy) < minDistance) {
        return false;
      }
    }
    return true;
  };

  for (const stone of stoneList) {
    let found: { x: number; y: number } | null = null;
    for (let tries = 0; tries < 250; tries += 1) {
      const candidateX = minX + Math.random() * (maxX - minX);
      const candidateY = minY + Math.random() * (maxY - minY);
      if (isValid(candidateX, candidateY)) {
        found = { x: candidateX, y: candidateY };
        break;
      }
    }
    if (!found) {
      return null;
    }
    placed.push({
      id: stone.id,
      x: found.x,
      y: found.y
    });
  }

  return placed;
}

const AGILE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const shotBudget = Math.max(1, Math.floor(readTunablesNumber("agile", "shot_budget", 2)));
  context.playing.shotBudget = Math.max(context.playing.shotBudget, shotBudget);
  effectPayload.shotBudget = context.playing.shotBudget;
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const REINFORCEMENT_HANDLER: AbilityHandler = (context, effectPayload) => {
  const target = context.payload.target;
  if (!target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const minPlaceDistance = Math.max(1, readTunablesNumber("reinforcement", "min_place_distance", 19));
  if (!context.canPlaceStoneAt(target.x, target.y, minPlaceDistance)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const newStone: AbilityPlayingStone = {
    id: context.createPlayingEntityId(`p${context.playerIndex}_r`),
    ownerPlayerIndex: context.playerIndex,
    x: target.x,
    y: target.y,
    alive: true
  };
  context.playing.stones.push(newStone);
  if (!context.playing.turnHistory.spawnPositionByStoneId || typeof context.playing.turnHistory.spawnPositionByStoneId !== "object") {
    context.playing.turnHistory.spawnPositionByStoneId = {};
  }
  context.playing.turnHistory.spawnPositionByStoneId[newStone.id] = {
    x: newStone.x,
    y: newStone.y
  };
  getStoneStatus(context.playing, newStone.id).spawnLockedThisTurn = true;
  if (readTunablesBoolean("reinforcement", "lock_spawned_stone_for_turn", true)) {
    context.playing.lockedStoneIds.push(newStone.id);
  }

  effectPayload.spawnStone = {
    id: newStone.id,
    ownerPlayerIndex: newStone.ownerPlayerIndex,
    x: newStone.x,
    y: newStone.y,
    alive: true
  };
  effectPayload.lockedStoneIds = [...context.playing.lockedStoneIds];
  effectPayload.stoneStatusById = buildStoneStatusPatch(context.playing, [newStone.id]);
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const ROCKFALL_HANDLER: AbilityHandler = (context, effectPayload) => {
  const target = context.payload.target;
  if (!target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const obstacleWidth = Math.max(1, readTunablesNumber("rockfall", "width", 100));
  const obstacleHeight = Math.max(1, readTunablesNumber("rockfall", "height", 50));
  const obstacleMargin = Math.max(0, readTunablesNumber("rockfall", "margin", 5));
  if (!context.canPlaceObstacleAt(target.x, target.y, obstacleWidth, obstacleHeight, obstacleMargin)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const newObstacle: AbilityObstacle = {
    id: context.createPlayingEntityId("rock"),
    x: target.x,
    y: target.y,
    width: obstacleWidth,
    height: obstacleHeight
  };
  context.playing.obstacles.push(newObstacle);
  effectPayload.obstacle = {
    id: newObstacle.id,
    x: newObstacle.x,
    y: newObstacle.y,
    width: newObstacle.width,
    height: newObstacle.height
  };
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const INVINCIBLE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const turnOffset = Math.max(1, Math.floor(readTunablesNumber("invincible", "protect_after_turn_offset", 1)));
  context.playing.invincibleTurnByPlayer[context.playerIndex] = context.playing.turnIndex + turnOffset;
  effectPayload.invincibleTurnByPlayer = {
    1: context.playing.invincibleTurnByPlayer[1],
    2: context.playing.invincibleTurnByPlayer[2]
  };
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const SHOCKWAVE_HANDLER: AbilityHandler = (context, effectPayload) => {
  context.playing.shockwaveOwnerPlayerIndex = context.playerIndex;
  effectPayload.shockwaveOwnerPlayerIndex = context.playerIndex;
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const POWER_MOVE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const playerStatus = getPlayerStatus(context.playing, context.playerIndex);
  playerStatus.nextShotPowerMultiplier = clampNumber(readTunablesNumber("power_move", "power_multiplier", 1.25), 1, 2);
  effectPayload.playerStatusByIndex = buildPlayerStatusPatch(context.playing);
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const SEAL_HANDLER: AbilityHandler = (context, effectPayload) => {
  const durationTurns = Math.max(1, Math.floor(readTunablesNumber("seal", "duration_turns", 2)));
  const opponentIndex: 1 | 2 = context.playerIndex === 1 ? 2 : 1;
  const opponentStatus = getPlayerStatus(context.playing, opponentIndex);
  opponentStatus.abilitySealUntilTurn = context.playing.turnIndex + durationTurns;
  effectPayload.playerStatusByIndex = buildPlayerStatusPatch(context.playing);
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const BIND_HANDLER: AbilityHandler = (context, effectPayload) => {
  const targetStoneId = context.payload.targetStoneId;
  const targetStone = getStoneById(context.playing, targetStoneId);
  if (!targetStone || targetStone.alive === false) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  if (targetStone.ownerPlayerIndex === context.playerIndex) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const durationTurns = Math.max(1, Math.floor(readTunablesNumber("bind", "duration_turns", 3)));
  const stoneStatus = getStoneStatus(context.playing, targetStone.id);
  stoneStatus.boundUntilTurn = context.playing.turnIndex + durationTurns;
  effectPayload.stoneStatusById = buildStoneStatusPatch(context.playing, [targetStone.id]);
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const ICE_FIELD_HANDLER: AbilityHandler = (context, effectPayload) => {
  const target = context.payload.target;
  if (!target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  if (!isPointInsideBoard(target.x, target.y)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const radius = Math.max(20, readTunablesNumber("ice_field", "zone_radius", 110));
  if (target.x - radius < 0 || target.x + radius > BOARD_W || target.y - radius < 0 || target.y + radius > BOARD_H) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const durationTurns = Math.max(1, Math.floor(readTunablesNumber("ice_field", "duration_turns", 2)));
  const dampingMultiplier = clampNumber(readTunablesNumber("ice_field", "damping_multiplier", 0.45), 0.05, 1);
  const zone: AbilityIceZone = {
    id: context.createPlayingEntityId("ice"),
    ownerPlayerIndex: context.playerIndex,
    x: target.x,
    y: target.y,
    radius,
    dampingMultiplier,
    expiresAtTurn: context.playing.turnIndex + durationTurns
  };
  ensureStatusContainers(context.playing);
  context.playing.boardEffects.iceZones.push(zone);
  effectPayload.iceZoneAdded = { ...zone };
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const BLINK_HANDLER: AbilityHandler = (context, effectPayload) => {
  const sourceStone = getStoneById(context.playing, context.payload.sourceStoneId);
  const target = context.payload.target;
  if (!sourceStone || sourceStone.alive === false || sourceStone.ownerPlayerIndex !== context.playerIndex || !target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  if (isStoneBound(context.playing, sourceStone.id)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const maxBlinkDistance = Math.max(1, readTunablesNumber("blink", "max_blink_distance", 170));
  const dx = target.x - sourceStone.x;
  const dy = target.y - sourceStone.y;
  const distance = Math.sqrt(dx * dx + dy * dy);
  if (!Number.isFinite(distance) || distance > maxBlinkDistance) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  const minDistance = Math.max(1, readTunablesNumber("blink", "min_place_distance", STONE_RADIUS * 2));
  if (!context.canPlaceStoneAtExcludingStone(sourceStone.id, target.x, target.y, minDistance)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  sourceStone.x = target.x;
  sourceStone.y = target.y;
  effectPayload.movedStones = [
    {
      id: sourceStone.id,
      x: sourceStone.x,
      y: sourceStone.y,
      resetVelocity: true
    }
  ];
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const SWAP_HANDLER: AbilityHandler = (context, effectPayload) => {
  const firstStone = getStoneById(context.playing, context.payload.sourceStoneId);
  const secondStone = getStoneById(context.playing, context.payload.targetStoneId);
  if (!firstStone || !secondStone || firstStone.alive === false || secondStone.alive === false) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  if (firstStone.ownerPlayerIndex !== context.playerIndex || secondStone.ownerPlayerIndex === context.playerIndex) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }

  const firstX = firstStone.x;
  const firstY = firstStone.y;
  firstStone.x = secondStone.x;
  firstStone.y = secondStone.y;
  secondStone.x = firstX;
  secondStone.y = firstY;

  effectPayload.movedStones = [
    { id: firstStone.id, x: firstStone.x, y: firstStone.y, resetVelocity: true },
    { id: secondStone.id, x: secondStone.x, y: secondStone.y, resetVelocity: true }
  ];
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const GHOST_HANDLER: AbilityHandler = (context, effectPayload) => {
  const durationTurns = Math.max(1, Math.floor(readTunablesNumber("ghost", "duration_turns", 1)));
  const affectedStoneIds: string[] = [];
  for (const stone of context.playing.stones) {
    if (stone.ownerPlayerIndex !== context.playerIndex) {
      continue;
    }
    const stoneStatus = getStoneStatus(context.playing, stone.id);
    stoneStatus.ghostUntilTurn = context.playing.turnIndex + durationTurns;
    stoneStatus.isGhost = true;
    affectedStoneIds.push(stone.id);
  }
  effectPayload.stoneStatusById = buildStoneStatusPatch(context.playing, affectedStoneIds);
  logAbilityDebug("ghost_applied", { playerIndex: context.playerIndex, count: affectedStoneIds.length });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const STEALTH_HANDLER: AbilityHandler = (context, effectPayload) => {
  const durationTurns = Math.max(1, Math.floor(readTunablesNumber("stealth", "duration_turns", 1)));
  const affectedStoneIds: string[] = [];
  for (const stone of context.playing.stones) {
    if (stone.ownerPlayerIndex !== context.playerIndex) {
      continue;
    }
    const stoneStatus = getStoneStatus(context.playing, stone.id);
    stoneStatus.invisibleToOpponentUntilTurn = context.playing.turnIndex + durationTurns;
    stoneStatus.isInvisibleToOpponent = true;
    affectedStoneIds.push(stone.id);
  }
  effectPayload.stoneStatusById = buildStoneStatusPatch(context.playing, affectedStoneIds);
  logAbilityDebug("stealth_applied", { playerIndex: context.playerIndex, count: affectedStoneIds.length });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const REBIRTH_HANDLER: AbilityHandler = (context, effectPayload) => {
  ensureStatusContainers(context.playing);
  const history = context.playing.turnHistory;
  const deathStoneIdList = Array.isArray(history.lastOpponentTurnDeaths) ? history.lastOpponentTurnDeaths : [];
  if (deathStoneIdList.length <= 0) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }

  const spawnMap = history.spawnPositionByStoneId || {};
  const minDistance = Math.max(1, readTunablesNumber("rebirth", "min_place_distance", STONE_RADIUS * 2));
  const movedStones: Array<{ id: string; x: number; y: number; resetVelocity: boolean }> = [];
  const patchedStoneIds: string[] = [];

  for (const stoneId of deathStoneIdList) {
    const stone = getStoneById(context.playing, stoneId);
    if (!stone || stone.ownerPlayerIndex !== context.playerIndex || stone.alive) {
      continue;
    }
    const spawn = spawnMap[stoneId];
    const anchorX = spawn && typeof spawn.x === "number" ? spawn.x : stone.x;
    const anchorY = spawn && typeof spawn.y === "number" ? spawn.y : stone.y;
    const fallback = findFallbackRebirthPosition(context, anchorX, anchorY, minDistance);
    if (!fallback) {
      continue;
    }
    stone.x = fallback.x;
    stone.y = fallback.y;
    stone.alive = true;
    const stoneStatus = getStoneStatus(context.playing, stone.id);
    stoneStatus.boundUntilTurn = null;
    stoneStatus.spawnLockedThisTurn = false;
    patchedStoneIds.push(stone.id);
    movedStones.push({
      id: stone.id,
      x: stone.x,
      y: stone.y,
      resetVelocity: true
    });
  }

  if (movedStones.length <= 0) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }

  effectPayload.movedStones = movedStones;
  effectPayload.stoneStatusById = buildStoneStatusPatch(context.playing, patchedStoneIds);
  logAbilityDebug("rebirth_applied", { playerIndex: context.playerIndex, revivedCount: movedStones.length });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const REPOSITION_HANDLER: AbilityHandler = (context, effectPayload) => {
  const aliveStoneList = context.playing.stones.filter((stone) => stone.alive);
  if (aliveStoneList.length <= 0) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }
  const minDistance = Math.max(1, readTunablesNumber("reposition", "min_place_distance", STONE_RADIUS * 2));
  let nextPositions: Array<{ id: string; x: number; y: number }> | null = null;
  for (let attempt = 0; attempt < 8; attempt += 1) {
    nextPositions = tryGenerateValidRepositionSet(context, aliveStoneList, minDistance);
    if (nextPositions) {
      break;
    }
  }
  if (!nextPositions) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }

  const movedStones: Array<{ id: string; x: number; y: number; resetVelocity: boolean }> = [];
  const byId = new Map<string, { x: number; y: number }>();
  for (const position of nextPositions) {
    byId.set(position.id, position);
  }
  for (const stone of aliveStoneList) {
    const next = byId.get(stone.id);
    if (!next) {
      continue;
    }
    stone.x = next.x;
    stone.y = next.y;
    movedStones.push({
      id: stone.id,
      x: stone.x,
      y: stone.y,
      resetVelocity: true
    });
  }
  effectPayload.movedStones = movedStones;
  logAbilityDebug("reposition_applied", { movedCount: movedStones.length });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const BLACKHOLE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const target = context.payload.target;
  if (!target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  if (!isPointInsideBoard(target.x, target.y)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  const radius = Math.max(20, readTunablesNumber("blackhole", "radius_px", 130));
  if (target.x - radius < 0 || target.x + radius > BOARD_W || target.y - radius < 0 || target.y + radius > BOARD_H) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  const durationMs = Math.max(100, Math.floor(readTunablesNumber("blackhole", "duration_ms", 650)));
  const accelPxPerSec2 = Math.max(1, readTunablesNumber("blackhole", "accel_px_per_sec2", 220));
  const effect: AbilityBlackholeEffect = {
    id: context.createPlayingEntityId("blackhole"),
    ownerPlayerIndex: context.playerIndex,
    x: target.x,
    y: target.y,
    radius,
    durationMs,
    accelPxPerSec2,
    createdAtMs: Date.now()
  };
  context.playing.boardEffects.blackholeEffects.push(effect);
  effectPayload.blackholeEffectAdded = { ...effect };
  logAbilityDebug("blackhole_applied", { playerIndex: context.playerIndex, id: effect.id });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const EXPLOSIVE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const target = context.payload.target;
  if (!target) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  const minDistance = Math.max(1, readTunablesNumber("explosive", "min_place_distance", STONE_RADIUS * 2));
  if (!context.canPlaceStoneAt(target.x, target.y, minDistance)) {
    return { ok: false, errorCode: "invalid_card_target", effectPayload: {} };
  }
  const delayTurns = Math.max(1, Math.floor(readTunablesNumber("explosive", "delay_turns", 7)));
  const radius = Math.max(20, readTunablesNumber("explosive", "radius_px", 120));
  const impulse = Math.max(1, readTunablesNumber("explosive", "impulse_px_per_sec", 650));
  const bomb: AbilityBombEffect = {
    id: context.createPlayingEntityId("bomb"),
    ownerPlayerIndex: context.playerIndex,
    x: target.x,
    y: target.y,
    explodeAtTurn: context.playing.turnIndex + delayTurns,
    radius,
    impulse
  };
  context.playing.boardEffects.bombs.push(bomb);
  effectPayload.bombAdded = { ...bomb };
  logAbilityDebug("explosive_applied", { playerIndex: context.playerIndex, id: bomb.id, explodeAtTurn: bomb.explodeAtTurn });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const NONGAE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const playerStatus = getPlayerStatus(context.playing, context.playerIndex);
  if (typeof playerStatus.pendingNongaeUntilTurn === "number" && playerStatus.pendingNongaeUntilTurn >= context.playing.turnIndex) {
    return { ok: false, errorCode: "nongae_already_armed", effectPayload: {} };
  }
  playerStatus.pendingNongaeUntilTurn = context.playing.turnIndex;
  effectPayload.playerStatusByIndex = buildPlayerStatusPatch(context.playing);
  logAbilityDebug("nongae_armed", {
    playerIndex: context.playerIndex,
    turnIndex: context.playing.turnIndex
  });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const REVERSAL_HANDLER: AbilityHandler = (context, effectPayload) => {
  const playerStatus = getPlayerStatus(context.playing, context.playerIndex);
  if (playerStatus.reversalRewardPending === true
    || (typeof playerStatus.cannotUseAbilityUntilTurn === "number" && playerStatus.cannotUseAbilityUntilTurn >= context.playing.turnIndex)
  ) {
    return { ok: false, errorCode: "reversal_active", effectPayload: {} };
  }

  const lockTurns = Math.max(1, Math.floor(readTunablesNumber("reversal", "lockTurns", 10)));
  const rewardMultiplier = Math.max(0, readTunablesNumber("reversal", "rewardMultiplier", 2));
  const snapshotHandCount = Math.max(0, Math.floor(context.currentHandCount));
  const rewardCount = Math.max(0, Math.floor(snapshotHandCount * rewardMultiplier));
  const untilTurn = context.playing.turnIndex + lockTurns;

  playerStatus.reverseUntilTurn = untilTurn;
  playerStatus.cannotUseAbilityUntilTurn = untilTurn;
  playerStatus.reversalRewardPending = true;
  playerStatus.reversalRewardCount = rewardCount;
  effectPayload.playerStatusByIndex = buildPlayerStatusPatch(context.playing);
  effectPayload.reversalSnapshotHandCount = snapshotHandCount;
  effectPayload.reversalRewardCount = rewardCount;
  logAbilityDebug("reversal_applied", {
    playerIndex: context.playerIndex,
    lockTurns,
    rewardCount
  });

  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const QUICK_FINISH_HANDLER: AbilityHandler = (context, effectPayload) => {
  const playerStatus = getPlayerStatus(context.playing, context.playerIndex);
  if (playerStatus.quickFinishActive === true) {
    return { ok: false, errorCode: "quick_finish_already_active", effectPayload: {} };
  }
  if (context.currentPersonalTurnCount !== 1) {
    return { ok: false, errorCode: "quick_finish_first_turn_only", effectPayload: {} };
  }

  const deadlineTurns = Math.max(1, Math.floor(readTunablesNumber("quick_finish", "deadlineTurns", 7)));
  const cardsPerTurn = Math.max(1, Math.floor(readTunablesNumber("quick_finish", "cardsPerTurnAfterActivation", 1)));
  const deadlineTurn = context.playing.turnIndex + (deadlineTurns - 1);
  playerStatus.quickFinishActive = true;
  playerStatus.quickFinishActivationTurn = context.playing.turnIndex;
  playerStatus.quickFinishDeadlineTurn = deadlineTurn;
  playerStatus.quickFinishCardsPerTurn = cardsPerTurn;
  playerStatus.suddenDeathEndTurn = deadlineTurn;
  playerStatus.drawOneRandomCardPerTurnUntilTurn = deadlineTurn;
  effectPayload.playerStatusByIndex = buildPlayerStatusPatch(context.playing);
  effectPayload.quickFinishDiscardAllCards = true;
  effectPayload.quickFinishDeadlineTurn = deadlineTurn;
  effectPayload.quickFinishCardsPerTurn = cardsPerTurn;
  logAbilityDebug("quick_finish_applied", {
    playerIndex: context.playerIndex,
    deadlineTurn,
    cardsPerTurn
  });
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const BUFF_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  agile: AGILE_HANDLER,
  invincible: INVINCIBLE_HANDLER,
  shockwave: SHOCKWAVE_HANDLER,
  power_move: POWER_MOVE_HANDLER,
  seal: SEAL_HANDLER,
  ghost: GHOST_HANDLER,
  rebirth: REBIRTH_HANDLER,
  reposition: REPOSITION_HANDLER,
  stealth: STEALTH_HANDLER,
  nongae: NONGAE_HANDLER,
  reversal: REVERSAL_HANDLER,
  quick_finish: QUICK_FINISH_HANDLER
};

const TARGETED_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  reinforcement: REINFORCEMENT_HANDLER,
  rockfall: ROCKFALL_HANDLER,
  bind: BIND_HANDLER,
  ice_field: ICE_FIELD_HANDLER,
  blink: BLINK_HANDLER,
  swap: SWAP_HANDLER,
  blackhole: BLACKHOLE_HANDLER,
  explosive: EXPLOSIVE_HANDLER
};

const CARD_ABILITY_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  ...BUFF_HANDLER_BY_ID,
  ...TARGETED_HANDLER_BY_ID
};

export function isSupportedCardId(cardId: string): boolean {
  return CARD_SET.has(cardId) && isTurnCardEnabled(cardId);
}

export function applyTurnCardAbility(context: AbilityApplyContext): AbilityApplyResult {
  const cardId = context.payload.cardId;
  if (!isSupportedCardId(cardId)) {
    return {
      ok: false,
      errorCode: "invalid_card_id",
      effectPayload: {}
    };
  }

  ensureStatusContainers(context.playing);

  const handler = CARD_ABILITY_HANDLER_BY_ID[cardId];
  if (typeof handler !== "function") {
    return {
      ok: false,
      errorCode: "card_not_implemented",
      effectPayload: {}
    };
  }

  const effectPayload: Record<string, unknown> = {};
  return handler(context, effectPayload);
}
