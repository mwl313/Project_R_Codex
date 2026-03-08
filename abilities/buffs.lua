--[[
파일명: abilities/buffs.lua
모듈명: AbilityBuffs

역할:
- 턴 버프/디버프(무적/충격파 등) 계산과 충돌 보정 유틸을 담당한다.
]]

local Constants = require("constants")
local CardRules = require("shared.card_rules")

local AbilityBuffs = {}

local function readTurnIndexByPlayer(value, playerIndex)
  if type(value) ~= "table" then
    return nil
  end
  local numericKeyValue = value[playerIndex]
  if type(numericKeyValue) == "number" then
    return numericKeyValue
  end
  local stringKeyValue = value[tostring(playerIndex)]
  if type(stringKeyValue) == "number" then
    return stringKeyValue
  end
  return nil
end

function AbilityBuffs.normalizeInvincibleTurnByPlayer(value)
  return {
    [1] = readTurnIndexByPlayer(value, 1),
    [2] = readTurnIndexByPlayer(value, 2)
  }
end

function AbilityBuffs.isInvincibleOnCurrentTurn(scene, playerIndex)
  local invincibleTurnByPlayer = scene._invincibleTurnByPlayer
  if type(invincibleTurnByPlayer) ~= "table" then
    return false
  end
  local protectedTurnIndex = invincibleTurnByPlayer[playerIndex]
  if type(protectedTurnIndex) ~= "number" then
    protectedTurnIndex = invincibleTurnByPlayer[tostring(playerIndex)]
  end
  return type(protectedTurnIndex) == "number" and protectedTurnIndex == scene._playingTurnIndex
end

function AbilityBuffs.isShockwaveShotStone(scene, stoneId)
  if type(stoneId) ~= "string" then
    return false
  end
  return scene._shockwaveOwnerPlayerIndex ~= nil and scene._shockwaveSourceStoneId == stoneId
end

function AbilityBuffs.applyShockwaveFromPoint(scene, centerX, centerY)
  local shockwaveRule = CardRules.getShockwaveRule()
  local shockwaveRadius = Constants.STONE_RADIUS * math.max(0, shockwaveRule.radius_multiplier or 0)
  if shockwaveRadius <= 0 then
    return
  end
  if scene._effectManager then
    scene._effectManager:addShockwavePulse(centerX, centerY, shockwaveRadius)
  end

  local impulseStrength = math.max(0, shockwaveRule.strength or 0)
  if impulseStrength <= 0 then
    return
  end

  for _, stone in ipairs(scene._playingStoneList or {}) do
    local isSourceStoneBlocked = shockwaveRule.exclude_source_stone and stone.id == scene._shockwaveSourceStoneId
    local isInvincibleBlocked = shockwaveRule.ignore_invincible_targets and AbilityBuffs.isInvincibleOnCurrentTurn(scene, stone.ownerPlayerIndex)
    if stone.alive ~= false and (not isSourceStoneBlocked) and (not isInvincibleBlocked) then
      local dx = stone.x - centerX
      local dy = stone.y - centerY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance > 0 and distance <= shockwaveRadius then
        local velocity = scene:getStoneVelocity(stone.id)
        velocity.vx = velocity.vx + (dx / distance) * impulseStrength
        velocity.vy = velocity.vy + (dy / distance) * impulseStrength
      end
    end
  end
end

function AbilityBuffs.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
  if firstInvincible == secondInvincible then
    return false
  end

  local invincibleVelocity
  local movingVelocity
  local outwardNormalX
  local outwardNormalY

  if firstInvincible then
    invincibleVelocity = firstVelocity
    movingVelocity = secondVelocity
    outwardNormalX = normalX
    outwardNormalY = normalY
  else
    invincibleVelocity = secondVelocity
    movingVelocity = firstVelocity
    outwardNormalX = -normalX
    outwardNormalY = -normalY
  end

  local relVx = movingVelocity.vx - invincibleVelocity.vx
  local relVy = movingVelocity.vy - invincibleVelocity.vy
  local towardSpeed = relVx * outwardNormalX + relVy * outwardNormalY
  if towardSpeed < 0 then
    local reflectScale = -(1 + Constants.PHYSICS_RESTITUTION) * towardSpeed
    relVx = relVx + reflectScale * outwardNormalX
    relVy = relVy + reflectScale * outwardNormalY
    movingVelocity.vx = invincibleVelocity.vx + relVx
    movingVelocity.vy = invincibleVelocity.vy + relVy
  end

  return true
end

return AbilityBuffs
