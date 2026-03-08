--[[
파일명: single_dummy_scene.lua
모듈명: SingleDummyScene

역할:
- 싱글플레이 수동 테스트용 더미 씬.
- 네트워크 없이 game_mechanics.lua 공용 로직을 직접 검증한다.

외부에서 사용 가능한 함수:
- SingleDummyScene.new(app)

주의:
- 현재는 물리/입력 검증 목적의 더미이며, AI 로직은 포함하지 않는다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local EffectManager = require("effects.effect_manager")
local Abilities = require("abilities")
local CardRules = require("shared.card_rules")
local GameMechanics = require("game_mechanics")
local InputCaptureGuard = require("utils.input_capture_guard")

local SingleDummyScene = {}
SingleDummyScene.__index = SingleDummyScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function intersectSegmentWithWorldRect(fromX, fromY, toX, toY)
  local minX = 0
  local minY = 0
  local maxX = Constants.BASE_WORLD_W
  local maxY = Constants.BASE_WORLD_H

  if toX >= minX and toX <= maxX and toY >= minY and toY <= maxY then
    return toX, toY
  end

  local dx = toX - fromX
  local dy = toY - fromY
  local bestT = nil
  local bestX = nil
  local bestY = nil

  local function tryHit(t, x, y)
    if t < 0 or t > 1 then
      return
    end
    if x < minX or x > maxX or y < minY or y > maxY then
      return
    end
    if bestT == nil or t < bestT then
      bestT = t
      bestX = x
      bestY = y
    end
  end

  if dx ~= 0 then
    local tLeft = (minX - fromX) / dx
    tryHit(tLeft, minX, fromY + dy * tLeft)
    local tRight = (maxX - fromX) / dx
    tryHit(tRight, maxX, fromY + dy * tRight)
  end
  if dy ~= 0 then
    local tTop = (minY - fromY) / dy
    tryHit(tTop, fromX + dx * tTop, minY)
    local tBottom = (maxY - fromY) / dy
    tryHit(tBottom, fromX + dx * tBottom, maxY)
  end

  if bestX and bestY then
    return bestX, bestY
  end
  return clamp(toX, minX, maxX), clamp(toY, minY, maxY)
end

local function createDummyStoneList()
  local stoneList = {}
  local xList = { 180, 260, 340, 420, 220, 300, 380 }
  local hostYList = { 460, 460, 460, 460, 520, 520, 520 }
  local guestYList = { 140, 140, 140, 140, 200, 200, 200 }

  for index = 1, #xList do
    stoneList[#stoneList + 1] = {
      id = "p1_s" .. tostring(index),
      ownerPlayerIndex = 1,
      x = xList[index],
      y = hostYList[index],
      alive = true
    }
    stoneList[#stoneList + 1] = {
      id = "p2_s" .. tostring(index),
      ownerPlayerIndex = 2,
      x = xList[index],
      y = guestYList[index],
      alive = true
    }
  end

  return stoneList
end

local function createDummyObstacleList()
  return {
    {
      id = "dummy_rock_1",
      x = Constants.BOARD_W * 0.5,
      y = Constants.BOARD_H * 0.5,
      width = Constants.ROCK_OBSTACLE_WIDTH,
      height = Constants.ROCK_OBSTACLE_HEIGHT
    }
  }
end

local function copyPlayerStatusByIndex(value)
  local copied = {
    [1] = {},
    [2] = {}
  }
  for playerIndex = 1, 2 do
    local source = type(value) == "table" and value[playerIndex] or {}
    copied[playerIndex] = {
      abilitySealUntilTurn = source.abilitySealUntilTurn,
      reverseUntilTurn = source.reverseUntilTurn,
      cannotUseAbilityUntilTurn = source.cannotUseAbilityUntilTurn,
      suddenDeathEndTurn = source.suddenDeathEndTurn,
      drawOneRandomCardPerTurnUntilTurn = source.drawOneRandomCardPerTurnUntilTurn,
      nextShotPowerMultiplier = tonumber(source.nextShotPowerMultiplier),
      powerMoveCharges = tonumber(source.powerMoveCharges) or 0,
      powerMoveUntilTurn = source.powerMoveUntilTurn
    }
  end
  return copied
end

function SingleDummyScene.new(app)
  local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
  local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5
  local instance = {
    _app = app,
    _boardX = boardX,
    _boardY = boardY,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _backScene = "lobby",
    _playingStoneList = {},
    _obstacleList = {},
    _stoneVelocityMap = {},
    _simAccumulatorSec = 0,
    _simElapsedSec = 0,
    _isShotSimulating = false,
    _shouldSendSnapshotAfterSim = false,
    _activePlayerIndex = 1,
    _playingShotBudget = 1,
    _playingShotUsed = 0,
    _isAimDragging = false,
    _isAimRelativeMode = false,
    _aimStoneId = nil,
    _aimStartWorldX = nil,
    _aimStartWorldY = nil,
    _aimAccumWorldDX = 0,
    _aimAccumWorldDY = 0,
    _aimLastMouseWorldX = nil,
    _aimLastMouseWorldY = nil,
    _playingTurnIndex = 1,
    _invincibleTurnByPlayer = { [1] = nil, [2] = nil },
    _shockwaveOwnerPlayerIndex = nil,
    _shockwaveSourceStoneId = nil,
    _backButton = nil,
    _abilityButtonList = {},
    _nextTurnButton = nil,
    _pendingCardTargetId = nil,
    _pendingCardTargetState = nil,
    _debugEntitySeq = 0,
    _stoneStatusById = {},
    _playerStatusByIndex = {},
    _boardEffects = {},
    _turnHistory = {},
    _lockedStoneIdSet = {}
  }
  setmetatable(instance, SingleDummyScene)
  instance._effectManager = EffectManager.new()
  instance._backButton = Button.new({
    x = 20,
    y = 16,
    w = 160,
    h = 40,
    label = t("single_dummy.back_button"),
    onClick = function()
      instance._app:goScene(instance._backScene, {
        statusText = t("single_dummy.status.exited"),
        statusColor = Constants.COLOR_TEXT_SUB
      }, Config.TRANSITION_BACK)
    end
  })
  instance._nextTurnButton = Button.new({
    x = 28,
    y = 642,
    w = 272,
    h = 38,
    label = t("single_dummy.next_turn_button"),
    onClick = function()
      instance:advanceTurn()
    end
  })
  return instance
end

function SingleDummyScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function SingleDummyScene:rebuildAbilityButtons()
  self._abilityButtonList = {}
  local cardIdList = {}
  local pool = CardRules.getCardPool(CardRules.GAME_MODE_MULTI)
  for _, cardId in ipairs(pool or {}) do
    if Abilities.isSupportedTurnCard(cardId) then
      cardIdList[#cardIdList + 1] = cardId
    end
  end

  local panelX = 28
  local panelY = 124
  local buttonW = 130
  local buttonH = 32
  local gapX = 12
  local gapY = 8
  local cols = 2
  for index, cardId in ipairs(cardIdList) do
    local zeroIndex = index - 1
    local col = zeroIndex % cols
    local row = math.floor(zeroIndex / cols)
    local buttonX = panelX + col * (buttonW + gapX)
    local buttonY = panelY + row * (buttonH + gapY)
    local label = Abilities.getCardLabel(cardId)
    self._abilityButtonList[#self._abilityButtonList + 1] = Button.new({
      x = buttonX,
      y = buttonY,
      w = buttonW,
      h = buttonH,
      label = label,
      onClick = function()
        self:activateAbilityCard(cardId)
      end
    })
  end
end

function SingleDummyScene:resetDummyState()
  self._playingStoneList = createDummyStoneList()
  self._obstacleList = createDummyObstacleList()
  self._stoneVelocityMap = {}
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = false
  self._shouldSendSnapshotAfterSim = false
  self._activePlayerIndex = 1
  self._playingTurnIndex = 1
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  self._debugEntitySeq = 0
  self._pendingCardTargetId = nil
  self._pendingCardTargetState = nil
  self:cancelAimDrag(true)
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._shockwaveSourceStoneId = nil
  self._shockwaveOwnerPlayerIndex = nil
  self._invincibleTurnByPlayer = { [1] = nil, [2] = nil }
  self._lockedStoneIdSet = {}
  self._stoneStatusById = {}
  self._playerStatusByIndex = {
    [1] = {},
    [2] = {}
  }
  self._boardEffects = {
    iceZones = {},
    bombs = {},
    blackholeEffects = {}
  }
  self._turnHistory = {
    lastOpponentTurnDeaths = {},
    spawnPositionByStoneId = {}
  }
  for _, stone in ipairs(self._playingStoneList) do
    self._turnHistory.spawnPositionByStoneId[stone.id] = {
      x = stone.x,
      y = stone.y
    }
  end
  Abilities.applyPlayingStateContainers(self, {
    stoneStatusById = self._stoneStatusById,
    playerStatusByIndex = self._playerStatusByIndex,
    boardEffects = self._boardEffects,
    turnHistory = self._turnHistory
  })
  if self._effectManager then
    self._effectManager:clear()
  end
  GameMechanics.resetStoneVelocities(self)
  Abilities.onTurnStart(self, self._activePlayerIndex)
end

function SingleDummyScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:resetDummyState()
  self:rebuildAbilityButtons()
  self:setStatus(t("single_dummy.status.entered"), Constants.COLOR_TEXT_SUB)
end

function SingleDummyScene:getPlayingStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId then
      return stone
    end
  end
  return nil
end

function SingleDummyScene:getStoneVelocity(stoneId)
  local velocity = self._stoneVelocityMap[stoneId]
  if not velocity then
    velocity = { vx = 0, vy = 0 }
    self._stoneVelocityMap[stoneId] = velocity
  end
  return velocity
end

function SingleDummyScene:getMyRole()
  return "host"
end

function SingleDummyScene:getMyPlayerIndex()
  return 1
end

function SingleDummyScene:isPlayingPhase()
  return true
end

function SingleDummyScene:isMyTurn()
  return self._activePlayerIndex == self:getMyPlayerIndex()
end

function SingleDummyScene:canonicalToLocal(canonicalX, canonicalY)
  return canonicalX, canonicalY
end

function SingleDummyScene:localToCanonical(localX, localY)
  return localX, localY
end

function SingleDummyScene:createDebugPlayingEntityId(prefix)
  self._debugEntitySeq = (self._debugEntitySeq or 0) + 1
  return string.format("%s_dbg_%d", tostring(prefix or "dbg"), self._debugEntitySeq)
end

function SingleDummyScene:getAliveStoneById(stoneId)
  local stone = self:getPlayingStoneById(stoneId)
  if stone and stone.alive ~= false then
    return stone
  end
  return nil
end

function SingleDummyScene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
  return Abilities.canPlaceRockfallAtCanonical(self, canonicalX, canonicalY)
end

function SingleDummyScene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
  return Abilities.canPlaceReinforcementAtCanonical(self, canonicalX, canonicalY)
end

function SingleDummyScene:canPlaceStoneAtCanonicalExcluding(excludeStoneId, canonicalX, canonicalY, minDistance)
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  if canonicalX < minX or canonicalX > maxX or canonicalY < minY or canonicalY > maxY then
    return false
  end

  local safeMinDistance = type(minDistance) == "number" and math.max(0, minDistance) or Constants.MIN_PLACE_DISTANCE
  for _, stone in ipairs(self._playingStoneList or {}) do
    if stone.alive ~= false and stone.id ~= excludeStoneId then
      local dx = stone.x - canonicalX
      local dy = stone.y - canonicalY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < safeMinDistance then
        return false
      end
    end
  end

  for _, obstacle in ipairs(self._obstacleList or {}) do
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    local halfW = width * 0.5
    local halfH = height * 0.5
    local left = obstacle.x - halfW
    local right = obstacle.x + halfW
    local top = obstacle.y - halfH
    local bottom = obstacle.y + halfH
    local closestX = clamp(canonicalX, left, right)
    local closestY = clamp(canonicalY, top, bottom)
    local dx = canonicalX - closestX
    local dy = canonicalY - closestY
    if dx * dx + dy * dy < Constants.STONE_RADIUS * Constants.STONE_RADIUS then
      return false
    end
  end

  return true
end

function SingleDummyScene:isInvincibleOnCurrentTurn(playerIndex)
  return Abilities.isInvincibleOnCurrentTurn(self, playerIndex)
end

function SingleDummyScene:isShockwaveShotStone(stoneId)
  return Abilities.isShockwaveShotStone(self, stoneId)
end

function SingleDummyScene:applyShockwaveFromPoint(centerX, centerY)
  Abilities.applyShockwaveFromPoint(self, centerX, centerY)
end

function SingleDummyScene:applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
  return Abilities.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
end

function SingleDummyScene:canStoneCollideWithObstacle(stone, obstacle)
  return Abilities.canStoneCollideWithObstacle(self, stone, obstacle)
end

function SingleDummyScene:canStoneCollideWithStone(firstStone, secondStone)
  return Abilities.canStoneCollideWithStone(self, firstStone, secondStone)
end

function SingleDummyScene:shouldRenderStone(stone)
  return Abilities.shouldRenderStone(self, stone)
end

function SingleDummyScene:getStepAccelerationForStone(stone, velocity, stepSec)
  return Abilities.getStepAccelerationForStone(self, stone, velocity, stepSec)
end

function SingleDummyScene:onStoneOut(stone, cause)
  Abilities.onStoneOut(self, stone, cause)
end

function SingleDummyScene:sendHostSnapshotIfNeeded(_turnIndex, _reason)
end

function SingleDummyScene:toBoardLocal(worldX, worldY)
  local localX = worldX - self._boardX
  local localY = worldY - self._boardY
  if localX < 0 or localY < 0 or localX > Constants.BOARD_W or localY > Constants.BOARD_H then
    return nil, nil
  end
  return localX, localY
end

function SingleDummyScene:toBoardLocalNoClamp(worldX, worldY)
  return worldX - self._boardX, worldY - self._boardY
end

function SingleDummyScene:findAimStoneAt(worldX, worldY)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == 1 then
      local stoneWorldX = self._boardX + stone.x
      local stoneWorldY = self._boardY + stone.y
      local dx = worldX - stoneWorldX
      local dy = worldY - stoneWorldY
      if math.sqrt(dx * dx + dy * dy) <= Constants.STONE_RADIUS + 6 then
        return stone
      end
    end
  end
  return nil
end

function SingleDummyScene:isShotInputEnabled()
  return (not self._isShotSimulating)
    and (self._activePlayerIndex == 1)
    and (self._playingShotUsed < (self._playingShotBudget or 1))
    and (not self._pendingCardTargetId)
end

function SingleDummyScene:beginAimDrag(worldX, worldY)
  if not self:isShotInputEnabled() then
    return
  end
  local stone = self:findAimStoneAt(worldX, worldY)
  if not stone then
    return
  end
  self._isAimDragging = true
  self._aimStoneId = stone.id
  self._aimStartWorldX = worldX
  self._aimStartWorldY = worldY
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = worldX
  self._aimLastMouseWorldY = worldY
  self._isAimRelativeMode = InputCaptureGuard.captureRelativeMouse()
  if self._isAimRelativeMode then
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
  end
end

function SingleDummyScene:getAimCursorWorldPosition()
  local startWorldX = self._aimStartWorldX or 0
  local startWorldY = self._aimStartWorldY or 0
  return startWorldX + self._aimAccumWorldDX, startWorldY + self._aimAccumWorldDY
end

function SingleDummyScene:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local restoreWorldX, restoreWorldY = intersectSegmentWithWorldRect(stoneWorldX, stoneWorldY, aimWorldX, aimWorldY)
  return self._app:worldToScreen(restoreWorldX, restoreWorldY)
end

function SingleDummyScene:cancelAimDrag(_silent)
  local restoreScreenX = nil
  local restoreScreenY = nil
  if self._isAimDragging then
    self:updateAimDragInput()
    local stone = self:getPlayingStoneById(self._aimStoneId)
    if stone and stone.alive ~= false then
      local stoneWorldX = self._boardX + stone.x
      local stoneWorldY = self._boardY + stone.y
      restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
    end
  end

  if (not self._isAimDragging) and (not self._aimStoneId) then
    InputCaptureGuard.release(restoreScreenX, restoreScreenY)
    self._isAimRelativeMode = false
    self._aimStartWorldX = nil
    self._aimStartWorldY = nil
    self._aimAccumWorldDX = 0
    self._aimAccumWorldDY = 0
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
    return
  end

  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
end

function SingleDummyScene:updateAimDragInput()
  if not self._isAimDragging then
    return
  end

  if self._isAimRelativeMode then
    local relativeDx, relativeDy, isRelative = InputCaptureGuard.consumeRelativeDelta()
    if isRelative then
      local worldDx, worldDy = self._app:screenDeltaToWorldDelta(relativeDx, relativeDy)
      self._aimAccumWorldDX = self._aimAccumWorldDX + worldDx
      self._aimAccumWorldDY = self._aimAccumWorldDY + worldDy
      return
    end
    self._isAimRelativeMode = false
    InputCaptureGuard.release()
  end

  local mouseWorldX, mouseWorldY = self._app:getMouseWorldPosition()
  if self._aimLastMouseWorldX ~= nil and self._aimLastMouseWorldY ~= nil then
    self._aimAccumWorldDX = self._aimAccumWorldDX + (mouseWorldX - self._aimLastMouseWorldX)
    self._aimAccumWorldDY = self._aimAccumWorldDY + (mouseWorldY - self._aimLastMouseWorldY)
  end
  self._aimLastMouseWorldX = mouseWorldX
  self._aimLastMouseWorldY = mouseWorldY
end

function SingleDummyScene:commitAimDrag(_worldX, _worldY)
  if not self._isAimDragging then
    return
  end

  self:updateAimDragInput()

  local stone = self:getPlayingStoneById(self._aimStoneId)
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local restoreScreenX = nil
  local restoreScreenY = nil
  if stone and stone.alive ~= false then
    local stoneWorldX = self._boardX + stone.x
    local stoneWorldY = self._boardY + stone.y
    restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  end
  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
  if not stone or stone.alive == false then
    self._aimAccumWorldDX = 0
    self._aimAccumWorldDY = 0
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
    return
  end

  local stoneWorldX = self._boardX + stone.x
  local stoneWorldY = self._boardY + stone.y
  local dirX = stoneWorldX - aimWorldX
  local dirY = stoneWorldY - aimWorldY
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  local dragLength = math.sqrt(dirX * dirX + dirY * dirY)
  if dragLength < 1 then
    self:setStatus(t("single_dummy.status.drag_too_short"), Constants.COLOR_DANGER)
    return
  end

  local dirLength = math.sqrt(dirX * dirX + dirY * dirY)
  local power = math.min(Constants.MAX_SHOT_POWER, dragLength * Constants.POWER_PER_PIXEL)
  local shotSpeedScale = Abilities.getNextShotPowerMultiplier(self, 1) or 1
  Abilities.onShotPrepare(self, {
    shooterPlayerIndex = 1,
    stoneId = stone.id,
    power = power,
    shotSpeedScale = shotSpeedScale
  })
  if self._shockwaveOwnerPlayerIndex and stone.ownerPlayerIndex == self._shockwaveOwnerPlayerIndex then
    self._shockwaveSourceStoneId = stone.id
  else
    self._shockwaveSourceStoneId = nil
  end
  GameMechanics.applyShotImpulse(self, {
    stoneId = stone.id,
    dirX = dirX / dirLength,
    dirY = dirY / dirLength,
    power = power,
    shotSpeedScale = shotSpeedScale
  })
  local myStatus = self._playerStatusByIndex and self._playerStatusByIndex[1]
  if type(myStatus) == "table" and type(myStatus.nextShotPowerMultiplier) == "number" then
    myStatus.nextShotPowerMultiplier = nil
    myStatus.powerMoveCharges = 0
  end
  self._shockwaveOwnerPlayerIndex = nil
  self._playingShotUsed = (self._playingShotUsed or 0) + 1
end

function SingleDummyScene:update(dt)
  self:updateAimDragInput()
  local wasSimulating = self._isShotSimulating
  GameMechanics.updateShotSimulation(self, dt)
  if wasSimulating and (not self._isShotSimulating) then
    Abilities.onShotResolved(self, {
      activePlayerIndex = self._activePlayerIndex,
      turnIndex = self._playingTurnIndex
    })
  end
  if self._effectManager then
    self._effectManager:update(dt)
  end
end

function SingleDummyScene:drawBoard()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
  local centerY = self._boardY + Constants.BOARD_H * 0.5
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.line(self._boardX, centerY, self._boardX + Constants.BOARD_W, centerY)
end

function SingleDummyScene:drawStones()
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and self:shouldRenderStone(stone) then
      if stone.ownerPlayerIndex == 1 then
        love.graphics.setColor(Constants.COLOR_STONE_HOST)
      else
        love.graphics.setColor(Constants.COLOR_STONE_GUEST)
      end
      love.graphics.circle("fill", self._boardX + stone.x, self._boardY + stone.y, Constants.STONE_RADIUS)
      love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
      love.graphics.circle("line", self._boardX + stone.x, self._boardY + stone.y, Constants.STONE_RADIUS)
    end
  end
end

function SingleDummyScene:drawObstacles()
  love.graphics.setColor(0.44, 0.42, 0.40, 1.0)
  for _, obstacle in ipairs(self._obstacleList) do
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.rectangle("fill", self._boardX + obstacle.x - width * 0.5, self._boardY + obstacle.y - height * 0.5, width, height, 6, 6)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", self._boardX + obstacle.x - width * 0.5, self._boardY + obstacle.y - height * 0.5, width, height, 6, 6)
    love.graphics.setColor(0.44, 0.42, 0.40, 1.0)
  end
end

function SingleDummyScene:drawAimGuide(mouseX, mouseY)
  if not self._isAimDragging then
    return
  end
  local stone = self:getPlayingStoneById(self._aimStoneId)
  if not stone or stone.alive == false then
    return
  end

  local stoneWorldX = self._boardX + stone.x
  local stoneWorldY = self._boardY + stone.y
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local dirX = stoneWorldX - aimWorldX
  local dirY = stoneWorldY - aimWorldY
  local distance = math.sqrt(dirX * dirX + dirY * dirY)
  local power = math.min(Constants.MAX_SHOT_POWER, distance * Constants.POWER_PER_PIXEL)

  love.graphics.setColor(0.95, 0.92, 0.35, 0.95)
  love.graphics.setLineWidth(2)
  love.graphics.line(stoneWorldX, stoneWorldY, aimWorldX, aimWorldY)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.power_label", {
    power = string.format("%.0f", power)
  }), stoneWorldX - 50, stoneWorldY - 30, 100, "center")
end

function SingleDummyScene:drawSelectedStoneHighlight()
  if not self._isAimDragging then
    return
  end

  local stone = self:getPlayingStoneById(self._aimStoneId)
  if not stone or stone.alive == false then
    return
  end

  local stoneWorldX = self._boardX + stone.x
  local stoneWorldY = self._boardY + stone.y
  local timeSec = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  local pulse = math.sin(timeSec * 7.0) * 2.2
  local baseRadius = Constants.STONE_RADIUS + 4

  love.graphics.setColor(0.96, 0.88, 0.35, 0.12)
  love.graphics.circle("fill", stoneWorldX, stoneWorldY, baseRadius + 5 + pulse)

  love.graphics.setColor(0.98, 0.95, 0.65, 0.90)
  love.graphics.setLineWidth(2.6)
  love.graphics.circle("line", stoneWorldX, stoneWorldY, baseRadius + pulse)

  love.graphics.setColor(0.98, 0.95, 0.65, 0.45)
  love.graphics.setLineWidth(1.6)
  love.graphics.circle("line", stoneWorldX, stoneWorldY, baseRadius + 6 + pulse * 0.7)

  love.graphics.setLineWidth(1)
end

function SingleDummyScene:advanceTurn()
  Abilities.onTurnEnd(self, self._activePlayerIndex)
  self._activePlayerIndex = self._activePlayerIndex == 1 and 2 or 1
  self._playingTurnIndex = (self._playingTurnIndex or 1) + 1
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  Abilities.onTurnStart(self, self._activePlayerIndex)
  self:setStatus(t("single_dummy.status.turn_advanced", {
    turnIndex = self._playingTurnIndex,
    activePlayer = self._activePlayerIndex
  }), Constants.COLOR_TEXT_SUB)
end

function SingleDummyScene:activateAbilityCard(cardId)
  local abilityLabel = Abilities.getCardLabel(cardId)
  local myPlayerIndex = self:getMyPlayerIndex()
  if Abilities.isPlayerAbilitySealed(self, myPlayerIndex) then
    self:setStatus(t("single_dummy.status.ability_sealed"), Constants.COLOR_DANGER)
    return
  end
  if self._pendingCardTargetId then
    self._pendingCardTargetId = nil
    self._pendingCardTargetState = nil
  end

  if Abilities.needsTargeting(cardId) then
    self._pendingCardTargetId = cardId
    self._pendingCardTargetState = Abilities.createPendingTargetState(cardId)
    self:cancelAimDrag(true)
    self:setStatus(t("single_dummy.status.pending_target", {
      cardLabel = abilityLabel
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  local isOk, errorCode = self:applyLocalCardUsePayload({
    turnIndex = self._playingTurnIndex,
    cardId = cardId
  })
  if not isOk then
    self:setStatus(t("single_dummy.status.ability_failed", {
      code = tostring(errorCode or "card_use_failed")
    }), Constants.COLOR_DANGER)
  end
end

function SingleDummyScene:commitPendingCardTargetByWorld(worldX, worldY)
  if not self._pendingCardTargetId or not self._pendingCardTargetState then
    return false
  end

  local resolveResult = Abilities.resolvePendingTargetClick(self, self._pendingCardTargetState, worldX, worldY)
  if not resolveResult.handled then
    return false
  end
  if not resolveResult.keepPending then
    self._pendingCardTargetId = nil
    self._pendingCardTargetState = nil
  end
  if resolveResult.statusText then
    self:setStatus(resolveResult.statusText, resolveResult.statusColor or Constants.COLOR_TEXT_SUB)
  end
  if not resolveResult.payload then
    return true
  end

  local isOk, errorCode = self:applyLocalCardUsePayload(resolveResult.payload)
  if not isOk then
    self:setStatus(t("single_dummy.status.ability_failed", {
      code = tostring(errorCode or "card_use_failed")
    }), Constants.COLOR_DANGER)
    return true
  end
  return true
end

function SingleDummyScene:applyLocalCardUsePayload(payload)
  if type(payload) ~= "table" then
    return false, "invalid_payload"
  end

  local cardId = tostring(payload.cardId or "")
  local myPlayerIndex = self:getMyPlayerIndex()
  if not myPlayerIndex then
    return false, "role_missing"
  end

  local effectPayload = {}
  local tunables = CardRules.getCardTunables(cardId)
  local turnIndex = self._playingTurnIndex or 1
  local opponentPlayerIndex = myPlayerIndex == 1 and 2 or 1
  local function buildStoneStatusPatch(stoneIdList, mutateFn)
    local patch = {}
    for _, stoneIdValue in ipairs(stoneIdList or {}) do
      local sourceStatus = (self._stoneStatusById and self._stoneStatusById[stoneIdValue]) or {}
      local nextStatus = {
        ghostUntilTurn = sourceStatus.ghostUntilTurn,
        isGhost = sourceStatus.isGhost == true,
        invisibleToOpponentUntilTurn = sourceStatus.invisibleToOpponentUntilTurn,
        isInvisibleToOpponent = sourceStatus.isInvisibleToOpponent == true,
        boundUntilTurn = sourceStatus.boundUntilTurn,
        powerMoveCharges = tonumber(sourceStatus.powerMoveCharges) or 0,
        powerMoveUntilTurn = sourceStatus.powerMoveUntilTurn,
        nongaeUntilTurn = sourceStatus.nongaeUntilTurn,
        isNongae = sourceStatus.isNongae == true,
        spawnLockedThisTurn = sourceStatus.spawnLockedThisTurn == true
      }
      if type(mutateFn) == "function" then
        mutateFn(nextStatus, stoneIdValue)
      end
      patch[stoneIdValue] = nextStatus
    end
    return patch
  end

  if cardId == "agile" then
    local shotBudget = math.max(1, math.floor(tonumber(tunables.shot_budget) or 2))
    effectPayload.shotBudget = math.max(self._playingShotBudget or 1, shotBudget)
  elseif cardId == "invincible" then
    local turnOffset = math.max(1, math.floor(tonumber(tunables.protect_after_turn_offset) or 1))
    local invincibleByPlayer = {
      [1] = self._invincibleTurnByPlayer and self._invincibleTurnByPlayer[1] or nil,
      [2] = self._invincibleTurnByPlayer and self._invincibleTurnByPlayer[2] or nil
    }
    invincibleByPlayer[myPlayerIndex] = turnIndex + turnOffset
    effectPayload.invincibleTurnByPlayer = invincibleByPlayer
  elseif cardId == "shockwave" then
    effectPayload.shockwaveOwnerPlayerIndex = myPlayerIndex
  elseif cardId == "power_move" then
    local playerStatusByIndex = copyPlayerStatusByIndex(self._playerStatusByIndex)
    local myStatus = playerStatusByIndex[myPlayerIndex]
    myStatus.nextShotPowerMultiplier = clamp(tonumber(tunables.power_multiplier) or 1.25, 1, 2)
    effectPayload.playerStatusByIndex = playerStatusByIndex
  elseif cardId == "seal" then
    local playerStatusByIndex = copyPlayerStatusByIndex(self._playerStatusByIndex)
    local durationTurns = math.max(1, math.floor(tonumber(tunables.duration_turns) or 2))
    local opponentStatus = playerStatusByIndex[opponentPlayerIndex]
    opponentStatus.abilitySealUntilTurn = turnIndex + durationTurns
    effectPayload.playerStatusByIndex = playerStatusByIndex
  elseif cardId == "ghost" then
    local durationTurns = math.max(1, math.floor(tonumber(tunables.duration_turns) or 1))
    local targetStoneIdList = {}
    for _, stone in ipairs(self._playingStoneList or {}) do
      if stone.alive ~= false and stone.ownerPlayerIndex == myPlayerIndex then
        targetStoneIdList[#targetStoneIdList + 1] = stone.id
      end
    end
    effectPayload.stoneStatusById = buildStoneStatusPatch(targetStoneIdList, function(status)
      status.ghostUntilTurn = turnIndex + durationTurns
      status.isGhost = true
    end)
  elseif cardId == "stealth" then
    local durationTurns = math.max(1, math.floor(tonumber(tunables.duration_turns) or 1))
    local targetStoneIdList = {}
    for _, stone in ipairs(self._playingStoneList or {}) do
      if stone.alive ~= false and stone.ownerPlayerIndex == myPlayerIndex then
        targetStoneIdList[#targetStoneIdList + 1] = stone.id
      end
    end
    effectPayload.stoneStatusById = buildStoneStatusPatch(targetStoneIdList, function(status)
      status.invisibleToOpponentUntilTurn = turnIndex + durationTurns
      status.isInvisibleToOpponent = true
    end)
  elseif cardId == "rebirth" then
    local deathStoneIdList = (self._turnHistory and self._turnHistory.lastOpponentTurnDeaths) or {}
    local movedStones = {}
    local patchStoneIdList = {}
    for _, stoneIdValue in ipairs(deathStoneIdList) do
      local stone = self:getPlayingStoneById(stoneIdValue)
      if stone and stone.ownerPlayerIndex == myPlayerIndex and stone.alive == false then
        stone.alive = true
        movedStones[#movedStones + 1] = {
          id = stone.id,
          x = stone.x,
          y = stone.y,
          resetVelocity = true
        }
        patchStoneIdList[#patchStoneIdList + 1] = stone.id
      end
    end
    if #movedStones <= 0 then
      return false, "invalid_card_target"
    end
    effectPayload.movedStones = movedStones
    effectPayload.stoneStatusById = buildStoneStatusPatch(patchStoneIdList, function(status)
      status.boundUntilTurn = nil
      status.spawnLockedThisTurn = false
    end)
  elseif cardId == "reposition" then
    local aliveStoneList = {}
    for _, stone in ipairs(self._playingStoneList or {}) do
      if stone.alive ~= false then
        aliveStoneList[#aliveStoneList + 1] = stone
      end
    end
    if #aliveStoneList <= 0 then
      return false, "invalid_card_target"
    end
    local minDistance = math.max(1, tonumber(tunables.min_place_distance) or Constants.STONE_RADIUS * 2)
    local minX = Constants.STONE_RADIUS
    local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
    local minY = Constants.STONE_RADIUS
    local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
    local placed = {}
    local movedStones = {}
    local function canPlaceCandidate(x, y)
      if x < minX or x > maxX or y < minY or y > maxY then
        return false
      end
      for _, other in ipairs(placed) do
        local dx = other.x - x
        local dy = other.y - y
        if math.sqrt(dx * dx + dy * dy) < minDistance then
          return false
        end
      end
      return self:canPlaceStoneAtCanonicalExcluding(nil, x, y, minDistance)
    end
    for _, stone in ipairs(aliveStoneList) do
      local foundX, foundY = nil, nil
      for _ = 1, 280 do
        local candidateX = minX + math.random() * (maxX - minX)
        local candidateY = minY + math.random() * (maxY - minY)
        if canPlaceCandidate(candidateX, candidateY) then
          foundX = candidateX
          foundY = candidateY
          break
        end
      end
      if not foundX then
        return false, "invalid_card_target"
      end
      stone.x = foundX
      stone.y = foundY
      placed[#placed + 1] = { x = foundX, y = foundY }
      movedStones[#movedStones + 1] = {
        id = stone.id,
        x = foundX,
        y = foundY,
        resetVelocity = true
      }
    end
    effectPayload.movedStones = movedStones
  elseif cardId == "blackhole" then
    local target = payload.target
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then
      return false, "invalid_card_target"
    end
    local radius = math.max(20, tonumber(tunables.radius_px) or 130)
    if target.x - radius < 0 or target.x + radius > Constants.BOARD_W or target.y - radius < 0 or target.y + radius > Constants.BOARD_H then
      return false, "invalid_card_target"
    end
    effectPayload.blackholeEffectAdded = {
      id = self:createDebugPlayingEntityId("blackhole"),
      ownerPlayerIndex = myPlayerIndex,
      x = target.x,
      y = target.y,
      radius = radius,
      durationMs = math.max(100, math.floor(tonumber(tunables.duration_ms) or 650)),
      accelPxPerSec2 = math.max(1, tonumber(tunables.accel_px_per_sec2) or 220),
      createdAtMs = math.floor((love.timer.getTime() or os.clock()) * 1000)
    }
  elseif cardId == "explosive" then
    local target = payload.target
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then
      return false, "invalid_card_target"
    end
    local minDistance = math.max(1, tonumber(tunables.min_place_distance) or Constants.STONE_RADIUS * 2)
    if not self:canPlaceStoneAtCanonicalExcluding(nil, target.x, target.y, minDistance) then
      return false, "invalid_card_target"
    end
    effectPayload.bombAdded = {
      id = self:createDebugPlayingEntityId("bomb"),
      ownerPlayerIndex = myPlayerIndex,
      x = target.x,
      y = target.y,
      explodeAtTurn = turnIndex + math.max(1, math.floor(tonumber(tunables.delay_turns) or 7)),
      radius = math.max(20, tonumber(tunables.radius_px) or 120),
      impulse = math.max(1, tonumber(tunables.impulse_px_per_sec) or 650)
    }
  elseif cardId == "reinforcement" then
    local target = payload.target
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then
      return false, "invalid_card_target"
    end
    local canPlace = self:canPlaceReinforcementAtCanonical(target.x, target.y)
    if not canPlace then
      return false, "invalid_card_target"
    end
    local stoneId = self:createDebugPlayingEntityId(string.format("p%d_r", myPlayerIndex))
    effectPayload.spawnStone = {
      id = stoneId,
      ownerPlayerIndex = myPlayerIndex,
      x = target.x,
      y = target.y,
      alive = true
    }
    if tunables.lock_spawned_stone_for_turn ~= false then
      local nextLockedStoneIds = {}
      for stoneIdValue in pairs(self._lockedStoneIdSet or {}) do
        nextLockedStoneIds[#nextLockedStoneIds + 1] = stoneIdValue
      end
      nextLockedStoneIds[#nextLockedStoneIds + 1] = stoneId
      effectPayload.lockedStoneIds = nextLockedStoneIds
    end
    effectPayload.stoneStatusById = {
      [stoneId] = {
        ghostUntilTurn = nil,
        isGhost = false,
        invisibleToOpponentUntilTurn = nil,
        isInvisibleToOpponent = false,
        boundUntilTurn = nil,
        powerMoveCharges = 0,
        powerMoveUntilTurn = nil,
        nongaeUntilTurn = nil,
        isNongae = false,
        spawnLockedThisTurn = true
      }
    }
  elseif cardId == "rockfall" then
    local target = payload.target
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then
      return false, "invalid_card_target"
    end
    local canPlace = self:canPlaceRockfallAtCanonical(target.x, target.y)
    if not canPlace then
      return false, "invalid_card_target"
    end
    effectPayload.obstacle = {
      id = self:createDebugPlayingEntityId("rock"),
      x = target.x,
      y = target.y,
      width = math.max(1, tonumber(tunables.width) or Constants.ROCK_OBSTACLE_WIDTH),
      height = math.max(1, tonumber(tunables.height) or Constants.ROCK_OBSTACLE_HEIGHT)
    }
  elseif cardId == "bind" then
    local targetStoneId = tostring(payload.targetStoneId or "")
    local targetStone = self:getAliveStoneById(targetStoneId)
    if not targetStone or targetStone.ownerPlayerIndex == myPlayerIndex then
      return false, "invalid_card_target"
    end
    local durationTurns = math.max(1, math.floor(tonumber(tunables.duration_turns) or 3))
    effectPayload.stoneStatusById = buildStoneStatusPatch({ targetStone.id }, function(status)
      status.boundUntilTurn = turnIndex + durationTurns
    end)
  elseif cardId == "ice_field" then
    local target = payload.target
    if type(target) ~= "table" or type(target.x) ~= "number" or type(target.y) ~= "number" then
      return false, "invalid_card_target"
    end
    local radius = math.max(20, tonumber(tunables.zone_radius) or 110)
    if target.x - radius < 0 or target.x + radius > Constants.BOARD_W or target.y - radius < 0 or target.y + radius > Constants.BOARD_H then
      return false, "invalid_card_target"
    end
    local durationTurns = math.max(1, math.floor(tonumber(tunables.duration_turns) or 2))
    effectPayload.iceZoneAdded = {
      id = self:createDebugPlayingEntityId("ice"),
      ownerPlayerIndex = myPlayerIndex,
      x = target.x,
      y = target.y,
      radius = radius,
      dampingMultiplier = clamp(tonumber(tunables.damping_multiplier) or 0.45, 0.05, 1),
      expiresAtTurn = turnIndex + durationTurns
    }
  elseif cardId == "blink" then
    local sourceStoneId = tostring(payload.sourceStoneId or "")
    local sourceStone = self:getAliveStoneById(sourceStoneId)
    local target = payload.target
    if (not sourceStone) or sourceStone.ownerPlayerIndex ~= myPlayerIndex or type(target) ~= "table" then
      return false, "invalid_card_target"
    end
    if Abilities.isStoneBoundOnCurrentTurn(self, sourceStone.id) then
      return false, "invalid_card_target"
    end
    local targetX = tonumber(target.x)
    local targetY = tonumber(target.y)
    if not targetX or not targetY then
      return false, "invalid_card_target"
    end
    local maxDistance = math.max(1, tonumber(tunables.max_blink_distance) or 170)
    local dx = targetX - sourceStone.x
    local dy = targetY - sourceStone.y
    if math.sqrt(dx * dx + dy * dy) > maxDistance then
      return false, "invalid_card_target"
    end
    local minDistance = math.max(1, tonumber(tunables.min_place_distance) or Constants.STONE_RADIUS * 2)
    if not self:canPlaceStoneAtCanonicalExcluding(sourceStone.id, targetX, targetY, minDistance) then
      return false, "invalid_card_target"
    end
    effectPayload.movedStones = {
      {
        id = sourceStone.id,
        x = targetX,
        y = targetY,
        resetVelocity = true
      }
    }
  elseif cardId == "swap" then
    local sourceStone = self:getAliveStoneById(tostring(payload.sourceStoneId or ""))
    local targetStone = self:getAliveStoneById(tostring(payload.targetStoneId or ""))
    if (not sourceStone) or (not targetStone) then
      return false, "invalid_card_target"
    end
    if sourceStone.ownerPlayerIndex ~= myPlayerIndex or targetStone.ownerPlayerIndex == myPlayerIndex then
      return false, "invalid_card_target"
    end
    effectPayload.movedStones = {
      {
        id = sourceStone.id,
        x = targetStone.x,
        y = targetStone.y,
        resetVelocity = true
      },
      {
        id = targetStone.id,
        x = sourceStone.x,
        y = sourceStone.y,
        resetVelocity = true
      }
    }
  else
    return false, "card_not_implemented"
  end

  Abilities.applyServerCardEffect(self, effectPayload)
  if type(effectPayload.shotBudget) == "number" then
    self._playingShotBudget = effectPayload.shotBudget
  end
  self._pendingCardTargetId = nil
  self._pendingCardTargetState = nil
  self:setStatus(t("single_dummy.status.ability_applied", {
    cardLabel = tostring(Abilities.getCardLabel(cardId))
  }), Constants.COLOR_TEXT_SUB)
  return true, nil
end

function SingleDummyScene:drawAbilityPanel(mouseX, mouseY)
  local panelX = 20
  local panelY = 90
  local panelW = 288
  local panelH = 594
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12, 12)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12, 12)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single_dummy.ability_panel_title"), panelX, panelY + 10, panelW, "center")
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single_dummy.turn_line", {
    turnIndex = self._playingTurnIndex or 1,
    activePlayer = self._activePlayerIndex or 1,
    shotUsed = self._playingShotUsed or 0,
    shotBudget = self._playingShotBudget or 1
  }), panelX + 10, panelY + 36, panelW - 20, "center")
  if self._pendingCardTargetId then
    love.graphics.setColor(0.95, 0.89, 0.45, 1.0)
    love.graphics.printf(t("single_dummy.pending_line", {
      cardLabel = Abilities.getCardLabel(self._pendingCardTargetId)
    }), panelX + 10, panelY + 58, panelW - 20, "center")
  end

  for _, button in ipairs(self._abilityButtonList or {}) do
    button:draw(mouseX, mouseY)
  end
  if self._nextTurnButton then
    self._nextTurnButton:draw(mouseX, mouseY)
  end
end

function SingleDummyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single_dummy.title"), 0, 18, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single_dummy.subtitle"), 0, 52, Constants.BASE_WORLD_W, "center")

  self:drawAbilityPanel(mouseX, mouseY)
  self:drawBoard()
  Abilities.drawBoardEffects(self)
  self:drawObstacles()
  self:drawStones()
  Abilities.drawStoneStatusOverlays(self)
  self:drawSelectedStoneHighlight()
  self:drawAimGuide(mouseX, mouseY)
  Abilities.drawPendingCardPreview(self, mouseX, mouseY)

  if self._effectManager then
    self._effectManager:draw(self._boardX, self._boardY, function(canonicalX, canonicalY)
      return canonicalX, canonicalY
    end)
  end

  self._backButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleDummyScene:mousepressed(mouseX, mouseY, button)
  if button == 2 then
    if self._pendingCardTargetId then
      self._pendingCardTargetId = nil
      self._pendingCardTargetState = nil
      self:setStatus(t("single_dummy.status.target_cancel"), Constants.COLOR_TEXT_SUB)
      return
    end
    self:cancelAimDrag()
    return
  end
  if button ~= 1 then
    return
  end

  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end

  if self._nextTurnButton and self._nextTurnButton:isHovered(mouseX, mouseY) then
    self._nextTurnButton:onClick()
    return
  end

  for _, buttonItem in ipairs(self._abilityButtonList or {}) do
    if buttonItem:isHovered(mouseX, mouseY) then
      buttonItem:onClick()
      return
    end
  end

  if self:commitPendingCardTargetByWorld(mouseX, mouseY) then
    return
  end

  self:beginAimDrag(mouseX, mouseY)
end

function SingleDummyScene:mousereleased(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  self:commitAimDrag(mouseX, mouseY)
end

function SingleDummyScene:keypressed(key)
  if key == "escape" then
    if self._pendingCardTargetId then
      self._pendingCardTargetId = nil
      self._pendingCardTargetState = nil
      self:setStatus(t("single_dummy.status.target_cancel"), Constants.COLOR_TEXT_SUB)
      return
    end
    self._app:goScene(self._backScene, {
      statusText = t("single_dummy.status.exited"),
      statusColor = Constants.COLOR_TEXT_SUB
    }, Config.TRANSITION_BACK)
    return
  end
  if key == "r" then
    self:resetDummyState()
    self:setStatus(t("single_dummy.status.reset_done"), Constants.COLOR_TEXT_SUB)
    return
  end
  if key == "n" then
    self:advanceTurn()
    return
  end
  if key == "x" and self._pendingCardTargetId then
    self._pendingCardTargetId = nil
    self._pendingCardTargetState = nil
    self:setStatus(t("single_dummy.status.target_cancel"), Constants.COLOR_TEXT_SUB)
  end
end

function SingleDummyScene:onSceneWillChange(_event)
  self:cancelAimDrag(true)
end

function SingleDummyScene:exit()
  self:cancelAimDrag(true)
end

function SingleDummyScene:onAppEvent(event)
  if event.type == "focus_lost" then
    self:cancelAimDrag(true)
  end
end

return SingleDummyScene
