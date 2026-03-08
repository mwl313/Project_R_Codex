import sharedCardRulesJson from "../../shared/card_rules.json";

export const CARD_MODE_SINGLE_ONLY = "SINGLE_ONLY" as const;
export const CARD_MODE_MULTI_OK = "MULTI_OK" as const;
export type CardMode = typeof CARD_MODE_SINGLE_ONLY | typeof CARD_MODE_MULTI_OK;
export const TARGET_MODE_NONE = "NONE" as const;
export const TARGET_MODE_POINT = "POINT" as const;
export type TargetMode = typeof TARGET_MODE_NONE | typeof TARGET_MODE_POINT;

export const GAME_MODE_SINGLE = "SINGLE" as const;
export const GAME_MODE_MULTI = "MULTI" as const;
export type GameMode = typeof GAME_MODE_SINGLE | typeof GAME_MODE_MULTI;

const ALLOW_MISSING_MODE_AS_MULTI = false;
const STRICT_SCHEMA_IN_DEV = true;

interface BaseCardRule {
  id: string;
  mode: CardMode;
  enabled: boolean;
  tags: string[];
  tunables: Record<string, unknown>;
  [key: string]: unknown;
}

interface ReinforcementCardRule extends BaseCardRule {
  min_place_distance: number;
  lock_spawned_stone_for_turn: boolean;
}

interface ShockwaveCardRule extends BaseCardRule {
  radius_multiplier: number;
  strength: number;
  exclude_source_stone: boolean;
  ignore_invincible_targets: boolean;
}

interface InvincibleCardRule extends BaseCardRule {
  protect_after_turn_offset: number;
}

interface RockfallCardRule extends BaseCardRule {
  width: number;
  height: number;
  margin: number;
}

interface AgileCardRule extends BaseCardRule {
  shot_budget: number;
}

interface CardRules {
  version: number;
  card_order: string[];
  cards: Record<string, BaseCardRule> & {
    reinforcement: ReinforcementCardRule;
    shockwave: ShockwaveCardRule;
    invincible: InvincibleCardRule;
    rockfall: RockfallCardRule;
    agile: AgileCardRule;
  };
}

const DEFAULT_CARD_RULES: CardRules = {
  version: 1,
  card_order: ["reinforcement", "shockwave", "invincible", "rockfall", "agile"],
  cards: {
    reinforcement: {
      id: "reinforcement",
      mode: CARD_MODE_MULTI_OK,
      enabled: true,
      tags: ["UTILITY", "TRICK"],
      tunables: {
        min_place_distance: 19,
        lock_spawned_stone_for_turn: true
      },
      min_place_distance: 19,
      lock_spawned_stone_for_turn: true
    },
    shockwave: {
      id: "shockwave",
      mode: CARD_MODE_MULTI_OK,
      enabled: true,
      tags: ["OFFENSE", "CONTROL"],
      tunables: {
        radius_multiplier: 4,
        strength: 200,
        exclude_source_stone: true,
        ignore_invincible_targets: true
      },
      radius_multiplier: 4,
      strength: 200,
      exclude_source_stone: true,
      ignore_invincible_targets: true
    },
    invincible: {
      id: "invincible",
      mode: CARD_MODE_MULTI_OK,
      enabled: true,
      tags: ["DEFENSE", "UTILITY"],
      tunables: {
        protect_after_turn_offset: 1
      },
      protect_after_turn_offset: 1
    },
    rockfall: {
      id: "rockfall",
      mode: CARD_MODE_MULTI_OK,
      enabled: true,
      tags: ["OBSTACLE", "CONTROL"],
      tunables: {
        width: 100,
        height: 50,
        margin: 5
      },
      width: 100,
      height: 50,
      margin: 5
    },
    agile: {
      id: "agile",
      mode: CARD_MODE_MULTI_OK,
      enabled: true,
      tags: ["OFFENSE", "TRICK"],
      tunables: {
        shot_budget: 2
      },
      shot_budget: 2
    }
  }
};

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function readNumber(source: Record<string, unknown>, key: string, fallback: number): number {
  const value = source[key];
  return isFiniteNumber(value) ? value : fallback;
}

function readBoolean(source: Record<string, unknown>, key: string, fallback: boolean): boolean {
  const value = source[key];
  return typeof value === "boolean" ? value : fallback;
}

function readObject(source: unknown): Record<string, unknown> {
  if (!source || typeof source !== "object") {
    return {};
  }
  return source as Record<string, unknown>;
}

function readStringListValue(value: unknown, fallback: string[]): string[] {
  if (!Array.isArray(value)) {
    return [...fallback];
  }

  const sanitized: string[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== "string") {
      continue;
    }
    const normalized = entry.trim();
    if (normalized.length === 0 || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    sanitized.push(normalized);
  }

  if (sanitized.length <= 0) {
    return [...fallback];
  }
  return sanitized;
}

function isDevelopment(): boolean {
  const processRef = (globalThis as { process?: { env?: { NODE_ENV?: string } } }).process;
  return processRef?.env?.NODE_ENV !== "production";
}

function reportSchemaError(message: string): void {
  if (STRICT_SCHEMA_IN_DEV && isDevelopment()) {
    throw new Error(`[card_rules] schema error: ${message}`);
  }
  console.warn(`[card_rules] schema warning: ${message}`);
}

function normalizeMode(rawMode: unknown, cardId: string): CardMode {
  if (rawMode === CARD_MODE_SINGLE_ONLY || rawMode === CARD_MODE_MULTI_OK) {
    return rawMode;
  }
  if (ALLOW_MISSING_MODE_AS_MULTI) {
    return CARD_MODE_MULTI_OK;
  }
  reportSchemaError(`missing_or_invalid_mode:${cardId}`);
  return CARD_MODE_MULTI_OK;
}

function normalizeCardRule(
  cardId: string,
  rawCardRule: Record<string, unknown>,
  fallbackCardRule: BaseCardRule
): BaseCardRule {
  const legacyTunables: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(rawCardRule)) {
    if (key === "id" || key === "mode" || key === "enabled" || key === "tags" || key === "tunables") {
      continue;
    }
    legacyTunables[key] = value;
  }

  const rawTunables = {
    ...readObject(fallbackCardRule.tunables),
    ...readObject(rawCardRule.tunables),
    ...legacyTunables
  };

  const normalized: BaseCardRule = {
    id: typeof rawCardRule.id === "string" && rawCardRule.id.length > 0 ? rawCardRule.id : fallbackCardRule.id || cardId,
    mode: normalizeMode(rawCardRule.mode ?? fallbackCardRule.mode, cardId),
    enabled: readBoolean(rawCardRule, "enabled", fallbackCardRule.enabled === true),
    tags: readStringListValue(rawCardRule.tags, fallbackCardRule.tags || []),
    tunables: rawTunables
  };

  // 하위호환: 기존 abilities.ts가 rule.shot_budget 같은 루트 필드를 그대로 참조할 수 있게 유지.
  for (const [key, value] of Object.entries(rawTunables)) {
    normalized[key] = value;
  }

  return normalized;
}

function sanitizeCardRules(raw: unknown): CardRules {
  const source = readObject(raw);
  const cardsSource = readObject(source.cards);
  const fallbackCards = DEFAULT_CARD_RULES.cards;
  const versionValue = source.version ?? source.RULES_VERSION;
  const orderSource = Array.isArray(source.card_order) ? source.card_order : source.card_pool;

  const seen = new Set<string>();
  const orderedCardIds: string[] = [];
  for (const cardId of readStringListValue(orderSource, DEFAULT_CARD_RULES.card_order)) {
    if (!seen.has(cardId)) {
      seen.add(cardId);
      orderedCardIds.push(cardId);
    }
  }
  for (const cardId of Object.keys(cardsSource)) {
    if (!seen.has(cardId)) {
      seen.add(cardId);
      orderedCardIds.push(cardId);
    }
  }

  const normalizedCards: Record<string, BaseCardRule> = {};
  for (const cardId of orderedCardIds) {
    const rawCardRule = readObject(cardsSource[cardId]);
    const fallbackCardRule = fallbackCards[cardId] || {
      id: cardId,
      mode: CARD_MODE_MULTI_OK,
      enabled: false,
      tags: [],
      tunables: {}
    };
    normalizedCards[cardId] = normalizeCardRule(cardId, rawCardRule, fallbackCardRule);
  }

  return {
    version: isFiniteNumber(versionValue) ? versionValue : DEFAULT_CARD_RULES.version,
    card_order: orderedCardIds,
    cards: normalizedCards as CardRules["cards"]
  };
}

export const CARD_RULES = sanitizeCardRules(sharedCardRulesJson);

export function getCardRule(cardId: string): BaseCardRule | null {
  const rule = CARD_RULES.cards[cardId];
  return rule ? { ...rule } : null;
}

export function isAllowedInMode(cardId: string, gameMode: GameMode): boolean {
  const rule = CARD_RULES.cards[cardId];
  if (!rule || rule.enabled !== true) {
    return false;
  }
  if (gameMode === GAME_MODE_SINGLE) {
    return rule.mode === CARD_MODE_MULTI_OK || rule.mode === CARD_MODE_SINGLE_ONLY;
  }
  return rule.mode === CARD_MODE_MULTI_OK;
}

export function getTargetMode(cardId: string): TargetMode {
  const rule = CARD_RULES.cards[cardId];
  if (!rule || typeof rule.tunables !== "object" || !rule.tunables) {
    return TARGET_MODE_NONE;
  }
  const rawMode = (rule.tunables as Record<string, unknown>).target_mode;
  if (rawMode === TARGET_MODE_POINT || rawMode === TARGET_MODE_NONE) {
    return rawMode;
  }
  return TARGET_MODE_NONE;
}

export function isPointTargetCard(cardId: string): boolean {
  return getTargetMode(cardId) === TARGET_MODE_POINT;
}

function buildCardPoolByMode(gameMode: GameMode): string[] {
  const pool: string[] = [];
  for (const cardId of CARD_RULES.card_order) {
    if (isAllowedInMode(cardId, gameMode)) {
      pool.push(cardId);
    }
  }
  return pool;
}

export const CARD_POOL = buildCardPoolByMode(GAME_MODE_MULTI);
export const CARD_POOL_SET = new Set<string>(CARD_POOL);
export const SINGLE_CARD_POOL = buildCardPoolByMode(GAME_MODE_SINGLE);

export function isTurnCardEnabled(cardId: string): boolean {
  return isAllowedInMode(cardId, GAME_MODE_MULTI);
}
