--[[
파일명: reward_tables_loader.lua
모듈명: RewardTablesLoader
]]

local LoaderUtils = require("single.single_json_loader")

local RewardTablesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  rewardContexts = {
    {
      contextId = "combat_mob",
      nodeTypes = { "mob" },
      offerCount = 3,
      rarityWeightsRef = "base",
      allowLegendary = false,
      filters = { mode = "single", tagsAny = {} }
    },
    {
      contextId = "combat_elite",
      nodeTypes = { "elite" },
      offerCount = 3,
      rarityWeightsRef = "base",
      allowLegendary = false,
      filters = { mode = "single", tagsAny = {} }
    },
    {
      contextId = "combat_boss",
      nodeTypes = { "boss" },
      offerCount = 3,
      rarityWeightsRef = "base",
      allowLegendary = true,
      filters = { mode = "single", tagsAny = {} }
    },
    {
      contextId = "shop_buy",
      nodeTypes = { "shop" },
      offerCount = 3,
      rarityWeightsRef = "base",
      allowLegendary = false,
      filters = { mode = "single", tagsAny = {} }
    }
  }
}

local function sanitizeContext(entry)
  local source = LoaderUtils.toTable(entry, {})
  local filters = LoaderUtils.toTable(source.filters, {})
  local nodeTypes = {}
  for _, value in ipairs(LoaderUtils.toArray(source.nodeTypes, {})) do
    if type(value) == "string" and value ~= "" then
      nodeTypes[#nodeTypes + 1] = value
    end
  end
  if #nodeTypes <= 0 then
    nodeTypes = { "mob" }
  end

  local tagsAny = {}
  for _, value in ipairs(LoaderUtils.toArray(filters.tagsAny, {})) do
    if type(value) == "string" and value ~= "" then
      tagsAny[#tagsAny + 1] = value
    end
  end

  return {
    contextId = LoaderUtils.toString(source.contextId, "combat_mob"),
    nodeTypes = nodeTypes,
    offerCount = LoaderUtils.toNumber(source.offerCount, 3),
    rarityWeightsRef = LoaderUtils.toString(source.rarityWeightsRef, "base"),
    allowLegendary = LoaderUtils.toBoolean(source.allowLegendary, false),
    filters = {
      mode = LoaderUtils.toString(filters.mode, "single"),
      tagsAny = tagsAny
    }
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    rewardContexts = {}
  }

  local sourceContexts = LoaderUtils.toArray(source.rewardContexts, {})
  for _, entry in ipairs(sourceContexts) do
    if type(entry) == "table" then
      sanitized.rewardContexts[#sanitized.rewardContexts + 1] = sanitizeContext(entry)
    end
  end

  if #sanitized.rewardContexts <= 0 then
    sanitized.rewardContexts = LoaderUtils.deepCopy(DEFAULT_DATA.rewardContexts)
  end

  return sanitized
end

function RewardTablesLoader.load()
  local raw = LoaderUtils.readJson("shared/reward_tables.json", "reward_tables")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return RewardTablesLoader
