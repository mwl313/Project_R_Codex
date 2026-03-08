--[[
파일명: abilities.lua
모듈명: Abilities

역할:
- 카드/능력 허브 모듈.
- 외부 계약(API)은 유지하고, 내부 구현은 관심사별 하위 모듈로 분리한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local CardRules = require("shared.card_rules")
local AbilityTargeted = require("abilities.targeted")
local AbilityBuffs = require("abilities.buffs")
local AbilityBoardEffects = require("abilities.board_effects")
local AbilitySpecial = require("abilities.special")

local Abilities = {}

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

local function buildTurnCardSet()
  local turnCardSet = {}
  local pool = CardRules.getCardPool(CardRules.GAME_MODE_MULTI)
  for _, cardId in ipairs(pool) do
    if CardRules.isTurnCardEnabled(cardId) then
      turnCardSet[cardId] = true
    end
  end
  return turnCardSet
end

Abilities.TURN_CARD_SET = buildTurnCardSet()

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

function Abilities.normalizeInvincibleTurnByPlayer(value)
  return AbilityBuffs.normalizeInvincibleTurnByPlayer(value)
end

function Abilities.isInvincibleOnCurrentTurn(scene, playerIndex)
  return AbilityBuffs.isInvincibleOnCurrentTurn(scene, playerIndex)
end

function Abilities.isShockwaveShotStone(scene, stoneId)
  return AbilityBuffs.isShockwaveShotStone(scene, stoneId)
end

function Abilities.applyShockwaveFromPoint(scene, centerX, centerY)
  AbilityBuffs.applyShockwaveFromPoint(scene, centerX, centerY)
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

  for _, stone in ipairs(scene._playingStoneList or {}) do
    if stone.alive ~= false and intersectsStoneAndObstacle(stone.x, stone.y, previewObstacle) then
      return false, t("abilities.validate.rockfall_overlap_stone")
    end
  end

  for _, obstacle in ipairs(scene._obstacleList or {}) do
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

  for _, stone in ipairs(scene._playingStoneList or {}) do
    if stone.alive ~= false then
      local dx = stone.x - canonicalX
      local dy = stone.y - canonicalY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < minPlaceDistance then
        return false, t("abilities.validate.reinforcement_too_close")
      end
    end
  end

  for _, obstacle in ipairs(scene._obstacleList or {}) do
    if intersectsStoneAndObstacle(canonicalX, canonicalY, obstacle) then
      return false, t("abilities.validate.reinforcement_overlap_obstacle")
    end
  end

  return true, nil
end

function Abilities.getTargetMode(cardId)
  return AbilityTargeted.getTargetMode(cardId)
end

function Abilities.needsTargeting(cardId)
  return AbilityTargeted.needsTargeting(cardId)
end

function Abilities.createPendingTargetState(cardId)
  return AbilityTargeted.createPendingState(cardId)
end

function Abilities.getPendingTargetHint(cardId, pendingState)
  return AbilityTargeted.getPendingTargetHint(cardId, pendingState)
end

function Abilities.getPendingTargetStartStatus(cardId, pendingState)
  return AbilityTargeted.getPendingTargetStartStatus(cardId, pendingState)
end

function Abilities.getPendingTargetOutOfBoardStatus(cardId, pendingState)
  return AbilityTargeted.getPendingTargetOutOfBoardStatus(cardId, pendingState)
end

function Abilities.getPendingTargetRequestStatus(cardId)
  return AbilityTargeted.getPendingTargetRequestStatus(cardId)
end

function Abilities.resolvePendingTargetClick(scene, pendingState, worldX, worldY)
  return AbilityTargeted.resolvePendingClick(scene, pendingState, worldX, worldY)
end

function Abilities.applyPlayingStateContainers(scene, playingPayload)
  AbilityBoardEffects.applyPlayingState(scene, playingPayload)
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
    scene._invincibleTurnByPlayer = AbilityBuffs.normalizeInvincibleTurnByPlayer(effectPayload.invincibleTurnByPlayer)
  end
  if effectPayload.shockwaveOwnerPlayerIndex == 1 or effectPayload.shockwaveOwnerPlayerIndex == 2 then
    scene._shockwaveOwnerPlayerIndex = effectPayload.shockwaveOwnerPlayerIndex
  end
  AbilityBoardEffects.applyServerCardEffect(scene, effectPayload)
end

function Abilities.drawBoardEffects(scene)
  AbilityBoardEffects.drawBoardEffects(scene)
end

function Abilities.drawStoneStatusOverlays(scene)
  AbilityBoardEffects.drawStoneStatusOverlays(scene)
end

function Abilities.drawPendingCardPreview(scene, mouseX, mouseY)
  if scene._pendingCardTargetId and not scene._pendingCardTargetState then
    scene._pendingCardTargetState = AbilityTargeted.createPendingState(scene._pendingCardTargetId)
  end
  AbilityTargeted.drawPendingCardPreview(scene, mouseX, mouseY, scene._pendingCardTargetState)
end

function Abilities.isPlayerAbilitySealed(scene, playerIndex)
  return AbilityBoardEffects.isPlayerAbilitySealed(scene, playerIndex)
end

function Abilities.isStoneBoundOnCurrentTurn(scene, stoneId)
  return AbilityBoardEffects.isStoneBoundOnCurrentTurn(scene, stoneId)
end

function Abilities.getNextShotPowerMultiplier(scene, playerIndex)
  return AbilityBoardEffects.getNextShotPowerMultiplier(scene, playerIndex)
end

function Abilities.getStoneDampingMultiplier(scene, stone)
  return AbilityBoardEffects.getDampingMultiplierForStone(scene, stone)
end

function Abilities.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
  return AbilityBuffs.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
end

function Abilities.onTurnStart(scene, playerIndex)
  AbilityBoardEffects.onTurnStart(scene, playerIndex)
  AbilitySpecial.onTurnStart(scene, playerIndex)
end

function Abilities.onTurnEnd(scene, playerIndex)
  AbilityBoardEffects.onTurnEnd(scene, playerIndex)
  AbilitySpecial.onTurnEnd(scene, playerIndex)
end

function Abilities.onShotPrepare(scene, shotParams)
  AbilityBoardEffects.onShotPrepare(scene, shotParams)
  AbilitySpecial.onShotPrepare(scene, shotParams)
end

function Abilities.onShotResolved(scene, shotResult)
  AbilityBoardEffects.onShotResolved(scene, shotResult)
  AbilitySpecial.onShotResolved(scene, shotResult)
end

function Abilities.onStoneOut(scene, stone, cause)
  AbilityBoardEffects.onStoneOut(scene, stone, cause)
  AbilitySpecial.onStoneOut(scene, stone, cause)
end

return Abilities
