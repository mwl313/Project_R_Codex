--[[
파일명: single_ai.lua
모듈명: SingleAI

역할:
- 싱글 전투용 간단 휴리스틱 AI 샷 선택을 담당한다.
- 물리 예측은 공용 PhysicsEngine을 사용해 멀티와 동일한 충돌 규칙을 따른다.
]]

local Constants = require("constants")
local PhysicsEngine = require("physics_engine")

local SingleAI = {}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end
  if math.atan then
    local isOk, value = pcall(math.atan, y, x)
    if isOk and type(value) == "number" then
      return value
    end
  end
  if x > 0 then
    return math.atan(y / x)
  end
  if x < 0 and y >= 0 then
    return math.atan(y / x) + math.pi
  end
  if x < 0 and y < 0 then
    return math.atan(y / x) - math.pi
  end
  if x == 0 and y > 0 then
    return math.pi * 0.5
  end
  if x == 0 and y < 0 then
    return -math.pi * 0.5
  end
  return 0
end

local function copyStoneList(stoneList)
  local copied = {}
  for _, stone in ipairs(stoneList or {}) do
    copied[#copied + 1] = {
      id = stone.id,
      ownerPlayerIndex = stone.ownerPlayerIndex,
      x = stone.x,
      y = stone.y,
      alive = stone.alive ~= false
    }
  end
  return copied
end

local function copyObstacleList(obstacleList)
  local copied = {}
  for _, obstacle in ipairs(obstacleList or {}) do
    copied[#copied + 1] = {
      id = obstacle.id,
      x = obstacle.x,
      y = obstacle.y,
      width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
      height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    }
  end
  return copied
end

local function buildVelocityMap(stoneList)
  local map = {}
  for _, stone in ipairs(stoneList or {}) do
    map[stone.id] = { vx = 0, vy = 0 }
  end
  return map
end

local function getStoneById(stoneList, stoneId)
  for _, stone in ipairs(stoneList or {}) do
    if stone.id == stoneId then
      return stone
    end
  end
  return nil
end

local function countAlive(stoneList, playerIndex)
  local count = 0
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false and stone.ownerPlayerIndex == playerIndex then
      count = count + 1
    end
  end
  return count
end

local function distanceToEdge(stone, boardW, boardH, radius)
  local left = stone.x - radius
  local right = boardW - radius - stone.x
  local top = stone.y - radius
  local bottom = boardH - radius - stone.y
  return math.min(left, right, top, bottom)
end

local function getNodeTier(nodeType)
  if nodeType == "boss" then
    return "boss"
  end
  if nodeType == "elite" then
    return "elite"
  end
  return "mob"
end

local function getTierConfig(nodeType)
  local tier = getNodeTier(nodeType)
  if tier == "boss" then
    return {
      candidateCount = 60,
      aimErrorDeg = 4.0,
      powerMinRatio = 0.40
    }
  end
  if tier == "elite" then
    return {
      candidateCount = 35,
      aimErrorDeg = 8.0,
      powerMinRatio = 0.35
    }
  end
  return {
    candidateCount = 15,
    aimErrorDeg = 13.0,
    powerMinRatio = 0.30
  }
end

local function makeRng(seed)
  if love and love.math and love.math.newRandomGenerator then
    return love.math.newRandomGenerator(seed or os.time())
  end
  math.randomseed(seed or os.time())
  return nil
end

local function randomRange(rng, minValue, maxValue)
  if rng and type(rng.random) == "function" then
    return rng:random() * (maxValue - minValue) + minValue
  end
  return math.random() * (maxValue - minValue) + minValue
end

local function randomInt(rng, minValue, maxValue)
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function buildAliveLists(stoneList, aiPlayerIndex)
  local own = {}
  local enemy = {}
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false then
      if stone.ownerPlayerIndex == aiPlayerIndex then
        own[#own + 1] = stone
      else
        enemy[#enemy + 1] = stone
      end
    end
  end
  return own, enemy
end

local function pickShooterAndTarget(stoneList, aiPlayerIndex)
  local own, enemy = buildAliveLists(stoneList, aiPlayerIndex)
  if #own <= 0 or #enemy <= 0 then
    return nil, nil
  end

  local bestShooter = own[1]
  local bestTarget = enemy[1]
  local bestDistanceSq = math.huge

  for _, ownStone in ipairs(own) do
    for _, enemyStone in ipairs(enemy) do
      local dx = enemyStone.x - ownStone.x
      local dy = enemyStone.y - ownStone.y
      local distanceSq = dx * dx + dy * dy
      if distanceSq < bestDistanceSq then
        bestDistanceSq = distanceSq
        bestShooter = ownStone
        bestTarget = enemyStone
      end
    end
  end

  return bestShooter, bestTarget
end

local function makePhysicsContext(simStoneList, simObstacleList, velocityMap)
  local function getStoneRadius(_stone)
    return nil
  end
  local function getStoneMass(_stone)
    return nil
  end
  local function getStoneDampingPerSec(_stone)
    return nil
  end
  return {
    constants = Constants,
    stoneList = simStoneList,
    obstacleList = simObstacleList,
    getStoneVelocity = function(stoneId)
      local velocity = velocityMap[stoneId]
      if not velocity then
        velocity = { vx = 0, vy = 0 }
        velocityMap[stoneId] = velocity
      end
      return velocity
    end,
    isShockwaveShotStone = function(_stoneId)
      return false
    end,
    applyShockwaveFromPoint = function(_x, _y)
    end,
    isInvincibleOnCurrentTurn = function(_playerIndex)
      return false
    end,
    applyInvincibleCollisionResponse = function(_firstInvincible, _secondInvincible, _normalX, _normalY, _firstVelocity, _secondVelocity)
      return false
    end,
    getStoneRadius = getStoneRadius,
    getStoneMass = getStoneMass,
    getStoneDampingPerSec = getStoneDampingPerSec
  }
end

local function buildStatsResolver(params)
  local byPlayerIndex = (params and type(params.combatStatsByPlayerIndex) == "table") and params.combatStatsByPlayerIndex or {}

  local function getForOwner(ownerPlayerIndex, fieldName, fallback)
    local stats = byPlayerIndex[ownerPlayerIndex]
    if type(stats) ~= "table" then
      stats = byPlayerIndex[tostring(ownerPlayerIndex)]
    end
    if type(stats) ~= "table" then
      return fallback
    end
    local value = tonumber(stats[fieldName])
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
      return value
    end
    return fallback
  end

  return {
    getRadiusByOwner = function(ownerPlayerIndex)
      return math.max(1, getForOwner(ownerPlayerIndex, "stoneRadius", Constants.STONE_RADIUS))
    end,
    getMassByOwner = function(ownerPlayerIndex)
      return math.max(0.01, getForOwner(ownerPlayerIndex, "stoneMass", Constants.STONE_MASS or 1.0))
    end,
    getDampingByOwner = function(ownerPlayerIndex)
      return math.max(0, getForOwner(ownerPlayerIndex, "physicsDampingPerSec", Constants.PHYSICS_DAMPING_PER_SEC))
    end,
    getShotSpeedScaleByOwner = function(ownerPlayerIndex)
      return math.max(0.01, getForOwner(ownerPlayerIndex, "shotSpeedScale", Constants.SHOT_SPEED_SCALE))
    end
  }
end

local function makePhysicsContextWithResolver(simStoneList, simObstacleList, velocityMap, statsResolver)
  local physicsContext = makePhysicsContext(simStoneList, simObstacleList, velocityMap)
  physicsContext.getStoneRadius = function(stone)
    return statsResolver.getRadiusByOwner(stone and stone.ownerPlayerIndex or 1)
  end
  physicsContext.getStoneMass = function(stone)
    return statsResolver.getMassByOwner(stone and stone.ownerPlayerIndex or 1)
  end
  physicsContext.getStoneDampingPerSec = function(stone)
    return statsResolver.getDampingByOwner(stone and stone.ownerPlayerIndex or 1)
  end
  return physicsContext
end

local function evaluateCandidate(baseContext, shooterStoneId, candidate, statsResolver, shotSpeedScale)
  local beforeStoneList = baseContext.stoneList
  local afterStoneList = copyStoneList(baseContext.stoneList)
  local obstacleList = copyObstacleList(baseContext.obstacleList)
  local velocityMap = buildVelocityMap(afterStoneList)

  local shooter = getStoneById(afterStoneList, shooterStoneId)
  if not shooter or shooter.alive == false then
    return -math.huge
  end

  local speed = math.max(0, candidate.power * shotSpeedScale)
  local velocity = velocityMap[shooter.id]
  velocity.vx = candidate.dirX * speed
  velocity.vy = candidate.dirY * speed

  local physicsContext = makePhysicsContextWithResolver(afterStoneList, obstacleList, velocityMap, statsResolver)
  local maxSimSec = 0.50
  local elapsedSec = 0
  local stepSec = Constants.PHYSICS_FIXED_STEP_SEC

  while elapsedSec < maxSimSec do
    PhysicsEngine.simulateShotStep(physicsContext, stepSec)
    elapsedSec = elapsedSec + stepSec
    if not PhysicsEngine.hasAnyStoneInMotion(physicsContext) then
      break
    end
  end

  local aiIndex = baseContext.aiPlayerIndex
  local enemyIndex = aiIndex == 1 and 2 or 1
  local enemyOut = countAlive(beforeStoneList, enemyIndex) - countAlive(afterStoneList, enemyIndex)
  local selfOut = countAlive(beforeStoneList, aiIndex) - countAlive(afterStoneList, aiIndex)
  local score = (enemyOut * 1000) - (selfOut * 1200)

  local enemyEdgeDelta = 0
  local selfEdgeRisk = 0
  local beforeById = {}
  for _, stone in ipairs(beforeStoneList) do
    beforeById[stone.id] = stone
  end

  for _, afterStone in ipairs(afterStoneList) do
    if afterStone.alive ~= false then
      local beforeStone = beforeById[afterStone.id]
      if beforeStone and beforeStone.alive ~= false then
        local beforeRadius = statsResolver.getRadiusByOwner(beforeStone.ownerPlayerIndex)
        local afterRadius = statsResolver.getRadiusByOwner(afterStone.ownerPlayerIndex)
        local beforeEdge = distanceToEdge(beforeStone, Constants.BOARD_W, Constants.BOARD_H, beforeRadius)
        local afterEdge = distanceToEdge(afterStone, Constants.BOARD_W, Constants.BOARD_H, afterRadius)
        if afterStone.ownerPlayerIndex == enemyIndex then
          enemyEdgeDelta = enemyEdgeDelta + (beforeEdge - afterEdge)
        else
          local riskThreshold = afterRadius * 2.2
          selfEdgeRisk = selfEdgeRisk + math.max(0, riskThreshold - afterEdge)
        end
      end
    end
  end

  score = score + enemyEdgeDelta * 1.1 - selfEdgeRisk * 0.8
  return score
end

local function buildCandidate(rng, shooter, target, config, maxShotPower)
  local baseDx = target.x - shooter.x
  local baseDy = target.y - shooter.y
  local baseAngle = atan2(baseDy, baseDx)
  local errorRad = math.rad(config.aimErrorDeg)
  local angle = baseAngle + randomRange(rng, -errorRad, errorRad)
  local dirX = math.cos(angle)
  local dirY = math.sin(angle)
  local powerRatio = randomRange(rng, config.powerMinRatio, 1.0)
  local power = clamp(maxShotPower * powerRatio, 80, maxShotPower)
  return {
    dirX = dirX,
    dirY = dirY,
    power = power
  }
end

function SingleAI.chooseShot(params)
  local stoneList = params and params.stoneList or {}
  local obstacleList = params and params.obstacleList or {}
  local nodeType = params and params.nodeType or "mob"
  local aiPlayerIndex = params and tonumber(params.aiPlayerIndex) or 2
  local turnIndex = params and tonumber(params.turnIndex) or 1
  local maxShotPower = math.max(80, tonumber(params and params.maxShotPower) or Constants.MAX_SHOT_POWER)
  local statsResolver = buildStatsResolver(params)
  local shotSpeedScale = statsResolver.getShotSpeedScaleByOwner(aiPlayerIndex)

  local shooter, target = pickShooterAndTarget(stoneList, aiPlayerIndex)
  if not shooter or not target then
    return nil
  end

  local config = getTierConfig(nodeType)
  local rng = makeRng((os.time() * 31) + turnIndex * 17 + randomInt(nil, 1, 999))
  local bestCandidate = nil
  local bestScore = -math.huge

  local evalContext = {
    stoneList = stoneList,
    obstacleList = obstacleList,
    aiPlayerIndex = aiPlayerIndex
  }

  for _ = 1, config.candidateCount do
    local candidate = buildCandidate(rng, shooter, target, config, maxShotPower)
    local score = evaluateCandidate(evalContext, shooter.id, candidate, statsResolver, shotSpeedScale)
    if score > bestScore then
      bestScore = score
      bestCandidate = candidate
    end
  end

  if not bestCandidate then
    local fallbackDx = target.x - shooter.x
    local fallbackDy = target.y - shooter.y
    local fallbackLength = math.sqrt(fallbackDx * fallbackDx + fallbackDy * fallbackDy)
    if fallbackLength <= 0 then
      return nil
    end
    bestCandidate = {
      dirX = fallbackDx / fallbackLength,
      dirY = fallbackDy / fallbackLength,
      power = maxShotPower * 0.65
    }
  end

  return {
    stoneId = shooter.id,
    dirX = bestCandidate.dirX,
    dirY = bestCandidate.dirY,
    power = bestCandidate.power,
    shotSpeedScale = shotSpeedScale
  }
end

return SingleAI
