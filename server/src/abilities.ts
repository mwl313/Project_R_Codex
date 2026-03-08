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
  bombs: Array<Record<string, unknown>>;
  blackholeEffects: Array<Record<string, unknown>>;
}

export interface AbilityTurnHistory {
  lastOpponentTurnDeaths: string[];
}

export interface AbilityPlayingState {
  turnIndex: number;
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
    nextShotPowerMultiplier: 1
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
      lastOpponentTurnDeaths: []
    };
  }
  if (!Array.isArray(playing.turnHistory.lastOpponentTurnDeaths)) {
    playing.turnHistory.lastOpponentTurnDeaths = [];
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

const BUFF_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  agile: AGILE_HANDLER,
  invincible: INVINCIBLE_HANDLER,
  shockwave: SHOCKWAVE_HANDLER,
  power_move: POWER_MOVE_HANDLER,
  seal: SEAL_HANDLER
};

const TARGETED_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  reinforcement: REINFORCEMENT_HANDLER,
  rockfall: ROCKFALL_HANDLER,
  bind: BIND_HANDLER,
  ice_field: ICE_FIELD_HANDLER,
  blink: BLINK_HANDLER,
  swap: SWAP_HANDLER
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
