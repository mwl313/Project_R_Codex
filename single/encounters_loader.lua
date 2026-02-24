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
      gimmicks = { "boss_rockfall" }
    }
  },
  bosses = {
    {
      bossId = "boss_rockfall",
      stageIndex = 1,
      gimmicks = {
        { type = "auto_rockfall", everyTurns = 2, radius = 18 }
      }
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

local function sanitizeBossGimmick(entry)
  local source = LoaderUtils.toTable(entry, {})
  return {
    type = LoaderUtils.toString(source.type, ""),
    everyTurns = math.max(1, math.floor(LoaderUtils.toNumber(source.everyTurns, 1))),
    radius = math.max(1, math.floor(LoaderUtils.toNumber(source.radius, 18))),
    durationMs = math.max(1, math.floor(LoaderUtils.toNumber(source.durationMs, 600))),
    accel = math.max(0, LoaderUtils.toNumber(source.accel, 180)),
    durationTurns = math.max(1, math.floor(LoaderUtils.toNumber(source.durationTurns, 1)))
  }
end

local function sanitizeBoss(entry)
  local source = LoaderUtils.toTable(entry, {})
  local gimmicks = {}
  for _, gimmick in ipairs(LoaderUtils.toArray(source.gimmicks, {})) do
    if type(gimmick) == "table" then
      local sanitizedGimmick = sanitizeBossGimmick(gimmick)
      if sanitizedGimmick.type ~= "" then
        gimmicks[#gimmicks + 1] = sanitizedGimmick
      end
    end
  end

  return {
    bossId = LoaderUtils.toString(source.bossId, "boss_unknown"),
    stageIndex = math.max(1, math.floor(LoaderUtils.toNumber(source.stageIndex, 1))),
    gimmicks = gimmicks
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    encounters = {},
    bosses = {}
  }

  for _, entry in ipairs(LoaderUtils.toArray(source.encounters, {})) do
    if type(entry) == "table" then
      sanitized.encounters[#sanitized.encounters + 1] = sanitizeEncounter(entry)
    end
  end

  for _, entry in ipairs(LoaderUtils.toArray(source.bosses, {})) do
    if type(entry) == "table" then
      sanitized.bosses[#sanitized.bosses + 1] = sanitizeBoss(entry)
    end
  end

  if #sanitized.encounters <= 0 then
    sanitized.encounters = LoaderUtils.deepCopy(DEFAULT_DATA.encounters)
  end
  if #sanitized.bosses <= 0 then
    sanitized.bosses = LoaderUtils.deepCopy(DEFAULT_DATA.bosses)
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
