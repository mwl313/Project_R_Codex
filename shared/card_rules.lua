--[[
파일명: card_rules.lua
모듈명: CardRules

역할:
- 카드별 수치/제약을 shared/card_rules.json에서 읽어 제공한다.
- mode 기반 필터(SINGLE_ONLY/MULTI_OK)를 지원한다.
- 기존 소비 코드 호환을 위해 tunables를 카드 루트 필드로도 노출한다.

외부에서 사용 가능한 함수:
- CardRules.getRulesVersion()
- CardRules.getCardPool(gameMode)
- CardRules.getCardPoolCount(gameMode)
- CardRules.getCardRule(cardId)
- CardRules.isAllowedInMode(cardId, gameMode)
- CardRules.isTurnCardEnabled(cardId) -- 멀티 기준 호환 함수
- CardRules.getReinforcementRule()
- CardRules.getShockwaveRule()
- CardRules.getInvincibleRule()
- CardRules.getRockfallRule()
- CardRules.getAgileRule()
]]

local Json = require("utils.json")

local CardRules = {}

CardRules.MODE_SINGLE_ONLY = "SINGLE_ONLY"
CardRules.MODE_MULTI_OK = "MULTI_OK"
CardRules.GAME_MODE_SINGLE = "SINGLE"
CardRules.GAME_MODE_MULTI = "MULTI"
CardRules.TARGET_MODE_NONE = "NONE"
CardRules.TARGET_MODE_POINT = "POINT"

local ALLOW_MISSING_MODE_AS_MULTI = false

local DEFAULT_RULES = {
  version = 1,
  card_order = { "reinforcement", "shockwave", "invincible", "rockfall", "agile" },
  cards = {
    reinforcement = {
      id = "reinforcement",
      mode = CardRules.MODE_MULTI_OK,
      enabled = true,
      tags = { "UTILITY", "TRICK" },
      tunables = {
        target_mode = CardRules.TARGET_MODE_POINT,
        min_place_distance = 19,
        lock_spawned_stone_for_turn = true
      }
    },
    shockwave = {
      id = "shockwave",
      mode = CardRules.MODE_MULTI_OK,
      enabled = true,
      tags = { "OFFENSE", "CONTROL" },
      tunables = {
        target_mode = CardRules.TARGET_MODE_NONE,
        radius_multiplier = 4.0,
        strength = 200,
        exclude_source_stone = true,
        ignore_invincible_targets = true
      }
    },
    invincible = {
      id = "invincible",
      mode = CardRules.MODE_MULTI_OK,
      enabled = true,
      tags = { "DEFENSE", "UTILITY" },
      tunables = {
        target_mode = CardRules.TARGET_MODE_NONE,
        protect_after_turn_offset = 1
      }
    },
    rockfall = {
      id = "rockfall",
      mode = CardRules.MODE_MULTI_OK,
      enabled = true,
      tags = { "OBSTACLE", "CONTROL" },
      tunables = {
        target_mode = CardRules.TARGET_MODE_POINT,
        width = 100,
        height = 50,
        margin = 5
      }
    },
    agile = {
      id = "agile",
      mode = CardRules.MODE_MULTI_OK,
      enabled = true,
      tags = { "OFFENSE", "TRICK" },
      tunables = {
        target_mode = CardRules.TARGET_MODE_NONE,
        shot_budget = 2
      }
    }
  }
}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copied = {}
  for key, nested in pairs(value) do
    copied[key] = deepCopy(nested)
  end
  return copied
end

local function isDevMode()
  if not love or not love.filesystem or type(love.filesystem.isFused) ~= "function" then
    return false
  end
  return love.filesystem.isFused() ~= true
end

local function reportSchemaError(message)
  local normalizedMessage = tostring(message or "unknown_schema_error")
  if isDevMode() then
    error("CardRules schema error: " .. normalizedMessage)
  end
  print("[CardRules] schema warning: " .. normalizedMessage)
end

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
    return deepCopy(fallback)
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
    return deepCopy(fallback)
  end
  return sanitized
end

local function normalizeMode(rawMode, cardId)
  if rawMode == CardRules.MODE_SINGLE_ONLY or rawMode == CardRules.MODE_MULTI_OK then
    return rawMode
  end

  if ALLOW_MISSING_MODE_AS_MULTI then
    return CardRules.MODE_MULTI_OK
  end

  reportSchemaError("missing_or_invalid_mode:" .. tostring(cardId))
  return CardRules.MODE_MULTI_OK
end

local function normalizeCardRule(cardId, rawCardRule, fallbackCardRule)
  local source = toTable(rawCardRule)
  local fallback = toTable(fallbackCardRule)
  local legacyTunables = {}
  for key, value in pairs(source) do
    if key ~= "id" and key ~= "mode" and key ~= "enabled" and key ~= "tags" and key ~= "tunables" then
      legacyTunables[key] = value
    end
  end

  local fallbackTunables = toTable(fallback.tunables)
  local rawTunables = toTable(source.tunables)
  for key, value in pairs(legacyTunables) do
    rawTunables[key] = value
  end

  local mergedTunables = {}
  for key, value in pairs(fallbackTunables) do
    mergedTunables[key] = value
  end
  for key, value in pairs(rawTunables) do
    mergedTunables[key] = value
  end

  local normalized = {
    id = tostring(source.id or fallback.id or cardId),
    mode = normalizeMode(source.mode or fallback.mode, cardId),
    enabled = toBoolean(source.enabled, toBoolean(fallback.enabled, true)),
    tags = toStringList(source.tags, fallback.tags or {}),
    tunables = mergedTunables
  }

  -- 하위호환: 기존 코드가 cardRule.min_place_distance 같은 루트 필드를 읽어도 동작.
  for key, value in pairs(mergedTunables) do
    normalized[key] = value
  end

  return normalized
end

local function sanitizeRules(raw)
  local source = toTable(raw)
  local fallbackCards = toTable(DEFAULT_RULES.cards)
  local sourceCards = toTable(source.cards)

  local versionValue = source.version
  if versionValue == nil then
    versionValue = source.RULES_VERSION
  end

  local orderSource = source.card_order
  if type(orderSource) ~= "table" then
    orderSource = source.card_pool
  end
  local orderedIds = toStringList(orderSource, DEFAULT_RULES.card_order)
  local seenOrder = {}
  local orderedCardIds = {}
  for _, cardId in ipairs(orderedIds) do
    if not seenOrder[cardId] then
      seenOrder[cardId] = true
      orderedCardIds[#orderedCardIds + 1] = cardId
    end
  end

  for cardId, _ in pairs(sourceCards) do
    local normalizedId = tostring(cardId)
    if normalizedId ~= "" and not seenOrder[normalizedId] then
      seenOrder[normalizedId] = true
      orderedCardIds[#orderedCardIds + 1] = normalizedId
    end
  end

  local normalizedCards = {}
  for _, cardId in ipairs(orderedCardIds) do
    normalizedCards[cardId] = normalizeCardRule(cardId, sourceCards[cardId], fallbackCards[cardId])
  end

  return {
    version = toFiniteNumber(versionValue, DEFAULT_RULES.version),
    card_order = orderedCardIds,
    cards = normalizedCards
  }
end

local loaded = readJsonTable("shared/card_rules.json")
local SANITIZED_RULES = sanitizeRules(loaded)

function CardRules.getRulesVersion()
  return SANITIZED_RULES.version
end

function CardRules.getCardRule(cardId)
  local rule = SANITIZED_RULES.cards[tostring(cardId or "")]
  if type(rule) ~= "table" then
    return nil
  end
  return deepCopy(rule)
end

function CardRules.getCardTunables(cardId)
  local rule = CardRules.getCardRule(cardId)
  if type(rule) ~= "table" then
    return {}
  end
  if type(rule.tunables) ~= "table" then
    return {}
  end
  return deepCopy(rule.tunables)
end

function CardRules.getTargetMode(cardId)
  local tunables = CardRules.getCardTunables(cardId)
  local targetMode = tunables.target_mode
  if targetMode == CardRules.TARGET_MODE_POINT or targetMode == CardRules.TARGET_MODE_NONE then
    return targetMode
  end
  return CardRules.TARGET_MODE_NONE
end

function CardRules.isPointTargetCard(cardId)
  return CardRules.getTargetMode(cardId) == CardRules.TARGET_MODE_POINT
end

function CardRules.isAllowedInMode(cardId, gameMode)
  local rule = SANITIZED_RULES.cards[tostring(cardId or "")]
  if type(rule) ~= "table" or rule.enabled ~= true then
    return false
  end

  if gameMode == CardRules.GAME_MODE_SINGLE then
    return rule.mode == CardRules.MODE_MULTI_OK or rule.mode == CardRules.MODE_SINGLE_ONLY
  end
  return rule.mode == CardRules.MODE_MULTI_OK
end

function CardRules.getCardPool(gameMode)
  local normalizedMode = gameMode or CardRules.GAME_MODE_MULTI
  local copied = {}
  for _, cardId in ipairs(SANITIZED_RULES.card_order or {}) do
    if CardRules.isAllowedInMode(cardId, normalizedMode) then
      copied[#copied + 1] = cardId
    end
  end
  return copied
end

function CardRules.getCardPoolCount(gameMode)
  return #CardRules.getCardPool(gameMode)
end

function CardRules.isTurnCardEnabled(cardId)
  return CardRules.isAllowedInMode(cardId, CardRules.GAME_MODE_MULTI)
end

function CardRules.getReinforcementRule()
  return CardRules.getCardRule("reinforcement")
end

function CardRules.getShockwaveRule()
  return CardRules.getCardRule("shockwave")
end

function CardRules.getInvincibleRule()
  return CardRules.getCardRule("invincible")
end

function CardRules.getRockfallRule()
  return CardRules.getCardRule("rockfall")
end

function CardRules.getAgileRule()
  return CardRules.getCardRule("agile")
end

return CardRules
