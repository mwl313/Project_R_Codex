--[[
파일명: single_combat_tuning.lua
모듈명: SingleCombatTuning

역할:
- 싱글 전투에서 플레이어/AI 별 물리/샷 튜닝값을 계산한다.
- 기본 상수 + 유물(플레이어) + encounter(enemyModifiers) 배율을 합성한다.
- 멀티플레이 경로에는 영향을 주지 않는다.
]]

local Constants = require("constants")
local EncountersLoader = require("single.encounters_loader")
local RelicEffects = require("single.relic_effects")

local SingleCombatTuning = {}

local CLAMP_RANGE = {
  maxShotPower = { min = 200, max = 5000 },
  shotSpeedScale = { min = 0.10, max = 3.00 },
  physicsDampingPerSec = { min = 0.00, max = 10.00 },
  stoneRadius = { min = 6.00, max = 40.00 },
  stoneMass = { min = 0.10, max = 20.00 }
}

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function readPositiveMultiplier(value)
  if isFiniteNumber(value) and value > 0 then
    return value
  end
  return 1.0
end

local function getBaseStats()
  return {
    maxShotPower = math.max(1, tonumber(Constants.MAX_SHOT_POWER) or 1),
    shotSpeedScale = math.max(0.01, tonumber(Constants.SHOT_SPEED_SCALE) or 0.01),
    physicsDampingPerSec = math.max(0, tonumber(Constants.PHYSICS_DAMPING_PER_SEC) or 0),
    stoneRadius = math.max(1, tonumber(Constants.STONE_RADIUS) or 1),
    stoneMass = math.max(0.01, tonumber(Constants.STONE_MASS) or 0.01)
  }
end

local function applyMultipliers(baseStats, multipliers)
  local stats = {}
  stats.maxShotPower = clamp(baseStats.maxShotPower * readPositiveMultiplier(multipliers.maxShotPowerMul), CLAMP_RANGE.maxShotPower.min, CLAMP_RANGE.maxShotPower.max)
  stats.shotSpeedScale = clamp(baseStats.shotSpeedScale * readPositiveMultiplier(multipliers.shotSpeedScaleMul), CLAMP_RANGE.shotSpeedScale.min, CLAMP_RANGE.shotSpeedScale.max)
  stats.physicsDampingPerSec = clamp(baseStats.physicsDampingPerSec * readPositiveMultiplier(multipliers.physicsDampingPerSecMul), CLAMP_RANGE.physicsDampingPerSec.min, CLAMP_RANGE.physicsDampingPerSec.max)
  stats.stoneRadius = clamp(baseStats.stoneRadius * readPositiveMultiplier(multipliers.stoneRadiusMul), CLAMP_RANGE.stoneRadius.min, CLAMP_RANGE.stoneRadius.max)
  stats.stoneMass = clamp(baseStats.stoneMass * readPositiveMultiplier(multipliers.stoneMassMul), CLAMP_RANGE.stoneMass.min, CLAMP_RANGE.stoneMass.max)
  return stats
end

local function findEncounter(nodeType, stageIndex)
  local data = EncountersLoader.load()
  local targetType = tostring(nodeType or "mob")
  local targetStageIndex = math.max(1, math.floor(tonumber(stageIndex) or 1))
  local encounterList = type(data.encounters) == "table" and data.encounters or {}

  for _, encounter in ipairs(encounterList) do
    if tostring(encounter.type or "mob") == targetType and math.max(1, math.floor(tonumber(encounter.stageIndex) or 1)) == targetStageIndex then
      return encounter
    end
  end
  for _, encounter in ipairs(encounterList) do
    if tostring(encounter.type or "mob") == targetType then
      return encounter
    end
  end
  for _, encounter in ipairs(encounterList) do
    if tostring(encounter.type or "mob") == "mob" then
      return encounter
    end
  end
  return nil
end

local function getEnemyMultipliers(encounter)
  local multipliers = {
    maxShotPowerMul = 1.0,
    shotSpeedScaleMul = 1.0,
    physicsDampingPerSecMul = 1.0,
    stoneRadiusMul = 1.0,
    stoneMassMul = 1.0
  }
  if type(encounter) ~= "table" then
    return multipliers
  end
  local enemyModifiers = type(encounter.enemyModifiers) == "table" and encounter.enemyModifiers or {}
  local combatStatsMul = type(enemyModifiers.combatStatsMul) == "table" and enemyModifiers.combatStatsMul or {}

  multipliers.maxShotPowerMul = readPositiveMultiplier(combatStatsMul.maxShotPowerMul)
  multipliers.shotSpeedScaleMul = readPositiveMultiplier(combatStatsMul.shotSpeedScaleMul)
  multipliers.physicsDampingPerSecMul = readPositiveMultiplier(combatStatsMul.physicsDampingPerSecMul)
  multipliers.stoneRadiusMul = readPositiveMultiplier(combatStatsMul.stoneRadiusMul)
  multipliers.stoneMassMul = readPositiveMultiplier(combatStatsMul.stoneMassMul)

  -- 하위 호환: 기존 maxShotPowerMul 필드를 함께 반영한다.
  multipliers.maxShotPowerMul = multipliers.maxShotPowerMul * readPositiveMultiplier(enemyModifiers.maxShotPowerMul)
  return multipliers
end

function SingleCombatTuning.build(params)
  local options = type(params) == "table" and params or {}
  local baseStats = getBaseStats()
  local encounter = findEncounter(options.nodeType, options.stageIndex)
  local playerMultipliers = RelicEffects.buildPlayerCombatMultipliers(options.runState)
  local enemyMultipliers = getEnemyMultipliers(encounter)

  return {
    byPlayerIndex = {
      [1] = applyMultipliers(baseStats, playerMultipliers),
      [2] = applyMultipliers(baseStats, enemyMultipliers)
    },
    sourceDebug = {
      encounterId = encounter and tostring(encounter.encounterId or "") or ""
    }
  }
end

return SingleCombatTuning
