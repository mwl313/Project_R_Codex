--[[
파일명: abilities.lua
모듈명: Abilities

역할:
- 카드/능력 관련 규칙을 한 파일에서 관리한다.
- MatchScene은 능력 규칙 계산을 이 모듈에 위임한다.

외부에서 사용 가능한 함수:
- Abilities.getCardLabel(cardId)
- Abilities.isSupportedTurnCard(cardId)
- Abilities.normalizeInvincibleTurnByPlayer(value)
- Abilities.isInvincibleOnCurrentTurn(scene, playerIndex)
- Abilities.isShockwaveShotStone(scene, stoneId)
- Abilities.applyShockwaveFromPoint(scene, centerX, centerY)
- Abilities.canPlaceRockfallAtCanonical(scene, canonicalX, canonicalY)
- Abilities.canPlaceReinforcementAtCanonical(scene, canonicalX, canonicalY)
- Abilities.getPendingTargetHint(cardId)
- Abilities.getPendingTargetStartStatus(cardId)
- Abilities.getPendingTargetOutOfBoardStatus(cardId)
- Abilities.getPendingTargetRequestStatus(cardId)
- Abilities.applyServerCardEffect(scene, effectPayload)
- Abilities.drawPendingCardPreview(scene, mouseX, mouseY)
- Abilities.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local CardRules = require("shared.card_rules")

local Abilities = {}

Abilities.TURN_CARD_SET = {}
for _, cardId in ipairs(CardRules.getCardPool(CardRules.GAME_MODE_MULTI)) do
  Abilities.TURN_CARD_SET[cardId] = CardRules.isTurnCardEnabled(cardId)
end

local function t(key, vars)
  return I18n.t(key, vars)
end

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function listToSet(valueList)
  local valueSet = {}
  for _, value in ipairs(valueList or {}) do
    valueSet[tostring(value)] = true
  end
  return valueSet
end

local function intersectsStoneAndObstacle(stoneX, stoneY, obstacle)
  local halfW = (obstacle.width or Constants.ROCK_OBSTACLE_WIDTH) * 0.5
  local halfH = (obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT) * 0.5
  local left = obstacle.x - halfW
  local right = obstacle.x + halfW
  local top = obstacle.y - halfH
  local bottom = obstacle.y + halfH
  local closestX = clamp(stoneX, left, right)
  local closestY = clamp(stoneY, top, bottom)
  local dx = stoneX - closestX
  local dy = stoneY - closestY
  return dx * dx + dy * dy < Constants.STONE_RADIUS * Constants.STONE_RADIUS
end

local function intersectsObstacleAndObstacle(firstObstacle, secondObstacle)
  local firstHalfW = (firstObstacle.width or Constants.ROCK_OBSTACLE_WIDTH) * 0.5
  local firstHalfH = (firstObstacle.height or Constants.ROCK_OBSTACLE_HEIGHT) * 0.5
  local secondHalfW = (secondObstacle.width or Constants.ROCK_OBSTACLE_WIDTH) * 0.5
  local secondHalfH = (secondObstacle.height or Constants.ROCK_OBSTACLE_HEIGHT) * 0.5
  return math.abs(firstObstacle.x - secondObstacle.x) < (firstHalfW + secondHalfW)
    and math.abs(firstObstacle.y - secondObstacle.y) < (firstHalfH + secondHalfH)
end

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

local PENDING_TARGET_HINT_KEY_BY_CARD_ID = {
  reinforcement = "abilities.hint.reinforcement_click",
  rockfall = "abilities.hint.rockfall_click"
}

local PENDING_TARGET_START_KEY_BY_CARD_ID = {
  reinforcement = "abilities.hint.reinforcement_start",
  rockfall = "abilities.hint.rockfall_start"
}

local PENDING_TARGET_OUT_OF_BOARD_KEY_BY_CARD_ID = {
  reinforcement = "abilities.hint.reinforcement_out_of_board",
  rockfall = "abilities.hint.rockfall_out_of_board"
}

local PENDING_TARGET_REQUEST_KEY_BY_CARD_ID = {
  reinforcement = "abilities.hint.reinforcement_sending",
  rockfall = "abilities.hint.rockfall_sending"
}

function Abilities.getCardLabel(cardId)
  local key = "abilities.card_label." .. tostring(cardId)
  local localized = t(key)
  if localized:sub(1, 10) == "[[missing:" then
    return tostring(cardId)
  end
  return localized
end

function Abilities.isSupportedTurnCard(cardId)
  return Abilities.TURN_CARD_SET[cardId] == true
end

function Abilities.isPointTargetCard(cardId)
  return CardRules.getTargetMode(cardId) == CardRules.TARGET_MODE_POINT
end

function Abilities.normalizeInvincibleTurnByPlayer(value)
  return {
    [1] = readTurnIndexByPlayer(value, 1),
    [2] = readTurnIndexByPlayer(value, 2)
  }
end

function Abilities.isInvincibleOnCurrentTurn(scene, playerIndex)
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

function Abilities.isShockwaveShotStone(scene, stoneId)
  if type(stoneId) ~= "string" then
    return false
  end
  return scene._shockwaveOwnerPlayerIndex ~= nil and scene._shockwaveSourceStoneId == stoneId
end

function Abilities.applyShockwaveFromPoint(scene, centerX, centerY)
  local shockwaveRule = CardRules.getShockwaveRule()
  local upgradeScale = tonumber(scene and scene._shockwaveCardScale) or 1.0
  if upgradeScale < 0 then
    upgradeScale = 0
  end
  local shockwaveRadius = Constants.STONE_RADIUS * math.max(0, shockwaveRule.radius_multiplier or 0) * upgradeScale
  if shockwaveRadius <= 0 then
    return
  end
  if scene._effectManager then
    scene._effectManager:addShockwavePulse(centerX, centerY, shockwaveRadius)
  end

  local impulseStrength = math.max(0, shockwaveRule.strength or 0) * upgradeScale
  if impulseStrength <= 0 then
    return
  end

  for _, stone in ipairs(scene._playingStoneList) do
    local isSourceStoneBlocked = shockwaveRule.exclude_source_stone and stone.id == scene._shockwaveSourceStoneId
    local isInvincibleBlocked = shockwaveRule.ignore_invincible_targets and Abilities.isInvincibleOnCurrentTurn(scene, stone.ownerPlayerIndex)
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

function Abilities.canPlaceRockfallAtCanonical(scene, canonicalX, canonicalY)
  local rockfallRule = CardRules.getRockfallRule()
  local width = math.max(1, rockfallRule.width or Constants.ROCK_OBSTACLE_WIDTH)
  local height = math.max(1, rockfallRule.height or Constants.ROCK_OBSTACLE_HEIGHT)
  local halfW = width * 0.5
  local halfH = height * 0.5
  local margin = math.max(0, rockfallRule.margin or Constants.ROCK_OBSTACLE_MARGIN)

  if canonicalX - halfW < margin or canonicalX + halfW > Constants.BOARD_W - margin then
    return false, t("abilities.validate.rockfall_board_margin")
  end
  if canonicalY - halfH < margin or canonicalY + halfH > Constants.BOARD_H - margin then
    return false, t("abilities.validate.rockfall_board_margin")
  end

  local previewObstacle = {
    x = canonicalX,
    y = canonicalY,
    width = width,
    height = height
  }

  for _, stone in ipairs(scene._playingStoneList) do
    if stone.alive ~= false and intersectsStoneAndObstacle(stone.x, stone.y, previewObstacle) then
      return false, t("abilities.validate.rockfall_overlap_stone")
    end
  end

  for _, obstacle in ipairs(scene._obstacleList) do
    if intersectsObstacleAndObstacle(previewObstacle, obstacle) then
      return false, t("abilities.validate.rockfall_overlap_obstacle")
    end
  end

  return true, nil
end

function Abilities.canPlaceReinforcementAtCanonical(scene, canonicalX, canonicalY)
  local reinforcementRule = CardRules.getReinforcementRule()
  local minPlaceDistance = math.max(1, reinforcementRule.min_place_distance or Constants.MIN_PLACE_DISTANCE)
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  if canonicalX < minX or canonicalX > maxX or canonicalY < minY or canonicalY > maxY then
    return false, t("abilities.validate.reinforcement_out_of_board")
  end

  for _, stone in ipairs(scene._playingStoneList) do
    if stone.alive ~= false then
      local dx = stone.x - canonicalX
      local dy = stone.y - canonicalY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < minPlaceDistance then
        return false, t("abilities.validate.reinforcement_too_close")
      end
    end
  end

  local previewStone = {
    x = canonicalX,
    y = canonicalY
  }
  for _, obstacle in ipairs(scene._obstacleList) do
    if intersectsStoneAndObstacle(previewStone.x, previewStone.y, obstacle) then
      return false, t("abilities.validate.reinforcement_overlap_obstacle")
    end
  end

  return true, nil
end

function Abilities.getPendingTargetHint(cardId)
  local key = PENDING_TARGET_HINT_KEY_BY_CARD_ID[tostring(cardId or "")]
  if key then
    return t(key)
  end
  return t("match.status.card_target_cannot_place")
end

function Abilities.getPendingTargetStartStatus(cardId)
  local key = PENDING_TARGET_START_KEY_BY_CARD_ID[tostring(cardId or "")]
  if key then
    return t(key)
  end
  return t("match.status.cannot_use_card_now")
end

function Abilities.getPendingTargetOutOfBoardStatus(cardId)
  local key = PENDING_TARGET_OUT_OF_BOARD_KEY_BY_CARD_ID[tostring(cardId or "")]
  if key then
    return t(key)
  end
  return t("match.status.card_target_cannot_place")
end

function Abilities.getPendingTargetRequestStatus(cardId)
  local key = PENDING_TARGET_REQUEST_KEY_BY_CARD_ID[tostring(cardId or "")]
  if key then
    return t(key)
  end
  return t("match.status.card_use_submit")
end

local function validateRockfallTarget(scene, canonicalX, canonicalY)
  return Abilities.canPlaceRockfallAtCanonical(scene, canonicalX, canonicalY)
end

local function validateReinforcementTarget(scene, canonicalX, canonicalY)
  return Abilities.canPlaceReinforcementAtCanonical(scene, canonicalX, canonicalY)
end

local PENDING_TARGET_VALIDATOR_BY_CARD_ID = {
  rockfall = validateRockfallTarget,
  reinforcement = validateReinforcementTarget
}

function Abilities.validatePendingTargetAtCanonical(scene, cardId, canonicalX, canonicalY)
  local validator = PENDING_TARGET_VALIDATOR_BY_CARD_ID[tostring(cardId or "")]
  if type(validator) ~= "function" then
    return false, t("match.status.card_target_cannot_place")
  end
  return validator(scene, canonicalX, canonicalY)
end

function Abilities.applyServerCardEffect(scene, effectPayload)
  if type(effectPayload) ~= "table" then
    return
  end
  if type(effectPayload.shotBudget) == "number" then
    scene._playingShotBudget = effectPayload.shotBudget
  end
  if type(effectPayload.lockedStoneIds) == "table" then
    scene._lockedStoneIdSet = listToSet(effectPayload.lockedStoneIds)
  end
  if type(effectPayload.spawnStone) == "table" then
    scene._playingStoneList[#scene._playingStoneList + 1] = {
      id = effectPayload.spawnStone.id,
      ownerPlayerIndex = effectPayload.spawnStone.ownerPlayerIndex,
      x = effectPayload.spawnStone.x,
      y = effectPayload.spawnStone.y,
      alive = effectPayload.spawnStone.alive ~= false
    }
  end
  if type(effectPayload.obstacle) == "table" then
    scene._obstacleList[#scene._obstacleList + 1] = {
      id = effectPayload.obstacle.id,
      x = effectPayload.obstacle.x,
      y = effectPayload.obstacle.y,
      width = effectPayload.obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
      height = effectPayload.obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    }
  end
  if type(effectPayload.invincibleTurnByPlayer) == "table" then
    scene._invincibleTurnByPlayer = Abilities.normalizeInvincibleTurnByPlayer(effectPayload.invincibleTurnByPlayer)
  end
  if effectPayload.shockwaveOwnerPlayerIndex == 1 or effectPayload.shockwaveOwnerPlayerIndex == 2 then
    scene._shockwaveOwnerPlayerIndex = effectPayload.shockwaveOwnerPlayerIndex
  end
end

function Abilities.drawPendingCardPreview(scene, mouseX, mouseY)
  if not Abilities.isPointTargetCard(scene._pendingCardTargetId) then
    return
  end
  if not scene:isPlayingPhase() or not scene:isMyTurn() then
    return
  end

  local boardLocalX, boardLocalY = scene:toBoardLocal(mouseX, mouseY)
  if not boardLocalX then
    return
  end

  local canonicalX, canonicalY = scene:localToCanonical(boardLocalX, boardLocalY)
  local canPlace = false
  local pendingCardId = tostring(scene._pendingCardTargetId or "")
  canPlace = Abilities.validatePendingTargetAtCanonical(scene, pendingCardId, canonicalX, canonicalY)
  if pendingCardId == "rockfall" then
    local rockfallRule = CardRules.getRockfallRule()
    local width = math.max(1, rockfallRule.width or Constants.ROCK_OBSTACLE_WIDTH)
    local height = math.max(1, rockfallRule.height or Constants.ROCK_OBSTACLE_HEIGHT)
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
  else
    canPlace = Abilities.canPlaceReinforcementAtCanonical(scene, canonicalX, canonicalY)
    local radius = Constants.STONE_RADIUS
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.circle("fill", mouseX, mouseY, radius)
    love.graphics.setColor(borderColor)
    love.graphics.circle("line", mouseX, mouseY, radius)
  end
end

function Abilities.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
  if firstInvincible == secondInvincible then
    return false
  end

  -- 충돌 노멀은 first -> second 방향이다.
  -- 무적 돌 기준으로 "바깥 방향" 노멀을 잡고,
  -- moving-relative velocity를 반사시켜 무적 돌은 고정, 상대만 튕기게 만든다.
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

return Abilities
