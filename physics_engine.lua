--[[
파일명: physics_engine.lua
모듈명: PhysicsEngine

역할:
- 공용 물리 시뮬레이션(충돌/감쇠/정지/아웃)을 담당한다.
- 멀티/싱글 씬에서 동일한 물리 규칙을 재사용할 수 있게 한다.

외부에서 사용 가능한 함수:
- PhysicsEngine.resolveObstacleCollision(context, stone, obstacle)
- PhysicsEngine.resolveStoneCollision(context, firstStone, secondStone)
- PhysicsEngine.simulateShotStep(context, stepSec)
- PhysicsEngine.hasAnyStoneInMotion(context)

주의:
- context는 stoneList/obstacleList/getStoneVelocity 콜백을 제공해야 한다.
]]

local Constants = require("constants")

local PhysicsEngine = {}

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function getRules(context)
  return (context and context.constants) or Constants
end

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getStoneRadius(context, rules, stone)
  if type(context) == "table" and type(context.getStoneRadius) == "function" then
    local radius = context.getStoneRadius(stone)
    if isFiniteNumber(radius) and radius > 0 then
      return radius
    end
  end
  return rules.STONE_RADIUS
end

local function getStoneMass(context, _rules, stone)
  if type(context) == "table" and type(context.getStoneMass) == "function" then
    local mass = context.getStoneMass(stone)
    if isFiniteNumber(mass) and mass > 0 then
      return mass
    end
  end
  return 1.0
end

local function getStoneDampingPerSec(context, rules, stone)
  if type(context) == "table" and type(context.getStoneDampingPerSec) == "function" then
    local damping = context.getStoneDampingPerSec(stone)
    if isFiniteNumber(damping) and damping >= 0 then
      return damping
    end
  end
  return rules.PHYSICS_DAMPING_PER_SEC
end

local function applyPierceIfNeeded(context, stone, velocity, preSpeed, collisionKind)
  if type(context) ~= "table" or type(context.consumePiercingCollision) ~= "function" then
    return false
  end
  if type(stone) ~= "table" or type(velocity) ~= "table" then
    return false
  end
  local safePreSpeed = tonumber(preSpeed) or 0
  if safePreSpeed <= 0 then
    return false
  end
  local shouldConsume = context.consumePiercingCollision(stone, collisionKind)
  if not shouldConsume then
    return false
  end
  local postSpeed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
  if postSpeed <= 0.0001 then
    return false
  end
  local scale = safePreSpeed / postSpeed
  velocity.vx = velocity.vx * scale
  velocity.vy = velocity.vy * scale
  return true
end

local function resolveBoundaryAsWall(rules, stone, velocity, stoneRadius)
  local minX = stoneRadius
  local maxX = rules.BOARD_W - stoneRadius
  local minY = stoneRadius
  local maxY = rules.BOARD_H - stoneRadius
  local bounced = false

  if stone.x < minX then
    stone.x = minX
    if velocity.vx < 0 then
      velocity.vx = -velocity.vx * rules.PHYSICS_RESTITUTION
    end
    bounced = true
  elseif stone.x > maxX then
    stone.x = maxX
    if velocity.vx > 0 then
      velocity.vx = -velocity.vx * rules.PHYSICS_RESTITUTION
    end
    bounced = true
  end

  if stone.y < minY then
    stone.y = minY
    if velocity.vy < 0 then
      velocity.vy = -velocity.vy * rules.PHYSICS_RESTITUTION
    end
    bounced = true
  elseif stone.y > maxY then
    stone.y = maxY
    if velocity.vy > 0 then
      velocity.vy = -velocity.vy * rules.PHYSICS_RESTITUTION
    end
    bounced = true
  end

  return bounced
end

function PhysicsEngine.resolveObstacleCollision(context, stone, obstacle)
  if type(context) ~= "table" or type(stone) ~= "table" or type(obstacle) ~= "table" then
    return false, nil, nil
  end
  if type(context.getStoneVelocity) ~= "function" then
    return false, nil, nil
  end

  local rules = getRules(context)
  local halfW = (obstacle.width or rules.ROCK_OBSTACLE_WIDTH) * 0.5
  local halfH = (obstacle.height or rules.ROCK_OBSTACLE_HEIGHT) * 0.5
  local left = obstacle.x - halfW
  local right = obstacle.x + halfW
  local top = obstacle.y - halfH
  local bottom = obstacle.y + halfH
  local closestX = clamp(stone.x, left, right)
  local closestY = clamp(stone.y, top, bottom)
  local dx = stone.x - closestX
  local dy = stone.y - closestY
  local distanceSq = dx * dx + dy * dy
  local stoneRadius = getStoneRadius(context, rules, stone)
  local minDistanceSq = stoneRadius * stoneRadius

  if distanceSq >= minDistanceSq then
    return false, nil, nil
  end

  local normalX
  local normalY
  local overlap

  if distanceSq > 0 then
    local distance = math.sqrt(distanceSq)
    normalX = dx / distance
    normalY = dy / distance
    overlap = stoneRadius - distance
  else
    local penLeft = math.abs(stone.x - left)
    local penRight = math.abs(right - stone.x)
    local penTop = math.abs(stone.y - top)
    local penBottom = math.abs(bottom - stone.y)
    local minPen = math.min(penLeft, penRight, penTop, penBottom)
    if minPen == penLeft then
      normalX, normalY = -1, 0
      overlap = stoneRadius + penLeft
    elseif minPen == penRight then
      normalX, normalY = 1, 0
      overlap = stoneRadius + penRight
    elseif minPen == penTop then
      normalX, normalY = 0, -1
      overlap = stoneRadius + penTop
    else
      normalX, normalY = 0, 1
      overlap = stoneRadius + penBottom
    end
  end

  stone.x = stone.x + normalX * overlap
  stone.y = stone.y + normalY * overlap

  local velocity = context.getStoneVelocity(stone.id)
  local preSpeed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
  local normalSpeed = velocity.vx * normalX + velocity.vy * normalY
  if normalSpeed < 0 then
    local reflectScale = -(1 + rules.PHYSICS_RESTITUTION) * normalSpeed
    velocity.vx = velocity.vx + reflectScale * normalX
    velocity.vy = velocity.vy + reflectScale * normalY
  end
  applyPierceIfNeeded(context, stone, velocity, preSpeed, "obstacle")

  return true, closestX, closestY
end

function PhysicsEngine.resolveStoneCollision(context, firstStone, secondStone)
  if type(context) ~= "table" or type(firstStone) ~= "table" or type(secondStone) ~= "table" then
    return false, nil, nil
  end
  if type(context.getStoneVelocity) ~= "function" or type(context.isInvincibleOnCurrentTurn) ~= "function" then
    return false, nil, nil
  end

  local rules = getRules(context)
  local dx = secondStone.x - firstStone.x
  local dy = secondStone.y - firstStone.y
  local distanceSq = dx * dx + dy * dy
  local firstRadius = getStoneRadius(context, rules, firstStone)
  local secondRadius = getStoneRadius(context, rules, secondStone)
  local minDistance = firstRadius + secondRadius
  local minDistanceSq = minDistance * minDistance

  if distanceSq >= minDistanceSq then
    return false, nil, nil
  end

  local distance = math.sqrt(distanceSq)
  if distance <= 0 then
    dx = 0.001
    dy = 0
    distance = 0.001
  end

  local normalX = dx / distance
  local normalY = dy / distance
  local penetration = minDistance - distance
  local firstInvincible = context.isInvincibleOnCurrentTurn(firstStone.ownerPlayerIndex)
  local secondInvincible = context.isInvincibleOnCurrentTurn(secondStone.ownerPlayerIndex)

  if firstInvincible and not secondInvincible then
    secondStone.x = secondStone.x + normalX * penetration
    secondStone.y = secondStone.y + normalY * penetration
  elseif secondInvincible and not firstInvincible then
    firstStone.x = firstStone.x - normalX * penetration
    firstStone.y = firstStone.y - normalY * penetration
  else
    local firstMass = getStoneMass(context, rules, firstStone)
    local secondMass = getStoneMass(context, rules, secondStone)
    local firstInvMass = 1 / math.max(0.0001, firstMass)
    local secondInvMass = 1 / math.max(0.0001, secondMass)
    local totalInvMass = firstInvMass + secondInvMass
    local firstCorrectionRatio = 0.5
    local secondCorrectionRatio = 0.5
    if totalInvMass > 0 then
      firstCorrectionRatio = firstInvMass / totalInvMass
      secondCorrectionRatio = secondInvMass / totalInvMass
    end
    firstStone.x = firstStone.x - normalX * penetration * firstCorrectionRatio
    firstStone.y = firstStone.y - normalY * penetration * firstCorrectionRatio
    secondStone.x = secondStone.x + normalX * penetration * secondCorrectionRatio
    secondStone.y = secondStone.y + normalY * penetration * secondCorrectionRatio
  end

  local firstVelocity = context.getStoneVelocity(firstStone.id)
  local secondVelocity = context.getStoneVelocity(secondStone.id)
  if type(context.applyInvincibleCollisionResponse) == "function" then
    if context.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity) then
      local collisionX = (firstStone.x + secondStone.x) * 0.5
      local collisionY = (firstStone.y + secondStone.y) * 0.5
      return true, collisionX, collisionY
    end
  end

  local firstPreSpeed = math.sqrt(firstVelocity.vx * firstVelocity.vx + firstVelocity.vy * firstVelocity.vy)
  local secondPreSpeed = math.sqrt(secondVelocity.vx * secondVelocity.vx + secondVelocity.vy * secondVelocity.vy)
  local relativeX = secondVelocity.vx - firstVelocity.vx
  local relativeY = secondVelocity.vy - firstVelocity.vy
  local normalSpeed = relativeX * normalX + relativeY * normalY
  if normalSpeed < 0 then
    local firstMass = getStoneMass(context, rules, firstStone)
    local secondMass = getStoneMass(context, rules, secondStone)
    local firstInvMass = firstInvincible and 0 or (1 / math.max(0.0001, firstMass))
    local secondInvMass = secondInvincible and 0 or (1 / math.max(0.0001, secondMass))
    local denominator = firstInvMass + secondInvMass
    local impulse = 0
    if denominator > 0 then
      impulse = -(1 + rules.PHYSICS_RESTITUTION) * normalSpeed / denominator
    end
    if not firstInvincible then
      firstVelocity.vx = firstVelocity.vx - impulse * firstInvMass * normalX
      firstVelocity.vy = firstVelocity.vy - impulse * firstInvMass * normalY
    end
    if not secondInvincible then
      secondVelocity.vx = secondVelocity.vx + impulse * secondInvMass * normalX
      secondVelocity.vy = secondVelocity.vy + impulse * secondInvMass * normalY
    end
  end

  applyPierceIfNeeded(context, firstStone, firstVelocity, firstPreSpeed, "stone")
  applyPierceIfNeeded(context, secondStone, secondVelocity, secondPreSpeed, "stone")

  local collisionX = (firstStone.x + secondStone.x) * 0.5
  local collisionY = (firstStone.y + secondStone.y) * 0.5
  return true, collisionX, collisionY
end

function PhysicsEngine.simulateShotStep(context, stepSec)
  if type(context) ~= "table" or type(context.stoneList) ~= "table" or type(context.obstacleList) ~= "table" then
    return
  end
  if type(context.getStoneVelocity) ~= "function" then
    return
  end

  local rules = getRules(context)
  local aliveStoneList = {}
  for _, stone in ipairs(context.stoneList) do
    local velocity = context.getStoneVelocity(stone.id)
    if stone.alive ~= false then
      stone.x = stone.x + velocity.vx * stepSec
      stone.y = stone.y + velocity.vy * stepSec
      aliveStoneList[#aliveStoneList + 1] = stone
    else
      velocity.vx = 0
      velocity.vy = 0
    end
  end

  for _, stone in ipairs(aliveStoneList) do
    for _, obstacle in ipairs(context.obstacleList) do
      local collided, cx, cy = PhysicsEngine.resolveObstacleCollision(context, stone, obstacle)
      if collided then
        if type(context.isShockwaveShotStone) == "function" and type(context.applyShockwaveFromPoint) == "function" and context.isShockwaveShotStone(stone.id) then
          context.applyShockwaveFromPoint(stone.x, stone.y)
        end
        if type(context.onCollision) == "function" then
          context.onCollision(cx or stone.x, cy or stone.y)
        end
      end
    end
  end

  for firstIndex = 1, #aliveStoneList - 1 do
    for secondIndex = firstIndex + 1, #aliveStoneList do
      local firstStone = aliveStoneList[firstIndex]
      local secondStone = aliveStoneList[secondIndex]
      local collided, cx, cy = PhysicsEngine.resolveStoneCollision(context, firstStone, secondStone)
      if collided then
        if type(context.isShockwaveShotStone) == "function" and type(context.applyShockwaveFromPoint) == "function" then
          if context.isShockwaveShotStone(firstStone.id) then
            context.applyShockwaveFromPoint(firstStone.x, firstStone.y)
          elseif context.isShockwaveShotStone(secondStone.id) then
            context.applyShockwaveFromPoint(secondStone.x, secondStone.y)
          end
        end
        if type(context.onCollision) == "function" then
          context.onCollision(cx or (firstStone.x + secondStone.x) * 0.5, cy or (firstStone.y + secondStone.y) * 0.5)
        end
      end
    end
  end

  for _, stone in ipairs(context.stoneList) do
    local velocity = context.getStoneVelocity(stone.id)
    if stone.alive ~= false then
      local stoneRadius = getStoneRadius(context, rules, stone)
      local minX = stoneRadius
      local maxX = rules.BOARD_W - stoneRadius
      local minY = stoneRadius
      local maxY = rules.BOARD_H - stoneRadius
      if stone.x < minX or stone.x > maxX or stone.y < minY or stone.y > maxY then
        local treatedAsWall = false
        if type(context.shouldTreatOutAsWall) == "function" and context.shouldTreatOutAsWall(stone) then
          local preSpeed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
          treatedAsWall = resolveBoundaryAsWall(rules, stone, velocity, stoneRadius)
          if treatedAsWall then
            applyPierceIfNeeded(context, stone, velocity, preSpeed, "boundary")
          end
        end
        if not treatedAsWall then
          if type(context.isShockwaveShotStone) == "function" and type(context.applyShockwaveFromPoint) == "function" and context.isShockwaveShotStone(stone.id) then
            context.applyShockwaveFromPoint(stone.x, stone.y)
          end
          stone.alive = false
          velocity.vx = 0
          velocity.vy = 0
        end
      else
        local dampingPerSec = getStoneDampingPerSec(context, rules, stone)
        local damping = math.max(0, 1 - dampingPerSec * stepSec)
        velocity.vx = velocity.vx * damping
        velocity.vy = velocity.vy * damping
        local speed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
        if speed < rules.PHYSICS_STOP_SPEED then
          velocity.vx = 0
          velocity.vy = 0
        end
      end
    end
  end
end

function PhysicsEngine.hasAnyStoneInMotion(context)
  if type(context) ~= "table" or type(context.stoneList) ~= "table" then
    return false
  end
  if type(context.getStoneVelocity) ~= "function" then
    return false
  end

  local rules = getRules(context)
  for _, stone in ipairs(context.stoneList) do
    if stone.alive ~= false then
      local velocity = context.getStoneVelocity(stone.id)
      local speed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
      if speed >= rules.PHYSICS_STOP_SPEED then
        return true
      end
    end
  end
  return false
end

return PhysicsEngine
