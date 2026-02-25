--[[
파일명: proc_relic_generator.lua
모듈명: ProcRelicGenerator

역할:
- 싱글 웨이브용 절차 유물 1개를 생성한다.
- 유물은 항상 버프 1개 + 디버프 1개 조합이다.
]]

local ProcRelicGenerator = {}

local PARAM_DEF_LIST = {
  {
    id = "max_shot_power",
    tunableKey = "maxShotPowerMul",
    direction = "UP_IS_BUFF",
    displayNameKo = "최대 샷 파워"
  },
  {
    id = "shot_speed_scale",
    tunableKey = "shotSpeedScaleMul",
    direction = "UP_IS_BUFF",
    displayNameKo = "샷 스피드"
  },
  {
    id = "physics_damping_per_sec",
    tunableKey = "physicsDampingPerSecMul",
    direction = "DOWN_IS_BUFF",
    displayNameKo = "마찰력(감쇠)"
  },
  {
    id = "stone_radius",
    tunableKey = "stoneRadiusMul",
    direction = "UP_IS_BUFF",
    displayNameKo = "알 크기"
  },
  {
    id = "stone_mass",
    tunableKey = "stoneMassMul",
    direction = "UP_IS_BUFF",
    displayNameKo = "알 무게"
  }
}

local TIER_BANDS = {
  buff = {
    UP_IS_BUFF = {
      [1] = { min = 1.03, max = 1.06 },
      [2] = { min = 1.07, max = 1.10 },
      [3] = { min = 1.11, max = 1.15 },
      [4] = { min = 1.16, max = 1.20 },
      [5] = { min = 1.21, max = 1.25 }
    },
    DOWN_IS_BUFF = {
      [1] = { min = 0.94, max = 0.97 },
      [2] = { min = 0.90, max = 0.93 },
      [3] = { min = 0.85, max = 0.89 },
      [4] = { min = 0.80, max = 0.84 },
      [5] = { min = 0.75, max = 0.79 }
    }
  },
  debuff = {
    UP_IS_BUFF = {
      [1] = { min = 0.96, max = 0.98 },
      [2] = { min = 0.93, max = 0.95 },
      [3] = { min = 0.90, max = 0.92 },
      [4] = { min = 0.86, max = 0.89 },
      [5] = { min = 0.82, max = 0.85 }
    },
    DOWN_IS_BUFF = {
      [1] = { min = 1.02, max = 1.04 },
      [2] = { min = 1.05, max = 1.07 },
      [3] = { min = 1.08, max = 1.10 },
      [4] = { min = 1.11, max = 1.14 },
      [5] = { min = 1.15, max = 1.18 }
    }
  }
}

local relicSerial = 0

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
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
  if type(seed) ~= "number" then
    return nil
  end
  if love and love.math and type(love.math.newRandomGenerator) == "function" then
    return love.math.newRandomGenerator(seed)
  end
  return nil
end

local function sanitizeRunId(runId)
  local source = tostring(runId or "run")
  return (source:gsub("[^%w_]", "_"))
end

local function pickTierValue(rng, tierBand)
  local minValue = tonumber(tierBand.min) or 1.0
  local maxValue = tonumber(tierBand.max) or minValue
  if maxValue < minValue then
    minValue, maxValue = maxValue, minValue
  end
  local sampled = minValue + (maxValue - minValue) * randomFloat(rng)
  return clamp(sampled, minValue, maxValue)
end

local function formatPercentSigned(multiplier)
  local deltaPercent = (tonumber(multiplier) or 1.0) - 1.0
  local rounded = math.floor(math.abs(deltaPercent) * 100 + 0.5)
  local sign = deltaPercent >= 0 and "+" or "-"
  return string.format("%s%d%%", sign, rounded)
end

local function determineRarity(rarityScore)
  if rarityScore <= 0 then
    return "Common"
  end
  if rarityScore == 1 then
    return "Uncommon"
  end
  if rarityScore == 2 then
    return "Rare"
  end
  return "Epic"
end

local function createRelicId(context, rarity)
  relicSerial = relicSerial + 1
  local runId = sanitizeRunId(context and context.runId)
  local stageIndex = math.max(1, math.floor(tonumber(context and context.stageIndex) or 1))
  local waveIndex = math.max(1, math.floor(tonumber(context and context.waveIndex) or 1))
  local slotIndex = math.max(1, math.floor(tonumber(context and context.optionSlotIndex) or 1))
  return string.format("proc_relic_%s_s%d_w%d_o%d_%04d_%s", runId, stageIndex, waveIndex, slotIndex, relicSerial, string.lower(tostring(rarity or "common")))
end

local function composeLine(prefixText, paramDisplayName, multiplier, tier)
  return string.format("%s: %s %s (T%d)", prefixText, tostring(paramDisplayName), formatPercentSigned(multiplier), tier)
end

function ProcRelicGenerator.createRelic(context)
  local stageIndex = math.max(1, math.floor(tonumber(context and context.stageIndex) or 1))
  local waveIndex = math.max(1, math.floor(tonumber(context and context.waveIndex) or 1))
  local optionSlotIndex = math.max(1, math.floor(tonumber(context and context.optionSlotIndex) or 1))
  local runSeed = tonumber(context and context.runSeed)
  local localRng = nil
  local derivedSeed = nil
  if type(runSeed) == "number" then
    derivedSeed = runSeed + stageIndex * 10007 + waveIndex * 379 + optionSlotIndex * 53
    localRng = makeRng(derivedSeed)
  end
  local rng = localRng or (context and context.rng)

  local buffParamIndex = randomInt(rng, 1, #PARAM_DEF_LIST)
  local debuffParamIndex = buffParamIndex
  while debuffParamIndex == buffParamIndex do
    debuffParamIndex = randomInt(rng, 1, #PARAM_DEF_LIST)
  end

  local buffParam = PARAM_DEF_LIST[buffParamIndex]
  local debuffParam = PARAM_DEF_LIST[debuffParamIndex]
  local buffTier = randomInt(rng, 1, 5)
  local debuffTier = randomInt(rng, 1, buffTier)
  local rarityScore = buffTier - debuffTier
  local rarity = determineRarity(rarityScore)

  local buffBand = TIER_BANDS.buff[buffParam.direction][buffTier]
  local debuffBand = TIER_BANDS.debuff[debuffParam.direction][debuffTier]
  local buffMul = pickTierValue(rng, buffBand)
  local debuffMul = pickTierValue(rng, debuffBand)

  local tunables = {
    maxShotPowerMul = 1.0,
    shotSpeedScaleMul = 1.0,
    physicsDampingPerSecMul = 1.0,
    stoneRadiusMul = 1.0,
    stoneMassMul = 1.0
  }
  tunables[buffParam.tunableKey] = buffMul
  tunables[debuffParam.tunableKey] = debuffMul

  local buffLine = composeLine("버프", buffParam.displayNameKo, buffMul, buffTier)
  local debuffLine = composeLine("디버프", debuffParam.displayNameKo, debuffMul, debuffTier)
  local relicId = createRelicId(context, rarity)

  return {
    id = relicId,
    relicId = relicId,
    name = string.format("절차 유물 (%s)", rarity),
    rarity = rarity,
    buffLines = { buffLine },
    debuffLines = { debuffLine },
    descText = buffLine .. " | " .. debuffLine,
    meta = {
      buffParamKey = buffParam.id,
      debuffParamKey = debuffParam.id,
      buffTier = buffTier,
      debuffTier = debuffTier,
      buffMul = buffMul,
      debuffMul = debuffMul,
      rarityScore = rarityScore,
      stageIndex = stageIndex,
      waveIndex = waveIndex,
      optionSlotIndex = optionSlotIndex,
      seed = derivedSeed
    },
    tunables = tunables
  }
end

return ProcRelicGenerator
