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

local function buildPhysicsContext(matchContext)
  return {
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
    end
  }
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
  local speed = math.max(0, shotPayload.power * Constants.SHOT_SPEED_SCALE)
  velocity.vx = shotPayload.dirX / directionLength * speed
  velocity.vy = shotPayload.dirY / directionLength * speed
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

return GameMechanics
