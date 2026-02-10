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
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local EffectManager = require("effects.effect_manager")
local Abilities = require("abilities")
local GameMechanics = require("game_mechanics")

local SingleDummyScene = {}
SingleDummyScene.__index = SingleDummyScene

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
    _playingStoneList = {},
    _obstacleList = {},
    _stoneVelocityMap = {},
    _simAccumulatorSec = 0,
    _simElapsedSec = 0,
    _isShotSimulating = false,
    _shouldSendSnapshotAfterSim = false,
    _isAimDragging = false,
    _aimStoneId = nil,
    _playingTurnIndex = 1,
    _invincibleTurnByPlayer = { [1] = nil, [2] = nil },
    _shockwaveOwnerPlayerIndex = nil,
    _shockwaveSourceStoneId = nil,
    _isShockwaveEnabled = false,
    _isOpponentInvincible = false,
    _backButton = nil
  }
  setmetatable(instance, SingleDummyScene)
  instance._effectManager = EffectManager.new()
  instance._backButton = Button.new({
    x = 20,
    y = 16,
    w = 160,
    h = 40,
    label = "로비로",
    onClick = function()
      instance._app:goLobby({
        statusText = "싱글 더미 테스트 종료",
        statusColor = Constants.COLOR_TEXT_SUB
      })
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
  self._isAimDragging = false
  self._aimStoneId = nil
  self._shockwaveSourceStoneId = nil
  self._shockwaveOwnerPlayerIndex = nil
  self._invincibleTurnByPlayer = { [1] = nil, [2] = nil }
  if self._effectManager then
    self._effectManager:clear()
  end
  GameMechanics.resetStoneVelocities(self)
end

function SingleDummyScene:enter(_params)
  self:resetDummyState()
  self:setStatus("더미 모드: 드래그 발사 / 1=충격파 / 2=상대 무적 / R=리셋", Constants.COLOR_TEXT_SUB)
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
end

function SingleDummyScene:cancelAimDrag()
  self._isAimDragging = false
  self._aimStoneId = nil
end

function SingleDummyScene:commitAimDrag(worldX, worldY)
  if not self._isAimDragging then
    return
  end

  local stone = self:getPlayingStoneById(self._aimStoneId)
  self._isAimDragging = false
  self._aimStoneId = nil
  if not stone or stone.alive == false then
    return
  end

  local mouseLocalX, mouseLocalY = self:toBoardLocalNoClamp(worldX, worldY)
  local dirX = stone.x - mouseLocalX
  local dirY = stone.y - mouseLocalY
  local dragLength = math.sqrt(dirX * dirX + dirY * dirY)
  if dragLength < 1 then
    self:setStatus("드래그 거리가 너무 짧습니다.", Constants.COLOR_DANGER)
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
  local dirX = stoneWorldX - mouseX
  local dirY = stoneWorldY - mouseY
  local distance = math.sqrt(dirX * dirX + dirY * dirY)
  local power = math.min(Constants.MAX_SHOT_POWER, distance * Constants.POWER_PER_PIXEL)

  love.graphics.setColor(0.95, 0.92, 0.35, 0.95)
  love.graphics.setLineWidth(2)
  love.graphics.line(stoneWorldX, stoneWorldY, mouseX, mouseY)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(string.format("Power %.0f", power), stoneWorldX - 50, stoneWorldY - 30, 100, "center")
end

function SingleDummyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local shockwaveText = self._isShockwaveEnabled and "ON" or "OFF"
  local invincibleText = self._isOpponentInvincible and "ON" or "OFF"

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("Single Dummy (Manual Test)", 0, 18, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("충격파(1): " .. shockwaveText .. " | 상대 무적(2): " .. invincibleText .. " | R: 리셋 | ESC: 로비", 0, 52, Constants.BASE_WORLD_W, "center")

  self:drawBoard()
  self:drawObstacles()
  self:drawStones()
  self:drawAimGuide(mouseX, mouseY)

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
    self._app:goLobby({
      statusText = "싱글 더미 테스트 종료",
      statusColor = Constants.COLOR_TEXT_SUB
    })
    return
  end
  if key == "r" then
    self:resetDummyState()
    self:setStatus("더미 상태를 초기화했습니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if key == "1" then
    self._isShockwaveEnabled = not self._isShockwaveEnabled
    self:setStatus("충격파 토글: " .. (self._isShockwaveEnabled and "ON" or "OFF"), Constants.COLOR_TEXT_SUB)
    return
  end
  if key == "2" then
    self._isOpponentInvincible = not self._isOpponentInvincible
    if self._isOpponentInvincible then
      self._invincibleTurnByPlayer[2] = self._playingTurnIndex
    else
      self._invincibleTurnByPlayer[2] = nil
    end
    self:setStatus("상대 무적 토글: " .. (self._isOpponentInvincible and "ON" or "OFF"), Constants.COLOR_TEXT_SUB)
  end
end

function SingleDummyScene:onAppEvent(_event)
end

return SingleDummyScene
