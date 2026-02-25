--[[
파일명: relic_effects.lua
모듈명: RelicEffects

역할:
- runState.relicIds 기반 전투/경제 수치를 계산한다.
- 사이드 이펙트 없이 순수 계산 함수만 제공한다.
]]

local RelicRegistry = require("single.relic_registry")

local RelicEffects = {}
local COMBAT_MULTIPLIER_DEFAULTS = {
  maxShotPowerMul = 1.0,
  shotSpeedScaleMul = 1.0,
  physicsDampingPerSecMul = 1.0,
  stoneRadiusMul = 1.0,
  stoneMassMul = 1.0
}

local function getRelicList(runState)
  if type(runState) ~= "table" or type(runState.relicIds) ~= "table" then
    return {}
  end
  local list = {}
  for _, relicId in ipairs(runState.relicIds) do
    local relic = RelicRegistry.getRelic(relicId)
    if relic then
      list[#list + 1] = relic
    end
  end
  return list
end

local function readPositiveNumber(value, fallback)
  if type(value) == "number" and value > 0 and value == value and value ~= math.huge and value ~= -math.huge then
    return value
  end
  return fallback
end

local function cloneMultiplierDefaults()
  return {
    maxShotPowerMul = COMBAT_MULTIPLIER_DEFAULTS.maxShotPowerMul,
    shotSpeedScaleMul = COMBAT_MULTIPLIER_DEFAULTS.shotSpeedScaleMul,
    physicsDampingPerSecMul = COMBAT_MULTIPLIER_DEFAULTS.physicsDampingPerSecMul,
    stoneRadiusMul = COMBAT_MULTIPLIER_DEFAULTS.stoneRadiusMul,
    stoneMassMul = COMBAT_MULTIPLIER_DEFAULTS.stoneMassMul
  }
end

function RelicEffects.buildPlayerCombatMultipliers(runState)
  local multipliers = cloneMultiplierDefaults()
  for _, relic in ipairs(getRelicList(runState)) do
    local tunables = type(relic.tunables) == "table" and relic.tunables or {}
    multipliers.maxShotPowerMul = multipliers.maxShotPowerMul * readPositiveNumber(tunables.maxShotPowerMul, 1.0)
    multipliers.shotSpeedScaleMul = multipliers.shotSpeedScaleMul * readPositiveNumber(tunables.shotSpeedScaleMul, 1.0)
    multipliers.physicsDampingPerSecMul = multipliers.physicsDampingPerSecMul * readPositiveNumber(tunables.physicsDampingPerSecMul, 1.0)
    multipliers.stoneRadiusMul = multipliers.stoneRadiusMul * readPositiveNumber(tunables.stoneRadiusMul, 1.0)
    multipliers.stoneMassMul = multipliers.stoneMassMul * readPositiveNumber(tunables.stoneMassMul, 1.0)
  end
  return multipliers
end

function RelicEffects.applyCombatStartModifiers(runState, baseDrawCount)
  local drawCount = math.max(1, math.floor(tonumber(baseDrawCount) or 1))
  local drawPlus = 0
  for _, relic in ipairs(getRelicList(runState)) do
    local tunables = type(relic.tunables) == "table" and relic.tunables or {}
    drawPlus = drawPlus + math.max(0, math.floor(tonumber(tunables.drawPlus) or 0))
  end
  return math.max(1, drawCount + drawPlus)
end

function RelicEffects.applyShotModifiers(runState, baseMaxPower)
  local maxPower = math.max(1, tonumber(baseMaxPower) or 1)
  local multipliers = RelicEffects.buildPlayerCombatMultipliers(runState)
  local multiplier = readPositiveNumber(multipliers.maxShotPowerMul, 1.0)
  return math.max(1, math.floor(maxPower * multiplier + 0.5))
end

function RelicEffects.applyGoldModifiers(runState, baseGold)
  local gold = math.max(0, tonumber(baseGold) or 0)
  local multiplier = 1.0
  for _, relic in ipairs(getRelicList(runState)) do
    local tunables = type(relic.tunables) == "table" and relic.tunables or {}
    local mul = tonumber(tunables.goldRewardMul)
    if type(mul) == "number" and mul > 0 then
      multiplier = multiplier * mul
    end
  end
  return math.max(0, math.floor(gold * multiplier + 0.5))
end

return RelicEffects
