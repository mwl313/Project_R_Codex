--[[
파일명: game_mechanics.lua
모듈명: GameMechanics

역할:
- 매치 물리/턴 시뮬레이션 진입점을 한 곳으로 통합한다.
- 멀티플레이/싱글플레이가 동일한 메커니즘 API를 참조하도록 한다.

외부에서 사용 가능한 함수:
- GameMechanics.resetStoneVelocities(matchContext)
- GameMechanics.syncStoneVelocityMap(matchContext)
- GameMechanics.startShotSimulation(matchContext)
- GameMechanics.stopShotSimulation(matchContext)
- GameMechanics.applyShotImpulse(matchContext, shotPayload)
- GameMechanics.resolveObstacleCollision(matchContext, stone, obstacle)
- GameMechanics.resolveStoneCollision(matchContext, firstStone, secondStone)
- GameMechanics.simulateShotStep(matchContext, stepSec)
- GameMechanics.hasAnyStoneInMotion(matchContext)
- GameMechanics.updateShotSimulation(matchContext, dt)

주의:
- matchContext는 기존 MatchScene 필드/함수를 제공해야 한다.
]]

local Constants = require("constants")
local PhysicsEngine = require("physics_engine")

local GameMechanics = {}

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function buildPhysicsContext(matchContext)
  local context = {
    constants = Constants,
    stoneList = matchContext._playingStoneList,
    obstacleList = matchContext._obstacleList,
    getStoneVelocity = function(stoneId)
      return matchContext:getStoneVelocity(stoneId)
    end,
    isShockwaveShotStone = function(stoneId)
      return matchContext:isShockwaveShotStone(stoneId)
    end,
    applyShockwaveFromPoint = function(canonicalX, canonicalY)
      matchContext:applyShockwaveFromPoint(canonicalX, canonicalY)
    end,
    isInvincibleOnCurrentTurn = function(playerIndex)
      return matchContext:isInvincibleOnCurrentTurn(playerIndex)
    end,
    applyInvincibleCollisionResponse = function(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
      if type(matchContext.applyInvincibleCollisionResponse) == "function" then
        return matchContext:applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
      end
      return false
    end,
    onCollision = function(cx, cy)
      if matchContext._effectManager then
        matchContext._effectManager:addCollisionEffect(cx, cy, 0.5)
      end
    end
  }
  if type(matchContext.getStoneRadius) == "function" then
    context.getStoneRadius = function(stone)
      return matchContext:getStoneRadius(stone)
    end
  end
  if type(matchContext.getStoneMass) == "function" then
    context.getStoneMass = function(stone)
      return matchContext:getStoneMass(stone)
    end
  end
  if type(matchContext.getStoneDampingPerSec) == "function" then
    context.getStoneDampingPerSec = function(stone)
      return matchContext:getStoneDampingPerSec(stone)
    end
  end
  if type(matchContext.shouldTreatOutAsWall) == "function" then
    context.shouldTreatOutAsWall = function(stone)
      return matchContext:shouldTreatOutAsWall(stone)
    end
  end
  if type(matchContext.consumePiercingCollision) == "function" then
    context.consumePiercingCollision = function(stone, collisionKind)
      return matchContext:consumePiercingCollision(stone, collisionKind)
    end
  end
  return context
end

function GameMechanics.resetStoneVelocities(matchContext)
  matchContext._stoneVelocityMap = {}
  for _, stone in ipairs(matchContext._playingStoneList) do
    matchContext._stoneVelocityMap[stone.id] = { vx = 0, vy = 0 }
  end
end

function GameMechanics.syncStoneVelocityMap(matchContext)
  local nextVelocityMap = {}
  for _, stone in ipairs(matchContext._playingStoneList) do
    local velocity = matchContext._stoneVelocityMap[stone.id]
    if velocity then
      nextVelocityMap[stone.id] = { vx = velocity.vx, vy = velocity.vy }
    else
      nextVelocityMap[stone.id] = { vx = 0, vy = 0 }
    end
    if stone.alive == false then
      nextVelocityMap[stone.id].vx = 0
      nextVelocityMap[stone.id].vy = 0
    end
  end
  matchContext._stoneVelocityMap = nextVelocityMap
end

function GameMechanics.startShotSimulation(matchContext)
  matchContext._simAccumulatorSec = 0
  matchContext._simElapsedSec = 0
  matchContext._isShotSimulating = true
end

function GameMechanics.stopShotSimulation(matchContext)
  matchContext._simAccumulatorSec = 0
  matchContext._simElapsedSec = 0
  matchContext._isShotSimulating = false

  if matchContext._shouldSendSnapshotAfterSim then
    matchContext._shouldSendSnapshotAfterSim = false
    matchContext:sendHostSnapshotIfNeeded(matchContext._playingTurnIndex, "sim_done")
  end
end

function GameMechanics.applyShotImpulse(matchContext, shotPayload)
  if type(shotPayload) ~= "table" then
    return
  end
  if type(shotPayload.stoneId) ~= "string" then
    return
  end
  if type(shotPayload.dirX) ~= "number" or type(shotPayload.dirY) ~= "number" or type(shotPayload.power) ~= "number" then
    return
  end

  local stone = matchContext:getPlayingStoneById(shotPayload.stoneId)
  if not stone or stone.alive == false then
    return
  end

  local directionLength = math.sqrt(shotPayload.dirX * shotPayload.dirX + shotPayload.dirY * shotPayload.dirY)
  if directionLength <= 0 then
    return
  end

  local velocity = matchContext:getStoneVelocity(stone.id)
  local speedScale = nil
  if isFiniteNumber(shotPayload.shotSpeedScale) and shotPayload.shotSpeedScale > 0 then
    speedScale = shotPayload.shotSpeedScale
  elseif type(matchContext.getShotSpeedScaleForStone) == "function" then
    local autoScale = matchContext:getShotSpeedScaleForStone(stone)
    if isFiniteNumber(autoScale) and autoScale > 0 then
      speedScale = autoScale
    end
  end
  if not speedScale then
    speedScale = Constants.SHOT_SPEED_SCALE
  end
  local speed = math.max(0, shotPayload.power * speedScale)
  velocity.vx = shotPayload.dirX / directionLength * speed
  velocity.vy = shotPayload.dirY / directionLength * speed
  if type(matchContext.onShotImpulseApplied) == "function" then
    matchContext:onShotImpulseApplied(stone, shotPayload)
  end
  if matchContext._shockwaveOwnerPlayerIndex and stone.ownerPlayerIndex == matchContext._shockwaveOwnerPlayerIndex then
    matchContext._shockwaveSourceStoneId = stone.id
  else
    matchContext._shockwaveSourceStoneId = nil
  end
  GameMechanics.startShotSimulation(matchContext)
end

function GameMechanics.resolveObstacleCollision(matchContext, stone, obstacle)
  return PhysicsEngine.resolveObstacleCollision(buildPhysicsContext(matchContext), stone, obstacle)
end

function GameMechanics.resolveStoneCollision(matchContext, firstStone, secondStone)
  return PhysicsEngine.resolveStoneCollision(buildPhysicsContext(matchContext), firstStone, secondStone)
end

function GameMechanics.simulateShotStep(matchContext, stepSec)
  PhysicsEngine.simulateShotStep(buildPhysicsContext(matchContext), stepSec)
end

function GameMechanics.hasAnyStoneInMotion(matchContext)
  return PhysicsEngine.hasAnyStoneInMotion(buildPhysicsContext(matchContext))
end

function GameMechanics.updateShotSimulation(matchContext, dt)
  if not matchContext._isShotSimulating then
    return
  end

  local physicsContext = buildPhysicsContext(matchContext)
  matchContext._simAccumulatorSec = matchContext._simAccumulatorSec + math.min(dt, 0.05)
  while matchContext._simAccumulatorSec >= Constants.PHYSICS_FIXED_STEP_SEC do
    PhysicsEngine.simulateShotStep(physicsContext, Constants.PHYSICS_FIXED_STEP_SEC)
    matchContext._simAccumulatorSec = matchContext._simAccumulatorSec - Constants.PHYSICS_FIXED_STEP_SEC
    matchContext._simElapsedSec = matchContext._simElapsedSec + Constants.PHYSICS_FIXED_STEP_SEC

    if (not PhysicsEngine.hasAnyStoneInMotion(physicsContext)) or matchContext._simElapsedSec >= Constants.PHYSICS_MAX_SIM_SEC then
      GameMechanics.stopShotSimulation(matchContext)
      break
    end
  end
end

-- 충전 상태 관리 (초능력 시스템)

function GameMechanics.initChargeState(matchContext)
  matchContext._chargePercent = { [1] = 0, [2] = 0 }
  matchContext._characterIds = { [1] = "", [2] = "" }
end

function GameMechanics.advanceTurnCharge(matchContext, playerIndex)
  if type(matchContext._chargePercent) ~= "table" then
    GameMechanics.initChargeState(matchContext)
  end
  local current = tonumber(matchContext._chargePercent[playerIndex]) or 0
  local nextCharge = math.min(Constants.CHARGE_MAX, current + Constants.CHARGE_PER_TURN)
  matchContext._chargePercent[playerIndex] = nextCharge
  matchContext._chargePercent[tostring(playerIndex)] = nextCharge
end

function GameMechanics.addChargeOnAllyOut(matchContext, playerIndex)
  if type(matchContext._chargePercent) ~= "table" then
    GameMechanics.initChargeState(matchContext)
  end
  local current = tonumber(matchContext._chargePercent[playerIndex]) or 0
  local nextCharge = math.min(Constants.CHARGE_MAX, current + Constants.CHARGE_ON_ALLY_OUT)
  matchContext._chargePercent[playerIndex] = nextCharge
  matchContext._chargePercent[tostring(playerIndex)] = nextCharge
end

function GameMechanics.canUseAbility(matchContext, playerIndex)
  if type(matchContext._chargePercent) ~= "table" then
    return false
  end
  local charge = tonumber(matchContext._chargePercent[playerIndex]) or 0
  return charge >= Constants.CHARGE_MAX - 0.001
end

function GameMechanics.consumeCharge(matchContext, playerIndex)
  if type(matchContext._chargePercent) ~= "table" then
    GameMechanics.initChargeState(matchContext)
  end
  matchContext._chargePercent[playerIndex] = 0
  matchContext._chargePercent[tostring(playerIndex)] = 0
end

return GameMechanics
