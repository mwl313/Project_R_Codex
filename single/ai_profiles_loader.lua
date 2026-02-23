--[[
파일명: ai_profiles_loader.lua
모듈명: AiProfilesLoader
]]

local LoaderUtils = require("single.single_json_loader")

local AiProfilesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  profiles = {
    {
      aiProfileId = "ai_easy_01",
      aimErrorDeg = 6.0,
      aggression = 0.4,
      riskTolerance = 0.3,
      skillUseRate = 0.2
    },
    {
      aiProfileId = "ai_boss_01",
      aimErrorDeg = 3.0,
      aggression = 0.7,
      riskTolerance = 0.6,
      skillUseRate = 0.6
    }
  }
}

local function sanitizeProfile(entry)
  local source = LoaderUtils.toTable(entry, {})
  return {
    aiProfileId = LoaderUtils.toString(source.aiProfileId, "ai_unknown"),
    aimErrorDeg = LoaderUtils.toNumber(source.aimErrorDeg, 6.0),
    aggression = LoaderUtils.toNumber(source.aggression, 0.5),
    riskTolerance = LoaderUtils.toNumber(source.riskTolerance, 0.5),
    skillUseRate = LoaderUtils.toNumber(source.skillUseRate, 0.3)
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    profiles = {}
  }

  for _, entry in ipairs(LoaderUtils.toArray(source.profiles, {})) do
    if type(entry) == "table" then
      sanitized.profiles[#sanitized.profiles + 1] = sanitizeProfile(entry)
    end
  end

  if #sanitized.profiles <= 0 then
    sanitized.profiles = LoaderUtils.deepCopy(DEFAULT_DATA.profiles)
  end
  return sanitized
end

function AiProfilesLoader.load()
  local raw = LoaderUtils.readJson("shared/ai_profiles.json", "ai_profiles")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return AiProfilesLoader
