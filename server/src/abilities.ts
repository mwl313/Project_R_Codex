import { CARD_POOL } from "./rules";
import { CARD_RULES, isTurnCardEnabled } from "./card_rules";

export interface AbilityTargetPoint {
  x: number;
  y: number;
}

export interface AbilityCardUsePayload {
  turnIndex: number;
  cardId: string;
  target: AbilityTargetPoint | null;
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
}

export interface AbilityApplyContext {
  payload: AbilityCardUsePayload;
  playerIndex: 1 | 2;
  playing: AbilityPlayingState;
  createPlayingEntityId: (prefix: string) => string;
  canPlaceStoneAt: (x: number, y: number, minDistance: number) => boolean;
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

export function isSupportedCardId(cardId: string): boolean {
  return CARD_SET.has(cardId) && isTurnCardEnabled(cardId);
}

const AGILE_HANDLER: AbilityHandler = (context, effectPayload) => {
  const shotBudget = Math.max(1, Math.floor(CARD_RULES.cards.agile.shot_budget));
  context.playing.shotBudget = Math.max(context.playing.shotBudget, shotBudget);
  effectPayload.shotBudget = context.playing.shotBudget;
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const REINFORCEMENT_HANDLER: AbilityHandler = (context, effectPayload) => {
  const reinforcementRule = CARD_RULES.cards.reinforcement;
  const target = context.payload.target;
  if (!target) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }
  const minPlaceDistance = Math.max(1, reinforcementRule.min_place_distance);
  if (!context.canPlaceStoneAt(target.x, target.y, minPlaceDistance)) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }

  const newStone: AbilityPlayingStone = {
    id: context.createPlayingEntityId(`p${context.playerIndex}_r`),
    ownerPlayerIndex: context.playerIndex,
    x: target.x,
    y: target.y,
    alive: true
  };
  context.playing.stones.push(newStone);
  if (reinforcementRule.lock_spawned_stone_for_turn) {
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
  return {
    ok: true,
    appliedCardId: context.payload.cardId,
    effectPayload
  };
};

const ROCKFALL_HANDLER: AbilityHandler = (context, effectPayload) => {
  const rockfallRule = CARD_RULES.cards.rockfall;
  const target = context.payload.target;
  if (!target) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
  }
  const obstacleWidth = Math.max(1, rockfallRule.width);
  const obstacleHeight = Math.max(1, rockfallRule.height);
  const obstacleMargin = Math.max(0, rockfallRule.margin);
  if (!context.canPlaceObstacleAt(target.x, target.y, obstacleWidth, obstacleHeight, obstacleMargin)) {
    return {
      ok: false,
      errorCode: "invalid_card_target",
      effectPayload: {}
    };
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
  const turnOffset = Math.max(1, Math.floor(CARD_RULES.cards.invincible.protect_after_turn_offset));
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

const CARD_ABILITY_HANDLER_BY_ID: Record<string, AbilityHandler> = {
  agile: AGILE_HANDLER,
  reinforcement: REINFORCEMENT_HANDLER,
  rockfall: ROCKFALL_HANDLER,
  invincible: INVINCIBLE_HANDLER,
  shockwave: SHOCKWAVE_HANDLER
};

export function applyTurnCardAbility(context: AbilityApplyContext): AbilityApplyResult {
  const cardId = context.payload.cardId;
  if (!isSupportedCardId(cardId)) {
    return {
      ok: false,
      errorCode: "invalid_card_id",
      effectPayload: {}
    };
  }

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
