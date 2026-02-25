--[[
파일명: relic_registry.lua
모듈명: RelicRegistry

역할:
- shared/relic_rules.json 기반 릴릭 정의 조회/선택 기능을 제공한다.
]]

local RelicRulesLoader = require("single.relic_rules_loader")
local RuntimeRelicStore = require("single.runtime_relic_store")

local RelicRegistry = {}

local RARITY_ORDER = { "COMMON", "RARE", "EPIC", "LEGENDARY" }
local DEFAULT_WEIGHTS = {
  COMMON = 0.62,
  RARE = 0.28,
  EPIC = 0.10,
  LEGENDARY = 0.00
}

local cachedData = nil

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

local function normalizeRarity(value)
  local text = tostring(value or "COMMON"):upper()
  for _, rarity in ipairs(RARITY_ORDER) do
    if text == rarity then
      return rarity
    end
  end
  return "COMMON"
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
  if seed and love and love.math and type(love.math.newRandomGenerator) == "function" then
    return love.math.newRandomGenerator(seed)
  end
  return nil
end

local function ensureLoaded()
  if not cachedData then
    cachedData = RelicRulesLoader.load()
  end
  return cachedData
end

local function getOwnedSet(runState)
  local ownedSet = {}
  if type(runState) == "table" and type(runState.relicIds) == "table" then
    for _, relicId in ipairs(runState.relicIds) do
      local key = tostring(relicId or "")
      if key ~= "" then
        ownedSet[key] = true
      end
    end
  end
  return ownedSet
end

local function pickWeightedRarity(weights, rng)
  local total = 0
  for _, rarity in ipairs(RARITY_ORDER) do
    local weight = math.max(0, tonumber(weights[rarity]) or 0)
    total = total + weight
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
  for index, value in ipairs(RARITY_ORDER) do
    if value == rarity then
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

function RelicRegistry.resetCache()
  cachedData = nil
end

function RelicRegistry.listAll()
  local data = ensureLoaded()
  local list = {}
  for _, relic in ipairs(data.relics or {}) do
    list[#list + 1] = deepCopy(relic)
  end
  return list
end

function RelicRegistry.getRelic(relicId)
  local targetId = tostring(relicId or "")
  if targetId == "" then
    return nil
  end
  local data = ensureLoaded()
  for _, relic in ipairs(data.relics or {}) do
    if tostring(relic.relicId or "") == targetId then
      local copied = deepCopy(relic)
      copied.rarity = normalizeRarity(copied.rarity)
      return copied
    end
  end
  local runtimeRelic = RuntimeRelicStore.get(targetId)
  if runtimeRelic then
    return runtimeRelic
  end
  return nil
end

function RelicRegistry.listByRarity(rarity)
  local targetRarity = normalizeRarity(rarity)
  local list = {}
  for _, relic in ipairs(RelicRegistry.listAll()) do
    if normalizeRarity(relic.rarity) == targetRarity then
      list[#list + 1] = relic
    end
  end
  return list
end

function RelicRegistry.pickRewardChoices(options)
  local opts = type(options) == "table" and options or {}
  local count = math.max(1, math.floor(tonumber(opts.count) or 3))
  local isBoss = opts.isBoss == true
  local runState = opts.runState
  local rng = makeRng(opts.rngSeed)

  local weights = deepCopy(DEFAULT_WEIGHTS)
  if isBoss then
    weights.EPIC = 0.16
    weights.RARE = 0.30
    weights.COMMON = 0.54
  end

  local ownedSet = getOwnedSet(runState)
  local candidateList = {}
  for _, relic in ipairs(RelicRegistry.listAll()) do
    local relicId = tostring(relic.relicId or "")
    if relicId ~= "" and not ownedSet[relicId] then
      relic.rarity = normalizeRarity(relic.rarity)
      candidateList[#candidateList + 1] = relic
    end
  end

  if #candidateList <= 0 then
    candidateList = RelicRegistry.listAll()
    for _, relic in ipairs(candidateList) do
      relic.rarity = normalizeRarity(relic.rarity)
    end
  end

  local bucketByRarity = {
    COMMON = {},
    RARE = {},
    EPIC = {},
    LEGENDARY = {}
  }
  for _, relic in ipairs(candidateList) do
    bucketByRarity[relic.rarity][#bucketByRarity[relic.rarity] + 1] = relic
  end

  local picked = {}
  local pickedSet = {}
  for _ = 1, count do
    local preferred = pickWeightedRarity(weights, rng)
    local choice = pickFromBucketsWithFallback(bucketByRarity, preferred, rng)
    if not choice then
      break
    end
    local relicId = tostring(choice.relicId or "")
    if relicId ~= "" and not pickedSet[relicId] then
      pickedSet[relicId] = true
      picked[#picked + 1] = choice
    end
  end

  if #picked < count then
    for _, relic in ipairs(candidateList) do
      local relicId = tostring(relic.relicId or "")
      if relicId ~= "" and not pickedSet[relicId] then
        pickedSet[relicId] = true
        picked[#picked + 1] = relic
        if #picked >= count then
          break
        end
      end
    end
  end

  while #picked < count and #candidateList > 0 do
    picked[#picked + 1] = candidateList[randomInt(rng, 1, #candidateList)]
  end

  local result = {}
  for _, relic in ipairs(picked) do
    result[#result + 1] = deepCopy(relic)
  end
  return result
end

return RelicRegistry
