import sharedCardRulesJson from "../../shared/card_rules.json";

interface ReinforcementCardRule {
  enabled: boolean;
  min_place_distance: number;
  lock_spawned_stone_for_turn: boolean;
}

interface ShockwaveCardRule {
  enabled: boolean;
  radius_multiplier: number;
  strength: number;
  exclude_source_stone: boolean;
  ignore_invincible_targets: boolean;
}

interface InvincibleCardRule {
  enabled: boolean;
  protect_after_turn_offset: number;
}

interface RockfallCardRule {
  enabled: boolean;
  width: number;
  height: number;
  margin: number;
}

interface AgileCardRule {
  enabled: boolean;
  shot_budget: number;
}

interface CardRules {
  RULES_VERSION: number;
  card_pool: string[];
  cards: {
    reinforcement: ReinforcementCardRule;
    shockwave: ShockwaveCardRule;
    invincible: InvincibleCardRule;
    rockfall: RockfallCardRule;
    agile: AgileCardRule;
  };
}

const DEFAULT_CARD_RULES: CardRules = {
  RULES_VERSION: 1,
  card_pool: ["reinforcement", "shockwave", "invincible", "rockfall", "agile"],
  cards: {
    reinforcement: {
      enabled: true,
      min_place_distance: 19,
      lock_spawned_stone_for_turn: true
    },
    shockwave: {
      enabled: true,
      radius_multiplier: 4,
      strength: 200,
      exclude_source_stone: true,
      ignore_invincible_targets: true
    },
    invincible: {
      enabled: true,
      protect_after_turn_offset: 1
    },
    rockfall: {
      enabled: true,
      width: 100,
      height: 50,
      margin: 5
    },
    agile: {
      enabled: true,
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

function readStringList(source: Record<string, unknown>, key: string, fallback: string[]): string[] {
  const rawValue = source[key];
  if (!Array.isArray(rawValue)) {
    return [...fallback];
  }

  const sanitized: string[] = [];
  const seen = new Set<string>();
  for (const entry of rawValue) {
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

function sanitizeCardRules(raw: unknown): CardRules {
  const source = readObject(raw);
  const cards = readObject(source.cards);

  const reinforcementRaw = readObject(cards.reinforcement);
  const shockwaveRaw = readObject(cards.shockwave);
  const invincibleRaw = readObject(cards.invincible);
  const rockfallRaw = readObject(cards.rockfall);
  const agileRaw = readObject(cards.agile);

  return {
    RULES_VERSION: readNumber(source, "RULES_VERSION", DEFAULT_CARD_RULES.RULES_VERSION),
    card_pool: readStringList(source, "card_pool", DEFAULT_CARD_RULES.card_pool),
    cards: {
      reinforcement: {
        enabled: readBoolean(reinforcementRaw, "enabled", DEFAULT_CARD_RULES.cards.reinforcement.enabled),
        min_place_distance: readNumber(
          reinforcementRaw,
          "min_place_distance",
          DEFAULT_CARD_RULES.cards.reinforcement.min_place_distance
        ),
        lock_spawned_stone_for_turn: readBoolean(
          reinforcementRaw,
          "lock_spawned_stone_for_turn",
          DEFAULT_CARD_RULES.cards.reinforcement.lock_spawned_stone_for_turn
        )
      },
      shockwave: {
        enabled: readBoolean(shockwaveRaw, "enabled", DEFAULT_CARD_RULES.cards.shockwave.enabled),
        radius_multiplier: readNumber(
          shockwaveRaw,
          "radius_multiplier",
          DEFAULT_CARD_RULES.cards.shockwave.radius_multiplier
        ),
        strength: readNumber(shockwaveRaw, "strength", DEFAULT_CARD_RULES.cards.shockwave.strength),
        exclude_source_stone: readBoolean(
          shockwaveRaw,
          "exclude_source_stone",
          DEFAULT_CARD_RULES.cards.shockwave.exclude_source_stone
        ),
        ignore_invincible_targets: readBoolean(
          shockwaveRaw,
          "ignore_invincible_targets",
          DEFAULT_CARD_RULES.cards.shockwave.ignore_invincible_targets
        )
      },
      invincible: {
        enabled: readBoolean(invincibleRaw, "enabled", DEFAULT_CARD_RULES.cards.invincible.enabled),
        protect_after_turn_offset: readNumber(
          invincibleRaw,
          "protect_after_turn_offset",
          DEFAULT_CARD_RULES.cards.invincible.protect_after_turn_offset
        )
      },
      rockfall: {
        enabled: readBoolean(rockfallRaw, "enabled", DEFAULT_CARD_RULES.cards.rockfall.enabled),
        width: readNumber(rockfallRaw, "width", DEFAULT_CARD_RULES.cards.rockfall.width),
        height: readNumber(rockfallRaw, "height", DEFAULT_CARD_RULES.cards.rockfall.height),
        margin: readNumber(rockfallRaw, "margin", DEFAULT_CARD_RULES.cards.rockfall.margin)
      },
      agile: {
        enabled: readBoolean(agileRaw, "enabled", DEFAULT_CARD_RULES.cards.agile.enabled),
        shot_budget: readNumber(agileRaw, "shot_budget", DEFAULT_CARD_RULES.cards.agile.shot_budget)
      }
    }
  };
}

export const CARD_RULES = sanitizeCardRules(sharedCardRulesJson);
export const CARD_POOL = [...CARD_RULES.card_pool];
export const CARD_POOL_SET = new Set<string>(CARD_POOL);

export function isTurnCardEnabled(cardId: string): boolean {
  if (cardId === "reinforcement") {
    return CARD_RULES.cards.reinforcement.enabled;
  }
  if (cardId === "shockwave") {
    return CARD_RULES.cards.shockwave.enabled;
  }
  if (cardId === "invincible") {
    return CARD_RULES.cards.invincible.enabled;
  }
  if (cardId === "rockfall") {
    return CARD_RULES.cards.rockfall.enabled;
  }
  if (cardId === "agile") {
    return CARD_RULES.cards.agile.enabled;
  }
  return false;
}
