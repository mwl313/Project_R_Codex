--[[
파일명: relic_rules_loader.lua
모듈명: RelicRulesLoader
]]

local LoaderUtils = require("single.single_json_loader")

local RelicRulesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  relics = {
    {
      relicId = "relic_stub_01",
      rarity = "COMMON",
      tags = { "UTILITY" },
      tunables = { value = 1 }
    }
  }
}

local function sanitizeRelic(entry)
  local source = LoaderUtils.toTable(entry, {})
  local tags = {}
  for _, tag in ipairs(LoaderUtils.toArray(source.tags, {})) do
    if type(tag) == "string" and tag ~= "" then
      tags[#tags + 1] = tag
    end
  end

  local tunables = LoaderUtils.toTable(source.tunables, {})
  return {
    relicId = LoaderUtils.toString(source.relicId, "relic_unknown"),
    rarity = LoaderUtils.toString(source.rarity, "COMMON"),
    tags = tags,
    tunables = LoaderUtils.deepCopy(tunables)
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    relics = {}
  }

  for _, entry in ipairs(LoaderUtils.toArray(source.relics, {})) do
    if type(entry) == "table" then
      sanitized.relics[#sanitized.relics + 1] = sanitizeRelic(entry)
    end
  end

  if #sanitized.relics <= 0 then
    sanitized.relics = LoaderUtils.deepCopy(DEFAULT_DATA.relics)
  end
  return sanitized
end

function RelicRulesLoader.load()
  local raw = LoaderUtils.readJson("shared/relic_rules.json", "relic_rules")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return RelicRulesLoader
