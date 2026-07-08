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

local function getSceneStoneRadius(scene, stoneOrPlayerIndex)
  if type(scene) ~= "table" then
    return Constants.STONE_RADIUS
  end
  if type(stoneOrPlayerIndex) == "table" and type(scene.getStoneRadius) == "function" then
    local radius = scene:getStoneRadius(stoneOrPlayerIndex)
    if type(radius) == "number" and radius > 0 then
      return radius
    end
  end
  if type(stoneOrPlayerIndex) == "table" and type(scene.getStoneRadiusForPlayer) == "function" then
    local radius = scene:getStoneRadiusForPlayer(stoneOrPlayerIndex.ownerPlayerIndex)
    if type(radius) == "number" and radius > 0 then
      return radius
    end
  end
  if type(stoneOrPlayerIndex) == "number" and type(scene.getStoneRadiusForPlayer) == "function" then
    local radius = scene:getStoneRadiusForPlayer(stoneOrPlayerIndex)
    if type(radius) == "number" and radius > 0 then
      return radius
    end
  end
  if type(stoneOrPlayerIndex) == "number" and type(scene.getStoneRadius) == "function" then
    local radius = scene:getStoneRadius(stoneOrPlayerIndex)
    if type(radius) == "number" and radius > 0 then
      return radius
    end
  end
  return Constants.STONE_RADIUS
end

local function listToSet(valueList)
  local valueSet = {}
  for _, value in ipairs(valueList or {}) do
    valueSet[tostring(value)] = true
  end
  return valueSet
end

local function intersectsStoneAndObstacle(stoneX, stoneY, obstacle, stoneRadius)
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
  local radius = math.max(1, tonumber(stoneRadius) or Constants.STONE_RADIUS)
  return dx * dx + dy * dy < radius * radius
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
    if stone.alive ~= false and intersectsStoneAndObstacle(stone.x, stone.y, previewObstacle, getSceneStoneRadius(scene, stone)) then
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
  local placementRadius = getSceneStoneRadius(scene, 1)
  local minX = placementRadius
  local maxX = Constants.BOARD_W - placementRadius
  local minY = placementRadius
  local maxY = Constants.BOARD_H - placementRadius
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
    if intersectsStoneAndObstacle(previewStone.x, previewStone.y, obstacle, placementRadius) then
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
    local radius = getSceneStoneRadius(scene, 1)
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

---------------------------------------------------------------------------
-- 초능력 시스템 (Character Abilities)
---------------------------------------------------------------------------

local Json = require("utils.json")

local CHARACTERS_CACHE = nil

local function loadCharactersData()
  if CHARACTERS_CACHE then
    return CHARACTERS_CACHE
  end
  if not love or not love.filesystem then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  local isReadOk, raw = pcall(love.filesystem.read, "shared/characters.json")
  if not isReadOk or type(raw) ~= "string" or raw == "" then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  local isDecoded, parsed = pcall(Json.decode, raw)
  if not isDecoded or type(parsed) ~= "table" then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  CHARACTERS_CACHE = parsed
  return CHARACTERS_CACHE
end

function Abilities.getCharacterAbility(characterId)
  local data = loadCharactersData()
  local chars = type(data.characters) == "table" and data.characters or {}
  local charDef = chars[tostring(characterId or "")]
  if type(charDef) ~= "table" then
    return nil
  end
  return charDef.ability
end

function Abilities.getCharacterList()
  local data = loadCharactersData()
  local chars = type(data.characters) == "table" and data.characters or {}
  local order = type(data.characterOrder) == "table" and data.characterOrder or {}
  local list = {}
  for _, charId in ipairs(order) do
    local charDef = chars[tostring(charId)]
    if charDef then
      list[#list + 1] = charDef
    end
  end
  return list
end

function Abilities.getGlobalChargeParams()
  local data = loadCharactersData()
  local global = type(data.global) == "table" and data.global or {}
  return {
    chargePerTurn = tonumber(global.chargePerTurn) or Constants.CHARGE_PER_TURN,
    chargeOnAllyOut = tonumber(global.chargeOnAllyOut) or Constants.CHARGE_ON_ALLY_OUT,
    chargeMax = tonumber(global.chargeMax) or Constants.CHARGE_MAX
  }
end

function Abilities.executeShadowStep(scene, playerIndex, targetX, targetY)
  local stones = scene._playingStoneList
  if type(stones) ~= "table" then
    return false, "no_stones"
  end
  -- 플레이어가 조준 중인 알 하나를 순간이동
  local aimStoneId = scene._aimStoneId
  local targetStone = nil
  if aimStoneId then
    for _, stone in ipairs(stones) do
      if stone.id == aimStoneId and stone.alive ~= false and stone.ownerPlayerIndex == playerIndex then
        targetStone = stone
        break
      end
    end
  end
  if not targetStone then
    -- 조준 중이 아니면 첫 번째 살아있는 내 알
    for _, stone in ipairs(stones) do
      if stone.alive ~= false and stone.ownerPlayerIndex == playerIndex then
        targetStone = stone
        break
      end
    end
  end
  if not targetStone then
    return false, "no_valid_stone"
  end

  local radius = Constants.STONE_RADIUS
  if type(scene.getStoneRadius) == "function" then
    radius = scene:getStoneRadius(targetStone)
  elseif type(scene.getStoneRadiusForPlayer) == "function" then
    radius = scene:getStoneRadiusForPlayer(playerIndex)
  end

  local tx = clamp(targetX or targetStone.x, radius, Constants.BOARD_W - radius)
  local ty = clamp(targetY or targetStone.y, radius, Constants.BOARD_H - radius)

  -- 다른 알과 겹치지 않는지 확인
  for _, stone in ipairs(stones) do
    if stone.alive ~= false and stone.id ~= targetStone.id then
      local dx = stone.x - tx
      local dy = stone.y - ty
      if dx * dx + dy * dy < (radius * 2 + 4) ^ 2 then
        return false, "overlap"
      end
    end
  end

  -- 장애물과 겹치는지 확인
  local obstacles = scene._obstacleList
  if type(obstacles) == "table" then
    for _, obstacle in ipairs(obstacles) do
      local halfW = (obstacle.width or Constants.ROCK_OBSTACLE_WIDTH) * 0.5
      local halfH = (obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT) * 0.5
      local cx = clamp(tx, obstacle.x - halfW, obstacle.x + halfW)
      local cy = clamp(ty, obstacle.y - halfH, obstacle.y + halfH)
      if (tx - cx) ^ 2 + (ty - cy) ^ 2 < radius ^ 2 then
        return false, "overlap_obstacle"
      end
    end
  end

  targetStone.x = tx
  targetStone.y = ty

  -- 순간이동 후 추가 샷 허용
  scene._playingShotBudget = scene._playingShotBudget + 1
  return true, "ok"
end

function Abilities.executeMeteor(scene, _playerIndex)
  local centerX = Constants.BOARD_W * 0.5
  local centerY = Constants.BOARD_H * 0.5

  -- 충격파 (기존 shockwave 대비 1.5배)
  local multiplier = 1.5
  local shockwaveRadius = Constants.STONE_RADIUS * Constants.SHOCKWAVE_RANGE_MULTIPLIER * multiplier
  local impulseStrength = Constants.SHOCKWAVE_STRENGTH * multiplier

  if scene._effectManager then
    scene._effectManager:addShockwavePulse(centerX, centerY, shockwaveRadius)
  end

  for _, stone in ipairs(scene._playingStoneList) do
    if stone.alive ~= false then
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

  -- 중앙 장애물 생성
  local obstacleW = 70
  local obstacleH = 70
  scene._obstacleList[#scene._obstacleList + 1] = {
    id = "meteor_" .. tostring(os.time()),
    x = centerX,
    y = centerY,
    width = obstacleW,
    height = obstacleH
  }

  if type(scene.startShotSimulation) == "function" then
    scene:startShotSimulation()
  else
    -- GameMechanics 호환
    local GameMechanics = require("game_mechanics")
    GameMechanics.startShotSimulation(scene)
  end
  return true, "ok"
end

function Abilities.executeDivineShield(scene, playerIndex)
  local currentTurn = scene._playingTurnIndex or 1
  scene._invincibleTurnByPlayer = scene._invincibleTurnByPlayer or {}
  scene._invincibleTurnByPlayer[playerIndex] = currentTurn + 1
  scene._invincibleTurnByPlayer[tostring(playerIndex)] = currentTurn + 1
  -- 디바인실드는 자신 턴 + 다음 상대 턴까지 (2턴)
  if scene._invincibleTurnByPlayer[playerIndex] then
    scene._invincibleTurnByPlayer[playerIndex] = math.max(
      scene._invincibleTurnByPlayer[playerIndex] or 0,
      currentTurn + 1
    )
  end
  -- TODO: 반사 충돌 효과는 physics_engine에서 invincible collision response 활용
  return true, "ok"
end

function Abilities.executeComboFinisher(scene, _playerIndex)
  -- 추가 샷 1회 (총 2샷)
  scene._playingShotBudget = (scene._playingShotBudget or 1) + 1
  -- 콤보 배율 플래그 (첫 샷 아웃 시 파워 증가)
  scene._comboFinisherActive = true
  scene._comboFinisherFirstShotDone = false
  return true, "ok"
end

function Abilities.executeAbility(scene, playerIndex, characterId, target)
  if not characterId or characterId == "" then
    return false, "no_character"
  end
  local ability = Abilities.getCharacterAbility(characterId)
  if not ability then
    return false, "no_ability"
  end

  local abilityId = ability.id
  if abilityId == "shadow_step" then
    return Abilities.executeShadowStep(scene, playerIndex, (target and target.x), (target and target.y))
  elseif abilityId == "meteor" then
    return Abilities.executeMeteor(scene, playerIndex)
  elseif abilityId == "divine_shield" then
    return Abilities.executeDivineShield(scene, playerIndex)
  elseif abilityId == "combo_finisher" then
    return Abilities.executeComboFinisher(scene, playerIndex)
  end

  return false, "unknown_ability"
end

return Abilities
