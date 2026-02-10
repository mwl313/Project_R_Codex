import {
  CARD_POOL,
  MIN_PLACE_DISTANCE,
  ROCK_OBSTACLE_HEIGHT,
  ROCK_OBSTACLE_WIDTH
} from "./rules";

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
  canPlaceObstacleAt: (x: number, y: number, width: number, height: number) => boolean;
}

export interface AbilityApplyResult {
  ok: boolean;
  errorCode?: string;
  appliedCardId?: string;
  effectPayload: Record<string, unknown>;
}

const CARD_SET = new Set<string>(CARD_POOL as readonly string[]);

export function isSupportedCardId(cardId: string): boolean {
  return CARD_SET.has(cardId);
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

  const effectPayload: Record<string, unknown> = {};
  const playing = context.playing;

  if (cardId === "agile") {
    // Agile: allow one extra shot this turn by extending shot budget to 2.
    playing.shotBudget = Math.max(playing.shotBudget, 2);
    effectPayload.shotBudget = playing.shotBudget;
    return {
      ok: true,
      appliedCardId: cardId,
      effectPayload
    };
  }

  if (cardId === "reinforcement") {
    // Reinforcement: spawn one friendly stone at valid target, locked for this turn.
    const target = context.payload.target;
    if (!target) {
      return {
        ok: false,
        errorCode: "invalid_card_target",
        effectPayload: {}
      };
    }
    if (!context.canPlaceStoneAt(target.x, target.y, MIN_PLACE_DISTANCE)) {
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
    playing.stones.push(newStone);
    playing.lockedStoneIds.push(newStone.id);
    effectPayload.spawnStone = {
      id: newStone.id,
      ownerPlayerIndex: newStone.ownerPlayerIndex,
      x: newStone.x,
      y: newStone.y,
      alive: true
    };
    effectPayload.lockedStoneIds = [...playing.lockedStoneIds];
    return {
      ok: true,
      appliedCardId: cardId,
      effectPayload
    };
  }

  if (cardId === "rockfall") {
    // Rockfall: spawn one obstacle at valid target.
    const target = context.payload.target;
    if (!target) {
      return {
        ok: false,
        errorCode: "invalid_card_target",
        effectPayload: {}
      };
    }
    if (!context.canPlaceObstacleAt(target.x, target.y, ROCK_OBSTACLE_WIDTH, ROCK_OBSTACLE_HEIGHT)) {
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
      width: ROCK_OBSTACLE_WIDTH,
      height: ROCK_OBSTACLE_HEIGHT
    };
    playing.obstacles.push(newObstacle);
    effectPayload.obstacle = {
      id: newObstacle.id,
      x: newObstacle.x,
      y: newObstacle.y,
      width: newObstacle.width,
      height: newObstacle.height
    };
    return {
      ok: true,
      appliedCardId: cardId,
      effectPayload
    };
  }

  if (cardId === "invincible") {
    // Invincible: protect friendly stones from displacement on next turn.
    playing.invincibleTurnByPlayer[context.playerIndex] = playing.turnIndex + 1;
    effectPayload.invincibleTurnByPlayer = {
      1: playing.invincibleTurnByPlayer[1],
      2: playing.invincibleTurnByPlayer[2]
    };
    return {
      ok: true,
      appliedCardId: cardId,
      effectPayload
    };
  }

  if (cardId === "shockwave") {
    // Shockwave: mark current turn owner as shockwave-enabled shooter.
    playing.shockwaveOwnerPlayerIndex = context.playerIndex;
    effectPayload.shockwaveOwnerPlayerIndex = context.playerIndex;
    return {
      ok: true,
      appliedCardId: cardId,
      effectPayload
    };
  }

  return {
    ok: false,
    errorCode: "card_not_implemented",
    effectPayload: {}
  };
}
