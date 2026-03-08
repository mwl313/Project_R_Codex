--[[
파일명: abilities/targeted.lua
모듈명: AbilityTargeted

역할:
- 타겟 지정형 카드의 상태/검증/프리뷰/요청 payload 생성을 담당한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local CardRules = require("shared.card_rules")

local AbilityTargeted = {}

local TARGET_MODE_NONE = "NONE"
local TARGET_MODE_POINT = "POINT"
local TARGET_MODE_STONE_ENEMY = "STONE_ENEMY"
local TARGET_MODE_STONE_SELF_THEN_POINT = "STONE_SELF_THEN_POINT"
local TARGET_MODE_STONE_SELF_THEN_STONE_ENEMY = "STONE_SELF_THEN_STONE_ENEMY"

local function t(key, vars)
  return I18n.t(key, vars)
end

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function readTargetMode(cardId)
  local tunables = CardRules.getCardTunables(cardId)
  local raw = tunables.target_mode
  if type(raw) ~= "string" then
    return TARGET_MODE_NONE
  end
  return raw
end

local function getHoverStone(scene, worldX, worldY, predicate)
  local boardLocalX, boardLocalY = scene:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    return nil, nil, nil
  end
  local canonicalX, canonicalY = scene:localToCanonical(boardLocalX, boardLocalY)

  local nearestStone = nil
  local nearestDistanceSq = nil
  local hitRadius = Constants.STONE_RADIUS + 8
  local hitRadiusSq = hitRadius * hitRadius

  for _, stone in ipairs(scene._playingStoneList or {}) do
    local isRenderable = true
    if type(scene.shouldRenderStone) == "function" then
      isRenderable = scene:shouldRenderStone(stone)
    end
    if stone.alive ~= false and isRenderable and (not predicate or predicate(stone)) then
      local dx = stone.x - canonicalX
      local dy = stone.y - canonicalY
      local distanceSq = dx * dx + dy * dy
      if distanceSq <= hitRadiusSq and (nearestDistanceSq == nil or distanceSq < nearestDistanceSq) then
        nearestStone = stone
        nearestDistanceSq = distanceSq
      end
    end
  end

  return nearestStone, canonicalX, canonicalY
end

local function canPlaceIceFieldAtCanonical(canonicalX, canonicalY, radius)
  if canonicalX - radius < 0 or canonicalX + radius > Constants.BOARD_W then
    return false
  end
  if canonicalY - radius < 0 or canonicalY + radius > Constants.BOARD_H then
    return false
  end
  return true
end

local function drawStoneOutline(scene, stone, color, lineWidth)
  local localX, localY = scene:canonicalToLocal(stone.x, stone.y)
  love.graphics.setLineWidth(lineWidth or 2)
  love.graphics.setColor(color)
  love.graphics.circle("line", scene._boardX + localX, scene._boardY + localY, Constants.STONE_RADIUS + 4)
  love.graphics.setLineWidth(1)
end

function AbilityTargeted.getTargetMode(cardId)
  return readTargetMode(cardId)
end

function AbilityTargeted.needsTargeting(cardId)
  return readTargetMode(cardId) ~= TARGET_MODE_NONE
end

function AbilityTargeted.createPendingState(cardId)
  return {
    cardId = cardId,
    mode = readTargetMode(cardId),
    step = 1,
    sourceStoneId = nil,
    targetStoneId = nil
  }
end

function AbilityTargeted.getPendingTargetHint(cardId, pendingState)
  if cardId == "reinforcement" then
    return t("abilities.hint.reinforcement_click")
  end
  if cardId == "rockfall" then
    return t("abilities.hint.rockfall_click")
  end
  if cardId == "ice_field" then
    return t("abilities.hint.ice_field_click")
  end
  if cardId == "bind" then
    return t("abilities.hint.bind_click")
  end
  if cardId == "blackhole" then
    return t("abilities.hint.blackhole_click")
  end
  if cardId == "explosive" then
    return t("abilities.hint.explosive_click")
  end
  if cardId == "blink" then
    if pendingState and pendingState.step == 2 then
      return t("abilities.hint.blink_step2_click")
    end
    return t("abilities.hint.blink_step1_click")
  end
  if cardId == "swap" then
    if pendingState and pendingState.step == 2 then
      return t("abilities.hint.swap_step2_click")
    end
    return t("abilities.hint.swap_step1_click")
  end
  return t("abilities.hint.generic_click")
end

function AbilityTargeted.getPendingTargetStartStatus(cardId, pendingState)
  if cardId == "reinforcement" then
    return t("abilities.hint.reinforcement_start")
  end
  if cardId == "rockfall" then
    return t("abilities.hint.rockfall_start")
  end
  if cardId == "ice_field" then
    return t("abilities.hint.ice_field_start")
  end
  if cardId == "bind" then
    return t("abilities.hint.bind_start")
  end
  if cardId == "blackhole" then
    return t("abilities.hint.blackhole_start")
  end
  if cardId == "explosive" then
    return t("abilities.hint.explosive_start")
  end
  if cardId == "blink" then
    if pendingState and pendingState.step == 2 then
      return t("abilities.hint.blink_step2_start")
    end
    return t("abilities.hint.blink_step1_start")
  end
  if cardId == "swap" then
    if pendingState and pendingState.step == 2 then
      return t("abilities.hint.swap_step2_start")
    end
    return t("abilities.hint.swap_step1_start")
  end
  return t("abilities.hint.generic_start")
end

function AbilityTargeted.getPendingTargetOutOfBoardStatus(cardId, pendingState)
  if cardId == "reinforcement" then
    return t("abilities.hint.reinforcement_out_of_board")
  end
  if cardId == "rockfall" then
    return t("abilities.hint.rockfall_out_of_board")
  end
  if cardId == "ice_field" then
    return t("abilities.hint.ice_field_out_of_board")
  end
  if cardId == "blackhole" then
    return t("abilities.hint.blackhole_out_of_board")
  end
  if cardId == "explosive" then
    return t("abilities.hint.explosive_out_of_board")
  end
  if cardId == "blink" and pendingState and pendingState.step == 2 then
    return t("abilities.hint.blink_step2_out_of_board")
  end
  return t("abilities.hint.generic_out_of_board")
end

function AbilityTargeted.getPendingTargetRequestStatus(cardId)
  if cardId == "reinforcement" then
    return t("abilities.hint.reinforcement_sending")
  end
  if cardId == "rockfall" then
    return t("abilities.hint.rockfall_sending")
  end
  if cardId == "ice_field" then
    return t("abilities.hint.ice_field_sending")
  end
  if cardId == "bind" then
    return t("abilities.hint.bind_sending")
  end
  if cardId == "blackhole" then
    return t("abilities.hint.blackhole_sending")
  end
  if cardId == "explosive" then
    return t("abilities.hint.explosive_sending")
  end
  if cardId == "blink" then
    return t("abilities.hint.blink_sending")
  end
  if cardId == "swap" then
    return t("abilities.hint.swap_sending")
  end
  return t("abilities.hint.generic_sending")
end

function AbilityTargeted.canPlaceRockfallAtCanonical(scene, canonicalX, canonicalY)
  return scene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
end

function AbilityTargeted.canPlaceReinforcementAtCanonical(scene, canonicalX, canonicalY)
  return scene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
end

function AbilityTargeted.resolvePendingClick(scene, pendingState, worldX, worldY)
  if type(pendingState) ~= "table" or type(pendingState.cardId) ~= "string" then
    return { handled = false }
  end

  local cardId = pendingState.cardId
  local boardLocalX, boardLocalY = scene:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    return {
      handled = true,
      keepPending = true,
      statusText = AbilityTargeted.getPendingTargetOutOfBoardStatus(cardId, pendingState),
      statusColor = Constants.COLOR_DANGER
    }
  end
  local canonicalX, canonicalY = scene:localToCanonical(boardLocalX, boardLocalY)

  if cardId == "rockfall" or cardId == "reinforcement" then
    local canPlace, reason
    if cardId == "rockfall" then
      canPlace, reason = scene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
    else
      canPlace, reason = scene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
    end
    if not canPlace then
      return {
        handled = true,
        keepPending = true,
        statusText = reason or t("match.status.card_target_cannot_place"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        target = { x = canonicalX, y = canonicalY }
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "ice_field" then
    local tunables = CardRules.getCardTunables(cardId)
    local radius = math.max(20, tonumber(tunables.zone_radius) or 110)
    local canPlace = canPlaceIceFieldAtCanonical(canonicalX, canonicalY, radius)
    if not canPlace then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.ice_field_out_of_board"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        target = { x = canonicalX, y = canonicalY }
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "blackhole" then
    local tunables = CardRules.getCardTunables(cardId)
    local radius = math.max(20, tonumber(tunables.radius_px) or 130)
    local canPlace = canPlaceIceFieldAtCanonical(canonicalX, canonicalY, radius)
    if not canPlace then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.blackhole_out_of_board"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        target = { x = canonicalX, y = canonicalY }
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "explosive" then
    local tunables = CardRules.getCardTunables(cardId)
    local minDistance = math.max(1, tonumber(tunables.min_place_distance) or Constants.STONE_RADIUS * 2)
    local canPlace = type(scene.canPlaceStoneAtCanonicalExcluding) == "function"
      and scene:canPlaceStoneAtCanonicalExcluding(nil, canonicalX, canonicalY, minDistance)
    if not canPlace then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.explosive_cannot_place"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        target = { x = canonicalX, y = canonicalY }
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "bind" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    local targetStone = getHoverStone(scene, worldX, worldY, function(stone)
      return stone.ownerPlayerIndex ~= myPlayerIndex
    end)
    if not targetStone then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.bind_need_enemy_stone"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        targetStoneId = targetStone.id
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "blink" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    if pendingState.step == 1 then
      local sourceStone = getHoverStone(scene, worldX, worldY, function(stone)
        return stone.ownerPlayerIndex == myPlayerIndex
      end)
      if not sourceStone then
        return {
          handled = true,
          keepPending = true,
          statusText = t("abilities.validate.blink_need_own_stone"),
          statusColor = Constants.COLOR_DANGER
        }
      end
      pendingState.step = 2
      pendingState.sourceStoneId = sourceStone.id
      return {
        handled = true,
        keepPending = true,
        statusText = AbilityTargeted.getPendingTargetStartStatus(cardId, pendingState),
        statusColor = Constants.COLOR_TEXT_SUB
      }
    end

    local sourceStone = scene:getAliveStoneById(pendingState.sourceStoneId)
    if not sourceStone or sourceStone.ownerPlayerIndex ~= myPlayerIndex then
      return {
        handled = true,
        keepPending = false,
        statusText = t("abilities.validate.blink_source_missing"),
        statusColor = Constants.COLOR_DANGER
      }
    end

    local tunables = CardRules.getCardTunables(cardId)
    local maxDistance = math.max(1, tonumber(tunables.max_blink_distance) or 170)
    local dx = canonicalX - sourceStone.x
    local dy = canonicalY - sourceStone.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > maxDistance then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.blink_out_of_range"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    local canPlace = true
    local minDistance = Constants.STONE_RADIUS * 2
    if type(scene.canPlaceStoneAtCanonicalExcluding) == "function" then
      canPlace = scene:canPlaceStoneAtCanonicalExcluding(sourceStone.id, canonicalX, canonicalY, minDistance)
    end
    if not canPlace then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.blink_invalid_destination"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        sourceStoneId = sourceStone.id,
        target = { x = canonicalX, y = canonicalY }
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  if cardId == "swap" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    if pendingState.step == 1 then
      local myStone = getHoverStone(scene, worldX, worldY, function(stone)
        return stone.ownerPlayerIndex == myPlayerIndex
      end)
      if not myStone then
        return {
          handled = true,
          keepPending = true,
          statusText = t("abilities.validate.swap_need_own_stone"),
          statusColor = Constants.COLOR_DANGER
        }
      end
      pendingState.step = 2
      pendingState.sourceStoneId = myStone.id
      return {
        handled = true,
        keepPending = true,
        statusText = AbilityTargeted.getPendingTargetStartStatus(cardId, pendingState),
        statusColor = Constants.COLOR_TEXT_SUB
      }
    end

    local sourceStone = scene:getAliveStoneById(pendingState.sourceStoneId)
    if not sourceStone or sourceStone.ownerPlayerIndex ~= myPlayerIndex then
      return {
        handled = true,
        keepPending = false,
        statusText = t("abilities.validate.swap_source_missing"),
        statusColor = Constants.COLOR_DANGER
      }
    end

    local enemyStone = getHoverStone(scene, worldX, worldY, function(stone)
      return stone.ownerPlayerIndex ~= myPlayerIndex
    end)
    if not enemyStone then
      return {
        handled = true,
        keepPending = true,
        statusText = t("abilities.validate.swap_need_enemy_stone"),
        statusColor = Constants.COLOR_DANGER
      }
    end
    return {
      handled = true,
      keepPending = false,
      payload = {
        turnIndex = scene._playingTurnIndex,
        cardId = cardId,
        sourceStoneId = sourceStone.id,
        targetStoneId = enemyStone.id
      },
      statusText = AbilityTargeted.getPendingTargetRequestStatus(cardId),
      statusColor = Constants.COLOR_TEXT_SUB
    }
  end

  return { handled = false }
end

function AbilityTargeted.drawPendingCardPreview(scene, mouseX, mouseY, pendingState)
  if type(pendingState) ~= "table" or type(pendingState.cardId) ~= "string" then
    return
  end
  local cardId = pendingState.cardId
  if not scene:isPlayingPhase() or not scene:isMyTurn() then
    return
  end

  local boardLocalX, boardLocalY = scene:toBoardLocal(mouseX, mouseY)
  if not boardLocalX then
    return
  end
  local canonicalX, canonicalY = scene:localToCanonical(boardLocalX, boardLocalY)

  if cardId == "rockfall" then
    local canPlace = scene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
    local rockfallRule = CardRules.getRockfallRule()
    local width = math.max(1, rockfallRule.width or Constants.ROCK_OBSTACLE_WIDTH)
    local height = math.max(1, rockfallRule.height or Constants.ROCK_OBSTACLE_HEIGHT)
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
    return
  end

  if cardId == "reinforcement" then
    local canPlace = scene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.circle("fill", mouseX, mouseY, Constants.STONE_RADIUS)
    love.graphics.setColor(borderColor)
    love.graphics.circle("line", mouseX, mouseY, Constants.STONE_RADIUS)
    return
  end

  if cardId == "ice_field" then
    local tunables = CardRules.getCardTunables(cardId)
    local radius = math.max(20, tonumber(tunables.zone_radius) or 110)
    local canPlace = canPlaceIceFieldAtCanonical(canonicalX, canonicalY, radius)
    local color = canPlace and { 0.30, 0.70, 0.95, 0.18 } or { 0.90, 0.30, 0.30, 0.20 }
    local borderColor = canPlace and { 0.35, 0.80, 1.00, 0.75 } or { 0.90, 0.30, 0.30, 0.75 }
    love.graphics.setColor(color)
    love.graphics.circle("fill", mouseX, mouseY, radius)
    love.graphics.setColor(borderColor)
    love.graphics.circle("line", mouseX, mouseY, radius)
    return
  end

  if cardId == "bind" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    local hoverStone = getHoverStone(scene, mouseX, mouseY, function(stone)
      return stone.ownerPlayerIndex ~= myPlayerIndex
    end)
    if hoverStone then
      drawStoneOutline(scene, hoverStone, { 0.98, 0.55, 0.10, 1.0 }, 3)
    end
    return
  end

  if cardId == "blackhole" then
    local tunables = CardRules.getCardTunables(cardId)
    local radius = math.max(20, tonumber(tunables.radius_px) or 130)
    local canPlace = canPlaceIceFieldAtCanonical(canonicalX, canonicalY, radius)
    local color = canPlace and { 0.15, 0.10, 0.18, 0.30 } or { 0.90, 0.30, 0.30, 0.20 }
    local borderColor = canPlace and { 0.65, 0.55, 0.96, 0.80 } or { 0.90, 0.30, 0.30, 0.75 }
    love.graphics.setColor(color)
    love.graphics.circle("fill", mouseX, mouseY, radius)
    love.graphics.setColor(borderColor)
    love.graphics.circle("line", mouseX, mouseY, radius)
    love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], 0.45)
    love.graphics.circle("line", mouseX, mouseY, radius * 0.6)
    return
  end

  if cardId == "explosive" then
    local tunables = CardRules.getCardTunables(cardId)
    local minDistance = math.max(1, tonumber(tunables.min_place_distance) or Constants.STONE_RADIUS * 2)
    local canPlace = type(scene.canPlaceStoneAtCanonicalExcluding) == "function"
      and scene:canPlaceStoneAtCanonicalExcluding(nil, canonicalX, canonicalY, minDistance)
    local fill = canPlace and { 0.95, 0.34, 0.22, 0.32 } or { 0.90, 0.30, 0.30, 0.25 }
    local line = canPlace and { 1.0, 0.75, 0.22, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(fill)
    love.graphics.circle("fill", mouseX, mouseY, 12)
    love.graphics.setColor(line)
    love.graphics.circle("line", mouseX, mouseY, 12)
    local radius = math.max(20, tonumber(tunables.radius_px) or 120)
    love.graphics.setColor(line[1], line[2], line[3], 0.25)
    love.graphics.circle("line", mouseX, mouseY, radius)
    return
  end

  if cardId == "blink" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    if pendingState.step == 1 then
      local hoverStone = getHoverStone(scene, mouseX, mouseY, function(stone)
        return stone.ownerPlayerIndex == myPlayerIndex
      end)
      if hoverStone then
        drawStoneOutline(scene, hoverStone, { 0.35, 0.95, 0.55, 1.0 }, 3)
      end
      return
    end
    local sourceStone = scene:getAliveStoneById(pendingState.sourceStoneId)
    if not sourceStone then
      return
    end
    local tunables = CardRules.getCardTunables(cardId)
    local maxDistance = math.max(1, tonumber(tunables.max_blink_distance) or 170)
    local sourceLocalX, sourceLocalY = scene:canonicalToLocal(sourceStone.x, sourceStone.y)
    local sourceWorldX = scene._boardX + sourceLocalX
    local sourceWorldY = scene._boardY + sourceLocalY

    love.graphics.setColor(0.40, 0.95, 0.78, 0.22)
    love.graphics.circle("fill", sourceWorldX, sourceWorldY, maxDistance)
    love.graphics.setColor(0.40, 0.95, 0.78, 0.86)
    love.graphics.circle("line", sourceWorldX, sourceWorldY, maxDistance)

    local dx = canonicalX - sourceStone.x
    local dy = canonicalY - sourceStone.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local isInRange = distance <= maxDistance
    local canPlace = true
    local minDistance = Constants.STONE_RADIUS * 2
    if type(scene.canPlaceStoneAtCanonicalExcluding) == "function" then
      canPlace = scene:canPlaceStoneAtCanonicalExcluding(sourceStone.id, canonicalX, canonicalY, minDistance)
    end
    local ok = isInRange and canPlace
    local fill = ok and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local line = ok and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(fill)
    love.graphics.circle("fill", mouseX, mouseY, Constants.STONE_RADIUS)
    love.graphics.setColor(line)
    love.graphics.circle("line", mouseX, mouseY, Constants.STONE_RADIUS)
    drawStoneOutline(scene, sourceStone, { 0.42, 0.95, 0.78, 1.0 }, 3)
    return
  end

  if cardId == "swap" then
    local myPlayerIndex = scene:getMyPlayerIndex()
    if pendingState.step == 1 then
      local hoverStone = getHoverStone(scene, mouseX, mouseY, function(stone)
        return stone.ownerPlayerIndex == myPlayerIndex
      end)
      if hoverStone then
        drawStoneOutline(scene, hoverStone, { 0.35, 0.95, 0.55, 1.0 }, 3)
      end
      return
    end
    local sourceStone = scene:getAliveStoneById(pendingState.sourceStoneId)
    if sourceStone then
      drawStoneOutline(scene, sourceStone, { 0.35, 0.95, 0.55, 1.0 }, 3)
    end
    local enemyStone = getHoverStone(scene, mouseX, mouseY, function(stone)
      return stone.ownerPlayerIndex ~= myPlayerIndex
    end)
    if enemyStone then
      drawStoneOutline(scene, enemyStone, { 0.98, 0.55, 0.10, 1.0 }, 3)
    end
    return
  end
end

return AbilityTargeted
