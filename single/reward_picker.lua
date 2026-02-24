--[[
파일명: reward_picker.lua
모듈명: RewardPicker

역할:
- 싱글 보상 카드 3개를 SSOT 데이터 기반으로 선택한다.
- reward_tables + single_campaign_rules + shared/card_rules를 조합해
  모드/활성화/태그/희귀도 정책을 적용한다.
]]

local CardRules = require("shared.card_rules")
local CardRegistry = require("single.card_registry")
local RewardTablesLoader = require("single.reward_tables_loader")
local SingleCampaignRulesLoader = require("single.single_campaign_rules_loader")

local RewardPicker = {}
RewardPicker.__index = RewardPicker

local RARITY_ORDER = { "COMMON", "RARE", "EPIC", "LEGENDARY" }
local DEBUG_REWARD_PICK = false

local function isDevMode()
  if not love or not love.filesystem or type(love.filesystem.isFused) ~= "function" then
    return false
  end
  return love.filesystem.isFused() ~= true
end

local function debugLog(message)
  if not DEBUG_REWARD_PICK or not isDevMode() then
    return
  end
  print("[RewardPicker] " .. tostring(message or ""))
end

local function clampInt(value, fallback, minValue)
  local numeric = tonumber(value)
  if type(numeric) ~= "number" or numeric ~= numeric then
    numeric = fallback
  end
  numeric = math.floor(numeric or fallback)
  if numeric < minValue then
    numeric = minValue
  end
  return numeric
end

local function randomInt(rng, minValue, maxValue)
  if minValue >= maxValue then
    return minValue
  end
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function randomFloat(rng)
  if rng and type(rng.random) == "function" then
    return rng:random()
  end
  return math.random()
end

local function createFallbackRng(seed)
  if love and love.math and type(love.math.newRandomGenerator) == "function" then
    return love.math.newRandomGenerator(seed or os.time())
  end
  math.randomseed(seed or os.time())
  return nil
end

local function hasAnyTag(cardTags, tagsAny)
  if type(tagsAny) ~= "table" or #tagsAny <= 0 then
    return true
  end
  if type(cardTags) ~= "table" then
    return false
  end

  local cardTagSet = {}
  for _, tag in ipairs(cardTags) do
    if type(tag) == "string" and tag ~= "" then
      cardTagSet[tag] = true
    end
  end
  for _, requiredTag in ipairs(tagsAny) do
    if type(requiredTag) == "string" and cardTagSet[requiredTag] then
      return true
    end
  end
  return false
end

local function normalizeRarity(value)
  local text = tostring(value or ""):upper()
  for _, rarity in ipairs(RARITY_ORDER) do
    if text == rarity then
      return rarity
    end
  end
  return "COMMON"
end

local function findContextByNodeType(rewardTables, nodeType)
  local typeText = tostring(nodeType or "mob")
  local contextList = rewardTables and rewardTables.rewardContexts or nil
  if type(contextList) ~= "table" then
    return nil
  end

  local mobFallback = nil
  local firstContext = nil
  for _, context in ipairs(contextList) do
    if type(context) == "table" then
      firstContext = firstContext or context
      local nodeTypes = type(context.nodeTypes) == "table" and context.nodeTypes or {}
      local hasMob = false
      for _, mappedType in ipairs(nodeTypes) do
        if mappedType == "mob" then
          hasMob = true
        end
        if mappedType == typeText then
          return context
        end
      end
      if hasMob and (not mobFallback) then
        mobFallback = context
      end
    end
  end

  return mobFallback or firstContext
end

local function resolveWeights(campaignRules, rarityRef, stageIndex)
  local raritySection = type(campaignRules) == "table" and campaignRules.rarityWeights or nil
  if type(raritySection) ~= "table" then
    raritySection = {}
  end
  local baseCandidate = raritySection[rarityRef]
  if type(baseCandidate) ~= "table" then
    baseCandidate = raritySection.base
  end
  if type(baseCandidate) ~= "table" then
    baseCandidate = { COMMON = 1, RARE = 0, EPIC = 0, LEGENDARY = 0 }
  end

  local weights = {
    COMMON = tonumber(baseCandidate.COMMON) or 0,
    RARE = tonumber(baseCandidate.RARE) or 0,
    EPIC = tonumber(baseCandidate.EPIC) or 0,
    LEGENDARY = tonumber(baseCandidate.LEGENDARY) or 0
  }

  local scalingList = raritySection.stageScaling
  if type(scalingList) == "table" then
    local stageNumber = clampInt(stageIndex, 1, 1)
    for _, scaling in ipairs(scalingList) do
      if type(scaling) == "table" and clampInt(scaling.stageIndex, -1, -1) == stageNumber then
        if tonumber(scaling.COMMON) ~= nil then
          weights.COMMON = tonumber(scaling.COMMON) or weights.COMMON
        end
        if tonumber(scaling.RARE) ~= nil then
          weights.RARE = tonumber(scaling.RARE) or weights.RARE
        end
        if tonumber(scaling.EPIC) ~= nil then
          weights.EPIC = tonumber(scaling.EPIC) or weights.EPIC
        end
        if tonumber(scaling.LEGENDARY) ~= nil then
          weights.LEGENDARY = tonumber(scaling.LEGENDARY) or weights.LEGENDARY
        end
        break
      end
    end
  end

  return weights
end

local function pickWeightedRarity(weights, rng)
  local total = 0
  for _, rarity in ipairs(RARITY_ORDER) do
    local weight = tonumber(weights[rarity]) or 0
    if weight > 0 then
      total = total + weight
    end
  end

  if total <= 0 then
    return "COMMON"
  end

  local cursor = randomFloat(rng) * total
  local accum = 0
  for _, rarity in ipairs(RARITY_ORDER) do
    local weight = math.max(0, tonumber(weights[rarity]) or 0)
    if weight > 0 then
      accum = accum + weight
      if cursor <= accum then
        return rarity
      end
    end
  end

  return "COMMON"
end

local function findRarityIndex(targetRarity)
  for index, rarity in ipairs(RARITY_ORDER) do
    if rarity == targetRarity then
      return index
    end
  end
  return 1
end

local function pickFromRarityWithFallback(byRarity, preferredRarity, rng)
  local startIndex = findRarityIndex(preferredRarity)

  for index = startIndex, #RARITY_ORDER do
    local list = byRarity[RARITY_ORDER[index]]
    if type(list) == "table" and #list > 0 then
      local pickIndex = randomInt(rng, 1, #list)
      local picked = list[pickIndex]
      table.remove(list, pickIndex)
      return picked
    end
  end

  for index = 1, startIndex - 1 do
    local list = byRarity[RARITY_ORDER[index]]
    if type(list) == "table" and #list > 0 then
      local pickIndex = randomInt(rng, 1, #list)
      local picked = list[pickIndex]
      table.remove(list, pickIndex)
      return picked
    end
  end

  return nil
end

local function gatherCandidates(context, campaignRules, isBoss)
  local filters = type(context.filters) == "table" and context.filters or {}
  local tagsAny = type(filters.tagsAny) == "table" and filters.tagsAny or {}
  local filterMode = tostring(filters.mode or "single"):lower()
  local allowLegendaryByContext = context.allowLegendary == true
  local legendaryBossOnly = not not (campaignRules
    and campaignRules.legendaryPolicy
    and campaignRules.legendaryPolicy.bossOnly == true)

  local gameMode = CardRules.GAME_MODE_SINGLE
  if filterMode == "multi" then
    gameMode = CardRules.GAME_MODE_MULTI
  end

  local runtimePool = CardRules.getCardPool(gameMode)
  local bySaveCardId = {}

  for _, runtimeCardId in ipairs(runtimePool) do
    local rule = CardRules.getCardRule(runtimeCardId)
    if type(rule) == "table" and rule.enabled == true and hasAnyTag(rule.tags, tagsAny) then
      local rarity = normalizeRarity(rule.rarity or (rule.tunables and rule.tunables.rarity))
      if rarity ~= "LEGENDARY" or allowLegendaryByContext then
        if not (legendaryBossOnly and rarity == "LEGENDARY" and not isBoss) then
          local saveCardId = CardRegistry.fromRuntimeCardId(runtimeCardId)
          if CardRegistry.getCard(saveCardId) ~= nil then
            if not bySaveCardId[saveCardId] then
              bySaveCardId[saveCardId] = {
                cardId = saveCardId,
                runtimeCardId = runtimeCardId,
                rarity = rarity
              }
            end
          end
        end
      end
    end
  end

  local candidateList = {}
  for _, entry in pairs(bySaveCardId) do
    candidateList[#candidateList + 1] = entry
  end
  return candidateList
end

function RewardPicker.new()
  local instance = {
    _rewardTables = RewardTablesLoader.load(),
    _campaignRules = SingleCampaignRulesLoader.load()
  }
  return setmetatable(instance, RewardPicker)
end

function RewardPicker:pick3(runState, nodeType, stageIndex, isBoss, rng)
  local context = findContextByNodeType(self._rewardTables, nodeType) or {
    contextId = "fallback_mob",
    offerCount = 3,
    rarityWeightsRef = "base",
    allowLegendary = false,
    filters = { tagsAny = {} }
  }

  local effectiveStageIndex = clampInt(stageIndex or (runState and runState.stageIndex), 1, 1)
  local offerCount = 3
  local localRng = rng
  if not localRng then
    local seed = tonumber(runState and runState.rngSeed) or os.time()
    localRng = createFallbackRng(seed + effectiveStageIndex * 47)
  end

  local candidates = gatherCandidates(context, self._campaignRules, isBoss == true)
  local byRarity = {
    COMMON = {},
    RARE = {},
    EPIC = {},
    LEGENDARY = {}
  }
  for _, candidate in ipairs(candidates) do
    byRarity[candidate.rarity][#byRarity[candidate.rarity] + 1] = candidate
  end

  local weights = resolveWeights(self._campaignRules, context.rarityWeightsRef, effectiveStageIndex)
  local pickedIds = {}
  local pickedSet = {}
  local pickedRarities = {}

  for _ = 1, offerCount do
    local targetRarity = pickWeightedRarity(weights, localRng)
    local picked = pickFromRarityWithFallback(byRarity, targetRarity, localRng)
    if not picked then
      break
    end
    if not pickedSet[picked.cardId] then
      pickedSet[picked.cardId] = true
      pickedIds[#pickedIds + 1] = picked.cardId
      pickedRarities[#pickedRarities + 1] = picked.rarity
    end
  end

  if #pickedIds < offerCount then
    local remaining = {}
    for _, candidate in ipairs(candidates) do
      if not pickedSet[candidate.cardId] then
        remaining[#remaining + 1] = candidate
      end
    end
    while #pickedIds < offerCount and #remaining > 0 do
      local index = randomInt(localRng, 1, #remaining)
      local picked = remaining[index]
      table.remove(remaining, index)
      pickedSet[picked.cardId] = true
      pickedIds[#pickedIds + 1] = picked.cardId
      pickedRarities[#pickedRarities + 1] = picked.rarity
    end
  end

  if #pickedIds <= 0 then
    pickedIds = {
      "rockfall",
      "shockwave",
      "invincible"
    }
    pickedRarities = { "COMMON", "COMMON", "RARE" }
  end

  while #pickedIds < offerCount do
    pickedIds[#pickedIds + 1] = pickedIds[randomInt(localRng, 1, #pickedIds)]
  end

  debugLog(string.format(
    "context=%s nodeType=%s isBoss=%s stage=%d picks=%s rarities=%s",
    tostring(context.contextId),
    tostring(nodeType),
    tostring(isBoss == true),
    effectiveStageIndex,
    table.concat(pickedIds, ","),
    table.concat(pickedRarities, ",")
  ))

  return pickedIds
end

return RewardPicker
