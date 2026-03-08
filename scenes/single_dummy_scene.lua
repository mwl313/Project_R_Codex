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
local GameMechanics = require("game_mechanics")
local InputCaptureGuard = require("utils.input_capture_guard")
local GodRelicDefs = require("single.god_relic_defs")
local GodRelicRuntime = require("single.god_relic_runtime")

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

local function computeAimPreviewSegments(boardX, boardY, stoneRadius, directionX, directionY, bounceCount, startX, startY)
  local segmentList = {}
  local dirLength = math.sqrt(directionX * directionX + directionY * directionY)
  if dirLength <= 0.0001 then
    return segmentList
  end

  local dirX = directionX / dirLength
  local dirY = directionY / dirLength
  local minX = boardX + stoneRadius
  local maxX = boardX + Constants.BOARD_W - stoneRadius
  local minY = boardY + stoneRadius
  local maxY = boardY + Constants.BOARD_H - stoneRadius
  local x = startX
  local y = startY
  local maxSegmentCount = math.max(1, math.min(20, math.floor(tonumber(bounceCount) or 0) + 1))
  local epsilon = 0.0001

  for _ = 1, maxSegmentCount do
    local tx = math.huge
    if dirX > epsilon then
      tx = (maxX - x) / dirX
    elseif dirX < -epsilon then
      tx = (minX - x) / dirX
    end

    local ty = math.huge
    if dirY > epsilon then
      ty = (maxY - y) / dirY
    elseif dirY < -epsilon then
      ty = (minY - y) / dirY
    end

    local travel = math.min(tx, ty)
    if travel == math.huge or travel <= epsilon then
      break
    end

    local hitX = x + dirX * travel
    local hitY = y + dirY * travel
    segmentList[#segmentList + 1] = {
      x1 = x,
      y1 = y,
      x2 = hitX,
      y2 = hitY
    }

    local nearXHit = math.abs(tx - travel) <= 0.001
    local nearYHit = math.abs(ty - travel) <= 0.001
    if nearXHit then
      dirX = -dirX
    end
    if nearYHit then
      dirY = -dirY
    end
    x = hitX
    y = hitY
  end

  return segmentList
end

local GOD_RELIC_DEBUG_BINDING_LIST = {
  { key = "3", kpKey = "kp3", id = GodRelicDefs.ID_ACTION_POWER },
  { key = "4", kpKey = "kp4", id = GodRelicDefs.ID_INFINITE_POWER },
  { key = "5", kpKey = "kp5", id = GodRelicDefs.ID_SAFETY },
  { key = "6", kpKey = "kp6", id = GodRelicDefs.ID_PRECISION_CONTROL },
  { key = "7", kpKey = "kp7", id = GodRelicDefs.ID_PIERCING_SHOT }
}

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
    _isShockwaveEnabled = false,
    _isOpponentInvincible = false,
    _backButton = nil,
    _godRelicRunState = { godRelicCounts = {}, godRelicIds = {} },
    _godRelicDebugButtonList = {},
    _playerPiercingChargesLeft = 0,
    _activeShotStoneId = nil,
    _activeShotOwnerPlayerIndex = nil,
    _activeShotPierceConsumed = false
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
  local debugButtonX = Constants.BASE_WORLD_W - 308
  local debugButtonY = 166
  local debugButtonW = 276
  local debugButtonH = 34
  for index, binding in ipairs(GOD_RELIC_DEBUG_BINDING_LIST) do
    local relicDef = GodRelicDefs.getById(binding.id)
    local keyText = tostring(binding.key or "")
    local label = string.format("%s) %s", keyText, tostring(relicDef and relicDef.nameKo or binding.id))
    local button = Button.new({
      x = debugButtonX,
      y = debugButtonY + (index - 1) * (debugButtonH + 8),
      w = debugButtonW,
      h = debugButtonH,
      label = label,
      onClick = function()
        instance:addGodRelicDebug(binding.id)
      end
    })
    instance._godRelicDebugButtonList[#instance._godRelicDebugButtonList + 1] = button
  end
  instance._godRelicDebugButtonList[#instance._godRelicDebugButtonList + 1] = Button.new({
    x = debugButtonX,
    y = debugButtonY + #GOD_RELIC_DEBUG_BINDING_LIST * (debugButtonH + 8) + 6,
    w = debugButtonW,
    h = debugButtonH,
    label = "8) GOD RESET",
    onClick = function()
      instance:clearGodRelicDebug()
    end
  })
  return instance
end

function SingleDummyScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function SingleDummyScene:resetDummyState()
  self._playingStoneList = createDummyStoneList()
  self._obstacleList = createDummyObstacleList()
  self._stoneVelocityMap = {}
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = false
  self._shouldSendSnapshotAfterSim = false
  self:cancelAimDrag(true)
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._shockwaveSourceStoneId = nil
  self._shockwaveOwnerPlayerIndex = nil
  self._invincibleTurnByPlayer = { [1] = nil, [2] = nil }
  GodRelicRuntime.clear(self._godRelicRunState)
  self._playerPiercingChargesLeft = 0
  self._activeShotStoneId = nil
  self._activeShotOwnerPlayerIndex = nil
  self._activeShotPierceConsumed = false
  if self._effectManager then
    self._effectManager:clear()
  end
  GameMechanics.resetStoneVelocities(self)
end

function SingleDummyScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  GodRelicRuntime.initRunState(self._godRelicRunState)
  self:resetDummyState()
  self:setStatus(t("single_dummy.status.entered"), Constants.COLOR_TEXT_SUB)
end

function SingleDummyScene:getGodRelicCount(godRelicId)
  return GodRelicRuntime.getCount(self._godRelicRunState, godRelicId)
end

function SingleDummyScene:addGodRelicDebug(godRelicId)
  local relicDef = GodRelicDefs.getById(godRelicId)
  local ok, nextCount = GodRelicRuntime.addGodRelic(self._godRelicRunState, godRelicId)
  if not ok then
    return
  end
  self:setStatus(t("single_dummy.status.god_relic_added", {
    name = tostring(relicDef and relicDef.nameKo or godRelicId),
    count = tostring(nextCount)
  }), Constants.COLOR_TEXT_SUB)
end

function SingleDummyScene:clearGodRelicDebug()
  GodRelicRuntime.clear(self._godRelicRunState)
  self._playerPiercingChargesLeft = 0
  self._activeShotStoneId = nil
  self._activeShotOwnerPlayerIndex = nil
  self._activeShotPierceConsumed = false
  self:setStatus(t("single_dummy.status.god_relic_cleared"), Constants.COLOR_TEXT_SUB)
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
  return not self._isShotSimulating
end

function SingleDummyScene:getAimPreviewBounceCount()
  return math.max(0, self:getGodRelicCount(GodRelicDefs.ID_PRECISION_CONTROL))
end

function SingleDummyScene:onShotImpulseApplied(stone, _shotPayload)
  local stoneId = type(stone) == "table" and tostring(stone.id or "") or ""
  local owner = type(stone) == "table" and math.floor(tonumber(stone.ownerPlayerIndex) or 0) or 0
  self._activeShotStoneId = stoneId ~= "" and stoneId or nil
  self._activeShotOwnerPlayerIndex = owner > 0 and owner or nil
  self._activeShotPierceConsumed = false
  self._playerPiercingChargesLeft = math.max(0, self:getGodRelicCount(GodRelicDefs.ID_PIERCING_SHOT))
end

function SingleDummyScene:consumePiercingCollision(stone, _collisionKind)
  if type(stone) ~= "table" then
    return false
  end
  if self._activeShotPierceConsumed then
    return false
  end
  if self._activeShotOwnerPlayerIndex ~= 1 then
    return false
  end
  if tostring(stone.id or "") ~= tostring(self._activeShotStoneId or "") then
    return false
  end
  if self._playerPiercingChargesLeft <= 0 then
    return false
  end
  self._playerPiercingChargesLeft = self._playerPiercingChargesLeft - 1
  self._activeShotPierceConsumed = true
  return true
end

function SingleDummyScene:shouldTreatOutAsWall(stone)
  if type(stone) ~= "table" then
    return false
  end
  if tonumber(stone.ownerPlayerIndex) ~= 1 then
    return false
  end
  return self:getGodRelicCount(GodRelicDefs.ID_SAFETY) > 0
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
  if self._isShockwaveEnabled then
    self._shockwaveOwnerPlayerIndex = 1
  else
    self._shockwaveOwnerPlayerIndex = nil
  end
  GameMechanics.applyShotImpulse(self, {
    stoneId = stone.id,
    dirX = dirX / dirLength,
    dirY = dirY / dirLength,
    power = power
  })
end

function SingleDummyScene:update(dt)
  self:updateAimDragInput()
  GameMechanics.updateShotSimulation(self, dt)
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
    if stone.alive ~= false then
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

  local bounceCount = self:getAimPreviewBounceCount()
  if bounceCount > 0 then
    local segmentList = computeAimPreviewSegments(
      self._boardX,
      self._boardY,
      Constants.STONE_RADIUS,
      dirX,
      dirY,
      bounceCount,
      stoneWorldX,
      stoneWorldY
    )
    love.graphics.setColor(0.35, 0.95, 1.00, 0.70)
    love.graphics.setLineWidth(2)
    for _, segment in ipairs(segmentList) do
      love.graphics.line(segment.x1, segment.y1, segment.x2, segment.y2)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.power_label", {
    power = string.format("%.0f", power)
  }), stoneWorldX - 50, stoneWorldY - 30, 100, "center")
end

function SingleDummyScene:drawGodRelicDebugPanel(mouseX, mouseY)
  local panelX = Constants.BASE_WORLD_W - 320
  local panelY = 98
  local panelW = 292
  local panelH = 560

  love.graphics.setColor(0.10, 0.16, 0.24, 0.92)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 10, 10)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 10, 10)

  love.graphics.setFont(FontManager.getFont("body"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single_dummy.god_debug_title"), panelX + 14, panelY + 14, panelW - 28, "left")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single_dummy.god_debug_hint"), panelX + 14, panelY + 42, panelW - 28, "left")

  for _, button in ipairs(self._godRelicDebugButtonList) do
    button:draw(mouseX, mouseY)
  end

  local lineY = panelY + 402
  local uiLineList = GodRelicRuntime.toUiLines(self._godRelicRunState)
  if #uiLineList == 0 then
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(t("single_dummy.god_debug_empty"), panelX + 14, lineY, panelW - 28, "left")
    return
  end

  love.graphics.setColor(Constants.COLOR_TEXT)
  for _, line in ipairs(uiLineList) do
    love.graphics.printf(line, panelX + 14, lineY, panelW - 28, "left")
    lineY = lineY + 20
    if lineY > panelY + panelH - 24 then
      break
    end
  end
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

function SingleDummyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local shockwaveText = self._isShockwaveEnabled and t("common.on") or t("common.off")
  local invincibleText = self._isOpponentInvincible and t("common.on") or t("common.off")

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single_dummy.title"), 0, 18, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single_dummy.subtitle", {
    shockwave = shockwaveText,
    invincible = invincibleText
  }), 0, 52, Constants.BASE_WORLD_W, "center")

  self:drawBoard()
  self:drawObstacles()
  self:drawStones()
  self:drawSelectedStoneHighlight()
  self:drawAimGuide(mouseX, mouseY)
  self:drawGodRelicDebugPanel(mouseX, mouseY)

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
  for _, buttonItem in ipairs(self._godRelicDebugButtonList) do
    if buttonItem:isHovered(mouseX, mouseY) then
      buttonItem:onClick()
      return
    end
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
  if key == "1" then
    self._isShockwaveEnabled = not self._isShockwaveEnabled
    self:setStatus(t("single_dummy.status.shockwave_toggle", {
      value = self._isShockwaveEnabled and t("common.on") or t("common.off")
    }), Constants.COLOR_TEXT_SUB)
    return
  end
  if key == "2" then
    self._isOpponentInvincible = not self._isOpponentInvincible
    if self._isOpponentInvincible then
      self._invincibleTurnByPlayer[2] = self._playingTurnIndex
    else
      self._invincibleTurnByPlayer[2] = nil
    end
    self:setStatus(t("single_dummy.status.invincible_toggle", {
      value = self._isOpponentInvincible and t("common.on") or t("common.off")
    }), Constants.COLOR_TEXT_SUB)
    return
  end
  for _, binding in ipairs(GOD_RELIC_DEBUG_BINDING_LIST) do
    if key == binding.key or key == binding.kpKey then
      self:addGodRelicDebug(binding.id)
      return
    end
  end
  if key == "8" or key == "kp8" then
    self:clearGodRelicDebug()
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
