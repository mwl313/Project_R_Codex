--[[
파일명: reward_picker.lua
모듈명: RewardPicker

역할:
- 싱글 보상 드래프트(3선택)를 SSOT 데이터 기반으로 계산한다.
- shared/reward_tables.json / shared/single_campaign_rules.json / shared/card_rules.json을 조합한다.
]]

local CardRules = require("shared.card_rules")
local CardRegistry = require("single.card_registry")
local RewardTablesLoader = require("single.reward_tables_loader")
local SingleCampaignRulesLoader = require("single.single_campaign_rules_loader")

local RewardPicker = {}

local RARITY_ORDER = { "COMMON", "RARE", "EPIC", "LEGENDARY" }
local ENABLE_DEV_LOG = true

local cachedRewardTables = nil
local cachedCampaignRules = nil

local function isDevMode()
  if not love or not love.filesystem or type(love.filesystem.isFused) ~= "function" then
    return false
  end
  return love.filesystem.isFused() ~= true
end

local function logPick(message)
  if not ENABLE_DEV_LOG or not isDevMode() then
    return
  end
  print("[REWARD_PICK] " .. tostring(message or ""))
end

local function clampInt(value, fallback, minValue)
  local n = tonumber(value)
  if type(n) ~= "number" or n ~= n then
    n = tonumber(fallback) or minValue
  end
  n = math.floor(n)
  if n < minValue then
    n = minValue
  end
  return n
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

local function makeRng(seed)
  if love and love.math and type(love.math.newRandomGenerator) == "function" then
    return love.math.newRandomGenerator(seed or os.time())
  end
  math.randomseed(seed or os.time())
  return nil
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

local function ensureDataLoaded()
  if not cachedRewardTables then
    cachedRewardTables = RewardTablesLoader.load()
  end
  if not cachedCampaignRules then
    cachedCampaignRules = SingleCampaignRulesLoader.load()
  end
  return cachedRewardTables, cachedCampaignRules
end

local function findContextByNodeType(rewardTables, nodeType)
  local targetType = tostring(nodeType or "mob")
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
        if mappedType == targetType then
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

local function resolveRarityWeights(campaignRules, rarityRef, stageIndex)
  local raritySection = type(campaignRules) == "table" and campaignRules.rarityWeights or {}
  local baseWeights = type(raritySection[rarityRef]) == "table" and raritySection[rarityRef] or raritySection.base
  if type(baseWeights) ~= "table" then
    baseWeights = { COMMON = 1, RARE = 0, EPIC = 0, LEGENDARY = 0 }
  end

  local result = {
    COMMON = tonumber(baseWeights.COMMON) or 0,
    RARE = tonumber(baseWeights.RARE) or 0,
    EPIC = tonumber(baseWeights.EPIC) or 0,
    LEGENDARY = tonumber(baseWeights.LEGENDARY) or 0
  }

  local scalingList = raritySection.stageScaling
  if type(scalingList) == "table" then
    local stageNumber = clampInt(stageIndex, 1, 1)
    for _, scaling in ipairs(scalingList) do
      if type(scaling) == "table" and clampInt(scaling.stageIndex, -1, -1) == stageNumber then
        if tonumber(scaling.COMMON) ~= nil then
          result.COMMON = tonumber(scaling.COMMON) or result.COMMON
        end
        if tonumber(scaling.RARE) ~= nil then
          result.RARE = tonumber(scaling.RARE) or result.RARE
        end
        if tonumber(scaling.EPIC) ~= nil then
          result.EPIC = tonumber(scaling.EPIC) or result.EPIC
        end
        if tonumber(scaling.LEGENDARY) ~= nil then
          result.LEGENDARY = tonumber(scaling.LEGENDARY) or result.LEGENDARY
        end
        break
      end
    end
  end

  return result
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

local function findRarityIndex(rarity)
  for index, text in ipairs(RARITY_ORDER) do
    if text == rarity then
      return index
    end
  end
  return 1
end

local function pickFromBucketsWithFallback(bucketByRarity, preferredRarity, rng)
  local startIndex = findRarityIndex(preferredRarity)

  for index = startIndex, #RARITY_ORDER do
    local list = bucketByRarity[RARITY_ORDER[index]]
    if type(list) == "table" and #list > 0 then
      local pickIndex = randomInt(rng, 1, #list)
      local picked = list[pickIndex]
      table.remove(list, pickIndex)
      return picked
    end
  end
  for index = 1, startIndex - 1 do
    local list = bucketByRarity[RARITY_ORDER[index]]
    if type(list) == "table" and #list > 0 then
      local pickIndex = randomInt(rng, 1, #list)
      local picked = list[pickIndex]
      table.remove(list, pickIndex)
      return picked
    end
  end
  return nil
end

local function buildCandidatePool(context, campaignRules, isBoss)
  local filters = type(context.filters) == "table" and context.filters or {}
  local tagsAny = type(filters.tagsAny) == "table" and filters.tagsAny or {}
  local filterMode = tostring(filters.mode or "single"):lower()
  local gameMode = (filterMode == "multi") and CardRules.GAME_MODE_MULTI or CardRules.GAME_MODE_SINGLE

  local allowLegendaryByContext = context.allowLegendary == true
  local legendaryBossOnly = not not (campaignRules and campaignRules.legendaryPolicy and campaignRules.legendaryPolicy.bossOnly == true)

  local runtimeCardIdList = CardRules.getCardPool(gameMode)
  local bySaveCardId = {}

  for _, runtimeCardId in ipairs(runtimeCardIdList) do
    local rule = CardRules.getCardRule(runtimeCardId)
    if type(rule) == "table" and rule.enabled == true and hasAnyTag(rule.tags, tagsAny) then
      local rarity = normalizeRarity(rule.rarity or (rule.tunables and rule.tunables.rarity))
      local allowCard = true

      if rarity == "LEGENDARY" then
        -- 하드 룰:
        -- 1) 비보스는 전설 금지
        -- 2) 보스라도 context.allowLegendary=true AND legendaryPolicy.bossOnly=true 동시 만족 필요
        if (not isBoss) or (not allowLegendaryByContext) or (not legendaryBossOnly) then
          allowCard = false
        end
      end

      if allowCard then
        local saveCardId = CardRegistry.fromRuntimeCardId(runtimeCardId)
        if CardRegistry.getCard(saveCardId) ~= nil and not bySaveCardId[saveCardId] then
          bySaveCardId[saveCardId] = {
            cardId = saveCardId,
            rarity = rarity
          }
        end
      end
    end
  end

  local list = {}
  for _, entry in pairs(bySaveCardId) do
    list[#list + 1] = entry
  end
  return list
end

function RewardPicker.pick3(params)
  local option = type(params) == "table" and params or {}
  local rewardTables, campaignRules = ensureDataLoaded()

  local nodeType = tostring(option.nodeType or "mob")
  local stageIndex = clampInt(option.stageIndex, 1, 1)
  local isBoss = option.isBoss == true or nodeType == "boss"
  local rngSeed = tonumber(option.rngSeed) or os.time()
  local rng = makeRng(rngSeed)

  local context = findContextByNodeType(rewardTables, nodeType) or {
    contextId = "fallback_mob",
    offerCount = 3,
    rarityWeightsRef = "base",
    allowLegendary = false,
    filters = { mode = "single", tagsAny = {} }
  }

  local offerCount = 3
  local weights = resolveRarityWeights(campaignRules, context.rarityWeightsRef, stageIndex)
  local candidatePool = buildCandidatePool(context, campaignRules, isBoss)

  local bucketByRarity = {
    COMMON = {},
    RARE = {},
    EPIC = {},
    LEGENDARY = {}
  }
  for _, candidate in ipairs(candidatePool) do
    bucketByRarity[candidate.rarity][#bucketByRarity[candidate.rarity] + 1] = candidate
  end

  local pickedCardIdList = {}
  local pickedRarityList = {}
  local pickedSet = {}

  for _ = 1, offerCount do
    local preferredRarity = pickWeightedRarity(weights, rng)
    local picked = pickFromBucketsWithFallback(bucketByRarity, preferredRarity, rng)
    if not picked then
      break
    end
    if not pickedSet[picked.cardId] then
      pickedSet[picked.cardId] = true
      pickedCardIdList[#pickedCardIdList + 1] = picked.cardId
      pickedRarityList[#pickedRarityList + 1] = picked.rarity
    end
  end

  if #pickedCardIdList < offerCount then
    local remaining = {}
    for _, candidate in ipairs(candidatePool) do
      if not pickedSet[candidate.cardId] then
        remaining[#remaining + 1] = candidate
      end
    end
    while #pickedCardIdList < offerCount and #remaining > 0 do
      local index = randomInt(rng, 1, #remaining)
      local picked = remaining[index]
      table.remove(remaining, index)
      pickedSet[picked.cardId] = true
      pickedCardIdList[#pickedCardIdList + 1] = picked.cardId
      pickedRarityList[#pickedRarityList + 1] = picked.rarity
    end
  end

  if #pickedCardIdList <= 0 then
    pickedCardIdList = { "rockfall", "shockwave", "invincible" }
    pickedRarityList = { "COMMON", "COMMON", "RARE" }
  end

  -- 풀이 너무 작을 때만 중복 허용 (최후 수단)
  while #pickedCardIdList < offerCount do
    local copyIndex = randomInt(rng, 1, #pickedCardIdList)
    pickedCardIdList[#pickedCardIdList + 1] = pickedCardIdList[copyIndex]
    pickedRarityList[#pickedRarityList + 1] = pickedRarityList[copyIndex]
  end

  logPick(string.format(
    "contextId=%s stageIndex=%d isBoss=%s nodeType=%s picks=%s rarities=%s",
    tostring(context.contextId),
    stageIndex,
    tostring(isBoss),
    nodeType,
    table.concat(pickedCardIdList, ","),
    table.concat(pickedRarityList, ",")
  ))

  return pickedCardIdList
end

function RewardPicker.resetCache()
  cachedRewardTables = nil
  cachedCampaignRules = nil
end

return RewardPicker
