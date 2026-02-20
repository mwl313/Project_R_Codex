--[[
파일명: card_rules.lua
모듈명: CardRules

역할:
- 카드별 수치/제약을 shared/card_rules.json에서 읽어 제공한다.
- 카드 행동 로직(abilities.lua)과 데이터(JSON)를 분리해 밸런스 패치를 단순화한다.

외부에서 사용 가능한 함수:
- CardRules.getRulesVersion()
- CardRules.getCardPool()
- CardRules.getCardPoolCount()
- CardRules.isTurnCardEnabled(cardId)
- CardRules.getReinforcementRule()
- CardRules.getShockwaveRule()
- CardRules.getInvincibleRule()
- CardRules.getRockfallRule()
- CardRules.getAgileRule()
]]

local Json = require("utils.json")

local CardRules = {}

local DEFAULT_RULES = {
  RULES_VERSION = 1,
  card_pool = { "reinforcement", "shockwave", "invincible", "rockfall", "agile" },
  cards = {
    reinforcement = {
      enabled = true,
      min_place_distance = 19,
      lock_spawned_stone_for_turn = true
    },
    shockwave = {
      enabled = true,
      radius_multiplier = 4.0,
      strength = 200,
      exclude_source_stone = true,
      ignore_invincible_targets = true
    },
    invincible = {
      enabled = true,
      protect_after_turn_offset = 1
    },
    rockfall = {
      enabled = true,
      width = 100,
      height = 50,
      margin = 5
    },
    agile = {
      enabled = true,
      shot_budget = 2
    }
  }
}

local function readJsonTable(path)
  if not love or not love.filesystem then
    return nil
  end
  local isReadOk, rawOrError = pcall(love.filesystem.read, path)
  if not isReadOk or type(rawOrError) ~= "string" or rawOrError == "" then
    return nil
  end
  local isDecoded, parsed = pcall(Json.decode, rawOrError)
  if not isDecoded or type(parsed) ~= "table" then
    return nil
  end
  return parsed
end

local function toFiniteNumber(value, fallback)
  if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
    return value
  end
  return fallback
end

local function toBoolean(value, fallback)
  if type(value) == "boolean" then
    return value
  end
  return fallback
end

local function toTable(value)
  if type(value) == "table" then
    return value
  end
  return {}
end

local function toStringList(value, fallback)
  if type(value) ~= "table" then
    return fallback
  end

  local seen = {}
  local sanitized = {}
  for _, entry in ipairs(value) do
    if type(entry) == "string" and entry ~= "" and not seen[entry] then
      seen[entry] = true
      sanitized[#sanitized + 1] = entry
    end
  end
  if #sanitized <= 0 then
    return fallback
  end
  return sanitized
end

local function sanitizeRules(raw)
  local source = toTable(raw)
  local cards = toTable(source.cards)

  local reinforcement = toTable(cards.reinforcement)
  local shockwave = toTable(cards.shockwave)
  local invincible = toTable(cards.invincible)
  local rockfall = toTable(cards.rockfall)
  local agile = toTable(cards.agile)

  return {
    RULES_VERSION = toFiniteNumber(source.RULES_VERSION, DEFAULT_RULES.RULES_VERSION),
    card_pool = toStringList(source.card_pool, DEFAULT_RULES.card_pool),
    cards = {
      reinforcement = {
        enabled = toBoolean(reinforcement.enabled, DEFAULT_RULES.cards.reinforcement.enabled),
        min_place_distance = toFiniteNumber(
          reinforcement.min_place_distance,
          DEFAULT_RULES.cards.reinforcement.min_place_distance
        ),
        lock_spawned_stone_for_turn = toBoolean(
          reinforcement.lock_spawned_stone_for_turn,
          DEFAULT_RULES.cards.reinforcement.lock_spawned_stone_for_turn
        )
      },
      shockwave = {
        enabled = toBoolean(shockwave.enabled, DEFAULT_RULES.cards.shockwave.enabled),
        radius_multiplier = toFiniteNumber(
          shockwave.radius_multiplier,
          DEFAULT_RULES.cards.shockwave.radius_multiplier
        ),
        strength = toFiniteNumber(shockwave.strength, DEFAULT_RULES.cards.shockwave.strength),
        exclude_source_stone = toBoolean(
          shockwave.exclude_source_stone,
          DEFAULT_RULES.cards.shockwave.exclude_source_stone
        ),
        ignore_invincible_targets = toBoolean(
          shockwave.ignore_invincible_targets,
          DEFAULT_RULES.cards.shockwave.ignore_invincible_targets
        )
      },
      invincible = {
        enabled = toBoolean(invincible.enabled, DEFAULT_RULES.cards.invincible.enabled),
        protect_after_turn_offset = toFiniteNumber(
          invincible.protect_after_turn_offset,
          DEFAULT_RULES.cards.invincible.protect_after_turn_offset
        )
      },
      rockfall = {
        enabled = toBoolean(rockfall.enabled, DEFAULT_RULES.cards.rockfall.enabled),
        width = toFiniteNumber(rockfall.width, DEFAULT_RULES.cards.rockfall.width),
        height = toFiniteNumber(rockfall.height, DEFAULT_RULES.cards.rockfall.height),
        margin = toFiniteNumber(rockfall.margin, DEFAULT_RULES.cards.rockfall.margin)
      },
      agile = {
        enabled = toBoolean(agile.enabled, DEFAULT_RULES.cards.agile.enabled),
        shot_budget = toFiniteNumber(agile.shot_budget, DEFAULT_RULES.cards.agile.shot_budget)
      }
    }
  }
end

local loaded = readJsonTable("shared/card_rules.json")
local SANITIZED_RULES = sanitizeRules(loaded)

function CardRules.getRulesVersion()
  return SANITIZED_RULES.RULES_VERSION
end

function CardRules.getCardPool()
  local copied = {}
  for _, cardId in ipairs(SANITIZED_RULES.card_pool or {}) do
    copied[#copied + 1] = cardId
  end
  return copied
end

function CardRules.getCardPoolCount()
  return #(SANITIZED_RULES.card_pool or {})
end

function CardRules.isTurnCardEnabled(cardId)
  local cards = SANITIZED_RULES.cards
  local rule = cards and cards[cardId]
  return type(rule) == "table" and rule.enabled == true
end

function CardRules.getReinforcementRule()
  return SANITIZED_RULES.cards.reinforcement
end

function CardRules.getShockwaveRule()
  return SANITIZED_RULES.cards.shockwave
end

function CardRules.getInvincibleRule()
  return SANITIZED_RULES.cards.invincible
end

function CardRules.getRockfallRule()
  return SANITIZED_RULES.cards.rockfall
end

function CardRules.getAgileRule()
  return SANITIZED_RULES.cards.agile
end

return CardRules
