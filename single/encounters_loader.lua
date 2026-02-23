--[[
파일명: encounters_loader.lua
모듈명: EncountersLoader
]]

local LoaderUtils = require("single.single_json_loader")

local EncountersLoader = {}

local DEFAULT_DATA = {
  version = 1,
  encounters = {
    {
      encounterId = "stage1_mob_01",
      type = "mob",
      stageIndex = 1,
      aiProfileId = "ai_easy_01",
      enemyModifiers = {
        extraStones = 0,
        maxShotPowerMul = 1.0
      },
      gimmicks = {}
    },
    {
      encounterId = "stage1_boss_01",
      type = "boss",
      stageIndex = 1,
      aiProfileId = "ai_boss_01",
      enemyModifiers = {
        extraStones = 1,
        maxShotPowerMul = 1.05
      },
      gimmicks = { "boss_gimmick_stub" }
    }
  }
}

local function sanitizeEncounter(entry)
  local source = LoaderUtils.toTable(entry, {})
  local enemyModifiers = LoaderUtils.toTable(source.enemyModifiers, {})
  local gimmicks = {}
  for _, gimmick in ipairs(LoaderUtils.toArray(source.gimmicks, {})) do
    if type(gimmick) == "string" and gimmick ~= "" then
      gimmicks[#gimmicks + 1] = gimmick
    end
  end

  return {
    encounterId = LoaderUtils.toString(source.encounterId, "encounter_unknown"),
    type = LoaderUtils.toString(source.type, "mob"),
    stageIndex = LoaderUtils.toNumber(source.stageIndex, 1),
    aiProfileId = LoaderUtils.toString(source.aiProfileId, "ai_easy_01"),
    enemyModifiers = {
      extraStones = LoaderUtils.toNumber(enemyModifiers.extraStones, 0),
      maxShotPowerMul = LoaderUtils.toNumber(enemyModifiers.maxShotPowerMul, 1.0)
    },
    gimmicks = gimmicks
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    encounters = {}
  }

  for _, entry in ipairs(LoaderUtils.toArray(source.encounters, {})) do
    if type(entry) == "table" then
      sanitized.encounters[#sanitized.encounters + 1] = sanitizeEncounter(entry)
    end
  end

  if #sanitized.encounters <= 0 then
    sanitized.encounters = LoaderUtils.deepCopy(DEFAULT_DATA.encounters)
  end

  return sanitized
end

function EncountersLoader.load()
  local raw = LoaderUtils.readJson("shared/encounters.json", "encounters")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return EncountersLoader
