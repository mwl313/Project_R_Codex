--[[
파일명: match_scene.lua
모듈명: MatchScene

역할:
- Phase 3 매치 진행 화면(배치/공개/카드선택/턴 플레이 기본)
- 배치 클릭 입력, 제출, 공개 렌더링, 카드 선택 처리

외부에서 사용 가능한 함수:
- MatchScene.new(app)

주의:
- 모든 좌표 입력은 world 좌표 기준으로 처리한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local EffectManager = require("effects.effect_manager")

local MatchScene = {}
MatchScene.__index = MatchScene

local CARD_LABEL_MAP = {
  reinforcement = "신병",
  shockwave = "충격파",
  invincible = "무적",
  rockfall = "낙석",
  agile = "날렵함"
}

local function nowEpochMs()
  return os.time() * 1000
end

local function getCardSelectPanelRect(boardX, boardY)
  local panelMarginX = 70
  local panelMarginTop = 54
  local panelMarginBottom = 54
  return {
    x = boardX + panelMarginX,
    y = boardY + panelMarginTop,
    w = Constants.BOARD_W - panelMarginX * 2,
    h = Constants.BOARD_H - panelMarginTop - panelMarginBottom
  }
end

local function cloneStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      x = stone.x,
      y = stone.y
    }
  end
  return cloned
end

local function cloneStringList(valueList)
  local cloned = {}
  for _, value in ipairs(valueList or {}) do
    cloned[#cloned + 1] = tostring(value)
  end
  return cloned
end

local function clonePlayingStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      ownerPlayerIndex = stone.ownerPlayerIndex,
      x = stone.x,
      y = stone.y,
      alive = stone.alive ~= false
    }
  end
  return cloned
end

local function cloneObstacleList(obstacleList)
  local cloned = {}
  for _, obstacle in ipairs(obstacleList or {}) do
    cloned[#cloned + 1] = {
      id = obstacle.id,
      x = obstacle.x,
      y = obstacle.y,
      width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
      height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    }
  end
  return cloned
end

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
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

local function listToSet(valueList)
  local valueSet = {}
  for _, value in ipairs(valueList or {}) do
    valueSet[tostring(value)] = true
  end
  return valueSet
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

local function normalizeInvincibleTurnByPlayer(value)
  return {
    [1] = readTurnIndexByPlayer(value, 1),
    [2] = readTurnIndexByPlayer(value, 2)
  }
end

local function createDefaultRoomState()
  return {
    phase = Constants.PHASE_PLACEMENT_PRIVATE,
    timers = {},
    match = {
      firstPlayerIndex = nil,
      placement = {
        mySubmitted = false,
        opponentSubmitted = false,
        myStones = {},
        revealStones = nil
      },
      cardSelect = {
        myDealtCards = {},
        myPickedCards = {},
        myPickCount = 0,
        myLocked = false,
        opponentLocked = false,
        selectEndsAtMs = nil
      },
      playing = {
        turnIndex = 1,
        activePlayerIndex = 1,
        turnEndsAtMs = nil,
        shotBudget = 1,
        shotUsed = 0,
        hasCardUsedThisTurn = false,
        lockedStoneIds = {},
        obstacles = {},
        invincibleTurnByPlayer = { [1] = nil, [2] = nil },
        shockwaveOwnerPlayerIndex = nil,
        shotCommitted = false,
        awaitingSnapshot = false,
        stones = {}
      }
    },
    result = nil
  }
end

local function containsString(valueList, target)
  for _, value in ipairs(valueList) do
    if value == target then
      return true
    end
  end
  return false
end

local function removeString(valueList, target)
  for index, value in ipairs(valueList) do
    if value == target then
      table.remove(valueList, index)
      return true
    end
  end
  return false
end

local function getCardLabel(cardId)
  return CARD_LABEL_MAP[cardId] or tostring(cardId)
end

function MatchScene.new(app)
  local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
  local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5

  local instance = {
    _app = app,
    _roomState = createDefaultRoomState(),
    _statusText = "매치 상태 동기화 중...",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _boardX = boardX,
    _boardY = boardY,

    _myStoneList = {},
    _isPlacementSubmitted = false,
    _isSubmitPending = false,
    _revealStoneMap = nil,
    _submitButton = nil,

    _myDealtCardList = {},
    _myPickedCardList = {},
    _selectedCardList = {},
    _myPickCount = 0,
    _isMyCardLocked = false,
    _isOpponentCardLocked = false,
    _isCardPickPending = false,
    _cardSelectEndsAtMs = nil,
    _cardOptionButtonList = {},
    _cardConfirmButton = nil,

    _playingStoneList = {},
    _playingTurnIndex = 1,
    _activePlayerIndex = 1,
    _turnEndsAtMs = nil,
    _playingShotBudget = 1,
    _playingShotUsed = 0,
    _hasUsedCardThisTurn = false,
    _lockedStoneIdSet = {},
    _obstacleList = {},
    _invincibleTurnByPlayer = { [1] = nil, [2] = nil },
    _shockwaveOwnerPlayerIndex = nil,
    _shockwaveSourceStoneId = nil,
    _isPlayingShotCommitted = false,
    _isPlayingAwaitingSnapshot = false,
    _isTurnShotPending = false,
    _isCardUsePending = false,
    _pendingCardTargetId = nil,
    _isSurrenderPending = false,
    _isAimDragging = false,
    _aimStoneId = nil,
    _lastAutoSnapshotTurnIndex = nil,
    _stoneVelocityMap = {},
    _simAccumulatorSec = 0,
    _simElapsedSec = 0,
    _isShotSimulating = false,
    _shouldSendSnapshotAfterSim = false,
    _playingCardButtonList = {},
    _surrenderButton = nil,
    _resultRematchButton = nil,
    _resultLobbyButton = nil,
    _isResultVotePending = false,
    _myResultVote = nil,
    _opponentResultVote = nil
  }
  setmetatable(instance, MatchScene)
  instance._effectManager = EffectManager.new()

  instance._submitButton = Button.new({
    x = Constants.BASE_WORLD_W - 260,
    y = 666,
    w = 200,
    h = 42,
    label = "배치 제출",
    onClick = function()
      instance:submitPlacement()
    end
  })

  instance._cardConfirmButton = Button.new({
    x = 0,
    y = 0,
    w = 220,
    h = 42,
    label = "선택 확정",
    onClick = function()
      instance:submitCardPick()
    end
  })

  instance._surrenderButton = Button.new({
    x = Constants.BASE_WORLD_W - 250,
    y = 16,
    w = 220,
    h = 40,
    label = "기권",
    color = Constants.COLOR_DANGER,
    hoverColor = { 0.80, 0.28, 0.30, 1.0 },
    onClick = function()
      instance:requestSurrender()
    end
  })

  instance._resultRematchButton = Button.new({
    x = 0,
    y = 0,
    w = 190,
    h = 44,
    label = "재대결",
    onClick = function()
      instance:requestResultVote("rematch")
    end
  })

  instance._resultLobbyButton = Button.new({
    x = 0,
    y = 0,
    w = 190,
    h = 44,
    label = "로비로",
    color = Constants.COLOR_DANGER,
    hoverColor = { 0.80, 0.28, 0.30, 1.0 },
    onClick = function()
      instance:requestResultVote("to_lobby")
    end
  })

  return instance
end

function MatchScene:enter(params)
  self._roomState = createDefaultRoomState()

  self._myStoneList = {}
  self._isPlacementSubmitted = false
  self._isSubmitPending = false
  self._revealStoneMap = nil

  self._myDealtCardList = {}
  self._myPickedCardList = {}
  self._selectedCardList = {}
  self._myPickCount = 0
  self._isMyCardLocked = false
  self._isOpponentCardLocked = false
  self._isCardPickPending = false
  self._cardSelectEndsAtMs = nil
  self._cardOptionButtonList = {}

  self._playingStoneList = {}
  self._playingTurnIndex = 1
  self._activePlayerIndex = 1
  self._turnEndsAtMs = nil
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  self._hasUsedCardThisTurn = false
  self._lockedStoneIdSet = {}
  self._obstacleList = {}
  self._invincibleTurnByPlayer = { [1] = nil, [2] = nil }
  self._shockwaveOwnerPlayerIndex = nil
  self._shockwaveSourceStoneId = nil
  self._isPlayingShotCommitted = false
  self._isPlayingAwaitingSnapshot = false
  self._isTurnShotPending = false
  self._isCardUsePending = false
  self._pendingCardTargetId = nil
  self._isSurrenderPending = false
  self._isAimDragging = false
  self._aimStoneId = nil
  self._lastAutoSnapshotTurnIndex = nil
  self._stoneVelocityMap = {}
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = false
  self._shouldSendSnapshotAfterSim = false
  self._playingCardButtonList = {}
  self._isResultVotePending = false
  self._myResultVote = nil
  self._opponentResultVote = nil
  if self._effectManager then
    self._effectManager:clear()
  end

  if params and type(params.roomState) == "table" then
    self:applyRoomState(params.roomState)
  end
end

function MatchScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function MatchScene:getMyRole()
  local session = self._app:getSession()
  return session and session.role or nil
end

function MatchScene:getMyPlayerIndex()
  local role = self:getMyRole()
  if role == "host" then
    return 1
  end
  if role == "guest" then
    return 2
  end
  return nil
end

function MatchScene:isPlacementPhase()
  return self._roomState.phase == Constants.PHASE_PLACEMENT_PRIVATE
end

function MatchScene:isCardSelectPhase()
  return self._roomState.phase == Constants.PHASE_CARD_SELECT
end

function MatchScene:isPlayingPhase()
  return self._roomState.phase == Constants.PHASE_PLAYING
end

function MatchScene:isMyTurn()
  return self:isPlayingPhase() and self:getMyPlayerIndex() == self._activePlayerIndex
end

function MatchScene:isShotInputEnabled()
  return self:isMyTurn()
    and (not self._isPlayingShotCommitted)
    and (not self._isPlayingAwaitingSnapshot)
    and (not self._isTurnShotPending)
    and (not self._isCardUsePending)
    and (not self._pendingCardTargetId)
end

function MatchScene:isRevealVisiblePhase()
  local phase = self._roomState.phase
  return phase == Constants.PHASE_PLACEMENT_REVEAL or phase == Constants.PHASE_CARD_SELECT or phase == Constants.PHASE_PLAYING or phase == Constants.PHASE_RESULT
end

function MatchScene:canonicalToLocal(canonicalX, canonicalY)
  local role = self:getMyRole()
  if role == "guest" then
    return canonicalX, Constants.BOARD_H - canonicalY
  end
  return canonicalX, canonicalY
end

function MatchScene:localToCanonical(localX, localY)
  local role = self:getMyRole()
  if role == "guest" then
    return localX, Constants.BOARD_H - localY
  end
  return localX, localY
end

function MatchScene:toBoardLocal(worldX, worldY)
  local localX = worldX - self._boardX
  local localY = worldY - self._boardY
  if localX < 0 or localY < 0 or localX > Constants.BOARD_W or localY > Constants.BOARD_H then
    return nil, nil
  end
  return localX, localY
end

function MatchScene:toBoardLocalNoClamp(worldX, worldY)
  return worldX - self._boardX, worldY - self._boardY
end

function MatchScene:canPlaceAtCanonical(canonicalX, canonicalY)
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  if canonicalX < minX or canonicalX > maxX or canonicalY < minY or canonicalY > maxY then
    return false, "보드 경계를 벗어났습니다."
  end

  local centerY = Constants.BOARD_H * 0.5
  local role = self:getMyRole()
  if role == "host" and canonicalY < centerY + Constants.NO_PLACE_BUFFER then
    return false, "내 진영(하단 절반) 안에서만 배치할 수 있습니다."
  end
  if role == "guest" and canonicalY > centerY - Constants.NO_PLACE_BUFFER then
    return false, "내 진영(하단 절반) 안에서만 배치할 수 있습니다."
  end

  for _, stone in ipairs(self._myStoneList) do
    local dx = stone.x - canonicalX
    local dy = stone.y - canonicalY
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < Constants.MIN_PLACE_DISTANCE then
      return false, "기존 배치와 너무 가깝습니다."
    end
  end

  return true, nil
end

function MatchScene:getAliveStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId and stone.alive ~= false then
      return stone
    end
  end
  return nil
end

function MatchScene:findAimStoneAt(worldX, worldY)
  local myPlayerIndex = self:getMyPlayerIndex()
  if not myPlayerIndex then
    return nil
  end

  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == myPlayerIndex and (not self._lockedStoneIdSet[stone.id]) then
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      local stoneWorldX = self._boardX + localX
      local stoneWorldY = self._boardY + localY
      local dx = worldX - stoneWorldX
      local dy = worldY - stoneWorldY
      if math.sqrt(dx * dx + dy * dy) <= Constants.STONE_RADIUS + 6 then
        return stone
      end
    end
  end
  return nil
end

function MatchScene:getPlayingStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId then
      return stone
    end
  end
  return nil
end

function MatchScene:getStoneVelocity(stoneId)
  local velocity = self._stoneVelocityMap[stoneId]
  if not velocity then
    velocity = { vx = 0, vy = 0 }
    self._stoneVelocityMap[stoneId] = velocity
  end
  return velocity
end

function MatchScene:isInvincibleOnCurrentTurn(playerIndex)
  local invincibleTurnByPlayer = self._invincibleTurnByPlayer
  if type(invincibleTurnByPlayer) ~= "table" then
    return false
  end
  local protectedTurnIndex = invincibleTurnByPlayer[playerIndex]
  if type(protectedTurnIndex) ~= "number" then
    protectedTurnIndex = invincibleTurnByPlayer[tostring(playerIndex)]
  end
  return type(protectedTurnIndex) == "number" and protectedTurnIndex == self._playingTurnIndex
end

function MatchScene:isShockwaveShotStone(stoneId)
  if type(stoneId) ~= "string" then
    return false
  end
  return self._shockwaveOwnerPlayerIndex ~= nil and self._shockwaveSourceStoneId == stoneId
end

function MatchScene:applyShockwaveFromPoint(centerX, centerY)
  local shockwaveRadius = Constants.STONE_RADIUS * Constants.SHOCKWAVE_RANGE_MULTIPLIER
  if shockwaveRadius <= 0 then
    return
  end
  if self._effectManager then
    self._effectManager:addShockwavePulse(centerX, centerY, shockwaveRadius)
  end

  local impulseStrength = math.max(0, Constants.SHOCKWAVE_STRENGTH)
  if impulseStrength <= 0 then
    return
  end

  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.id ~= self._shockwaveSourceStoneId and (not self:isInvincibleOnCurrentTurn(stone.ownerPlayerIndex)) then
      local dx = stone.x - centerX
      local dy = stone.y - centerY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance > 0 and distance <= shockwaveRadius then
        local velocity = self:getStoneVelocity(stone.id)
        velocity.vx = velocity.vx + (dx / distance) * impulseStrength
        velocity.vy = velocity.vy + (dy / distance) * impulseStrength
      end
    end
  end
end

function MatchScene:resetStoneVelocities()
  self._stoneVelocityMap = {}
  for _, stone in ipairs(self._playingStoneList) do
    self._stoneVelocityMap[stone.id] = { vx = 0, vy = 0 }
  end
end

function MatchScene:resolveObstacleCollision(stone, obstacle)
  local halfW = (obstacle.width or Constants.ROCK_OBSTACLE_WIDTH) * 0.5
  local halfH = (obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT) * 0.5
  local left = obstacle.x - halfW
  local right = obstacle.x + halfW
  local top = obstacle.y - halfH
  local bottom = obstacle.y + halfH
  local closestX = clamp(stone.x, left, right)
  local closestY = clamp(stone.y, top, bottom)
  local dx = stone.x - closestX
  local dy = stone.y - closestY
  local distanceSq = dx * dx + dy * dy
  local minDistanceSq = Constants.STONE_RADIUS * Constants.STONE_RADIUS

  if distanceSq >= minDistanceSq then
    return false, nil, nil
  end

  local normalX, normalY
  local overlap

  if distanceSq > 0 then
    local distance = math.sqrt(distanceSq)
    normalX = dx / distance
    normalY = dy / distance
    overlap = Constants.STONE_RADIUS - distance
  else
    local penLeft = math.abs(stone.x - left)
    local penRight = math.abs(right - stone.x)
    local penTop = math.abs(stone.y - top)
    local penBottom = math.abs(bottom - stone.y)
    local minPen = math.min(penLeft, penRight, penTop, penBottom)
    if minPen == penLeft then
      normalX, normalY = -1, 0
      overlap = Constants.STONE_RADIUS + penLeft
    elseif minPen == penRight then
      normalX, normalY = 1, 0
      overlap = Constants.STONE_RADIUS + penRight
    elseif minPen == penTop then
      normalX, normalY = 0, -1
      overlap = Constants.STONE_RADIUS + penTop
    else
      normalX, normalY = 0, 1
      overlap = Constants.STONE_RADIUS + penBottom
    end
  end

  stone.x = stone.x + normalX * overlap
  stone.y = stone.y + normalY * overlap

  local velocity = self:getStoneVelocity(stone.id)
  local normalSpeed = velocity.vx * normalX + velocity.vy * normalY
  if normalSpeed < 0 then
    local reflectScale = -(1 + Constants.PHYSICS_RESTITUTION) * normalSpeed
    velocity.vx = velocity.vx + reflectScale * normalX
    velocity.vy = velocity.vy + reflectScale * normalY
  end
  return true, closestX, closestY
end

function MatchScene:syncStoneVelocityMap()
  local nextVelocityMap = {}
  for _, stone in ipairs(self._playingStoneList) do
    local velocity = self._stoneVelocityMap[stone.id]
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
  self._stoneVelocityMap = nextVelocityMap
end

function MatchScene:startShotSimulation()
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = true
end

function MatchScene:stopShotSimulation()
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = false

  if self._shouldSendSnapshotAfterSim then
    self._shouldSendSnapshotAfterSim = false
    self:sendHostSnapshotIfNeeded(self._playingTurnIndex, "sim_done")
  end
end

function MatchScene:applyShotImpulse(shotPayload)
  if type(shotPayload) ~= "table" then
    return
  end
  if type(shotPayload.stoneId) ~= "string" then
    return
  end
  if type(shotPayload.dirX) ~= "number" or type(shotPayload.dirY) ~= "number" or type(shotPayload.power) ~= "number" then
    return
  end

  local stone = self:getPlayingStoneById(shotPayload.stoneId)
  if not stone or stone.alive == false then
    return
  end

  local directionLength = math.sqrt(shotPayload.dirX * shotPayload.dirX + shotPayload.dirY * shotPayload.dirY)
  if directionLength <= 0 then
    return
  end

  local velocity = self:getStoneVelocity(stone.id)
  local speed = math.max(0, shotPayload.power * Constants.SHOT_SPEED_SCALE)
  velocity.vx = shotPayload.dirX / directionLength * speed
  velocity.vy = shotPayload.dirY / directionLength * speed
  if self._shockwaveOwnerPlayerIndex and stone.ownerPlayerIndex == self._shockwaveOwnerPlayerIndex then
    self._shockwaveSourceStoneId = stone.id
  else
    self._shockwaveSourceStoneId = nil
  end
  self:startShotSimulation()
end

function MatchScene:resolveStoneCollision(firstStone, secondStone)
  local dx = secondStone.x - firstStone.x
  local dy = secondStone.y - firstStone.y
  local distanceSq = dx * dx + dy * dy
  local minDistance = Constants.STONE_RADIUS * 2
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
  local firstInvincible = self:isInvincibleOnCurrentTurn(firstStone.ownerPlayerIndex)
  local secondInvincible = self:isInvincibleOnCurrentTurn(secondStone.ownerPlayerIndex)

  if firstInvincible and not secondInvincible then
    secondStone.x = secondStone.x + normalX * penetration
    secondStone.y = secondStone.y + normalY * penetration
  elseif secondInvincible and not firstInvincible then
    firstStone.x = firstStone.x - normalX * penetration
    firstStone.y = firstStone.y - normalY * penetration
  else
    local correctionX = normalX * penetration * 0.5
    local correctionY = normalY * penetration * 0.5
    firstStone.x = firstStone.x - correctionX
    firstStone.y = firstStone.y - correctionY
    secondStone.x = secondStone.x + correctionX
    secondStone.y = secondStone.y + correctionY
  end

  local firstVelocity = self:getStoneVelocity(firstStone.id)
  local secondVelocity = self:getStoneVelocity(secondStone.id)
  if firstInvincible ~= secondInvincible then
    local movingVelocity
    local awayNormalX
    local awayNormalY
    if firstInvincible then
      movingVelocity = secondVelocity
      awayNormalX = normalX
      awayNormalY = normalY
    else
      movingVelocity = firstVelocity
      awayNormalX = -normalX
      awayNormalY = -normalY
    end

    local towardSpeed = movingVelocity.vx * awayNormalX + movingVelocity.vy * awayNormalY
    if towardSpeed < 0 then
      local reflectScale = -(1 + Constants.PHYSICS_RESTITUTION) * towardSpeed
      movingVelocity.vx = movingVelocity.vx + reflectScale * awayNormalX
      movingVelocity.vy = movingVelocity.vy + reflectScale * awayNormalY
    end

    local collisionX = (firstStone.x + secondStone.x) * 0.5
    local collisionY = (firstStone.y + secondStone.y) * 0.5
    return true, collisionX, collisionY
  end

  local relativeX = secondVelocity.vx - firstVelocity.vx
  local relativeY = secondVelocity.vy - firstVelocity.vy
  local normalSpeed = relativeX * normalX + relativeY * normalY
  if normalSpeed < 0 then
    local impulse = -(1 + Constants.PHYSICS_RESTITUTION) * normalSpeed * 0.5
    if not firstInvincible then
      firstVelocity.vx = firstVelocity.vx - impulse * normalX
      firstVelocity.vy = firstVelocity.vy - impulse * normalY
    end
    if not secondInvincible then
      secondVelocity.vx = secondVelocity.vx + impulse * normalX
      secondVelocity.vy = secondVelocity.vy + impulse * normalY
    end
  end
  local collisionX = (firstStone.x + secondStone.x) * 0.5
  local collisionY = (firstStone.y + secondStone.y) * 0.5
  return true, collisionX, collisionY
end

function MatchScene:simulateShotStep(stepSec)
  local aliveStoneList = {}
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  local damping = math.max(0, 1 - Constants.PHYSICS_DAMPING_PER_SEC * stepSec)

  for _, stone in ipairs(self._playingStoneList) do
    local velocity = self:getStoneVelocity(stone.id)
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
    for _, obstacle in ipairs(self._obstacleList) do
      local collided = self:resolveObstacleCollision(stone, obstacle)
      if collided and self:isShockwaveShotStone(stone.id) then
        self:applyShockwaveFromPoint(stone.x, stone.y)
      end
    end
  end

  for firstIndex = 1, #aliveStoneList - 1 do
    for secondIndex = firstIndex + 1, #aliveStoneList do
      local firstStone = aliveStoneList[firstIndex]
      local secondStone = aliveStoneList[secondIndex]
      local collided = self:resolveStoneCollision(firstStone, secondStone)
      if collided and self:isShockwaveShotStone(firstStone.id) then
        self:applyShockwaveFromPoint(firstStone.x, firstStone.y)
      elseif collided and self:isShockwaveShotStone(secondStone.id) then
        self:applyShockwaveFromPoint(secondStone.x, secondStone.y)
      end
    end
  end

  for _, stone in ipairs(self._playingStoneList) do
    local velocity = self:getStoneVelocity(stone.id)
    if stone.alive ~= false then
      if stone.x < minX or stone.x > maxX or stone.y < minY or stone.y > maxY then
        if self:isShockwaveShotStone(stone.id) then
          self:applyShockwaveFromPoint(stone.x, stone.y)
        end
        stone.alive = false
        velocity.vx = 0
        velocity.vy = 0
      else
        velocity.vx = velocity.vx * damping
        velocity.vy = velocity.vy * damping
        local speed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
        if speed < Constants.PHYSICS_STOP_SPEED then
          velocity.vx = 0
          velocity.vy = 0
        end
      end
    end
  end
end

function MatchScene:hasAnyStoneInMotion()
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false then
      local velocity = self:getStoneVelocity(stone.id)
      local speed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
      if speed >= Constants.PHYSICS_STOP_SPEED then
        return true
      end
    end
  end
  return false
end

function MatchScene:updateShotSimulation(dt)
  if not self._isShotSimulating then
    return
  end

  self._simAccumulatorSec = self._simAccumulatorSec + math.min(dt, 0.05)
  while self._simAccumulatorSec >= Constants.PHYSICS_FIXED_STEP_SEC do
    self:simulateShotStep(Constants.PHYSICS_FIXED_STEP_SEC)
    self._simAccumulatorSec = self._simAccumulatorSec - Constants.PHYSICS_FIXED_STEP_SEC
    self._simElapsedSec = self._simElapsedSec + Constants.PHYSICS_FIXED_STEP_SEC

    if (not self:hasAnyStoneInMotion()) or self._simElapsedSec >= Constants.PHYSICS_MAX_SIM_SEC then
      self:stopShotSimulation()
      break
    end
  end
end

function MatchScene:addPlacementByWorld(worldX, worldY)
  if not self:isPlacementPhase() then
    return
  end
  if self._isPlacementSubmitted or self._isSubmitPending then
    self:setStatus("이미 배치를 제출했습니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if #self._myStoneList >= Constants.STONE_COUNT_PER_PLAYER then
    self:setStatus("배치 가능 개수(7개)를 모두 사용했습니다.", Constants.COLOR_DANGER)
    return
  end

  local boardLocalX, boardLocalY = self:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    return
  end

  local canonicalX, canonicalY = self:localToCanonical(boardLocalX, boardLocalY)
  local canPlace, reasonText = self:canPlaceAtCanonical(canonicalX, canonicalY)
  if not canPlace then
    self:setStatus(reasonText, Constants.COLOR_DANGER)
    return
  end

  local playerIndex = self:getMyPlayerIndex() or 0
  local stoneId = string.format("p%d_s%d", playerIndex, #self._myStoneList + 1)
  self._myStoneList[#self._myStoneList + 1] = {
    id = stoneId,
    x = canonicalX,
    y = canonicalY
  }
  self:setStatus(string.format("배치 진행: %d/%d", #self._myStoneList, Constants.STONE_COUNT_PER_PLAYER), Constants.COLOR_TEXT_SUB)
end

function MatchScene:submitPlacement()
  if not self:isPlacementPhase() then
    return
  end
  if self._isPlacementSubmitted or self._isSubmitPending then
    return
  end
  if #self._myStoneList ~= Constants.STONE_COUNT_PER_PLAYER then
    self:setStatus("7개를 모두 배치해야 제출할 수 있습니다.", Constants.COLOR_DANGER)
    return
  end

  self._app:sendWsEnvelope("client.match.placement.submit", {
    stones = cloneStoneList(self._myStoneList)
  })
  self._isSubmitPending = true
  self:setStatus("배치 제출 완료, 상대를 기다리는 중...", Constants.COLOR_TEXT_SUB)
end

function MatchScene:rebuildCardOptionButtons()
  self._cardOptionButtonList = {}

  local rect = getCardSelectPanelRect(self._boardX, self._boardY)
  local panelX = rect.x
  local panelY = rect.y
  local panelW = rect.w
  local panelH = rect.h

  for index, cardId in ipairs(self._myDealtCardList) do
    local button = Button.new({
      x = panelX + 36,
      y = panelY + 122 + (index - 1) * 58,
      w = panelW - 72,
      h = 44,
      label = getCardLabel(cardId),
      onClick = function()
        self:toggleCardSelection(cardId)
      end
    })
    self._cardOptionButtonList[#self._cardOptionButtonList + 1] = {
      cardId = cardId,
      button = button
    }
  end

  self._cardConfirmButton.x = panelX + (panelW - self._cardConfirmButton.w) * 0.5
  self._cardConfirmButton.y = panelY + panelH - 108
end

function MatchScene:toggleCardSelection(cardId)
  if not self:isCardSelectPhase() then
    return
  end
  if self._isMyCardLocked or self._isCardPickPending then
    return
  end

  if removeString(self._selectedCardList, cardId) then
    return
  end

  if #self._selectedCardList >= self._myPickCount then
    self:setStatus(string.format("최대 %d장까지만 선택할 수 있습니다.", self._myPickCount), Constants.COLOR_DANGER)
    return
  end

  self._selectedCardList[#self._selectedCardList + 1] = cardId
end

function MatchScene:submitCardPick()
  if not self:isCardSelectPhase() then
    return
  end
  if self._isMyCardLocked or self._isCardPickPending then
    return
  end

  if #self._selectedCardList ~= self._myPickCount then
    self:setStatus(string.format("%d장을 선택 후 확정하세요.", self._myPickCount), Constants.COLOR_DANGER)
    return
  end

  self._app:sendWsEnvelope("client.match.cards.pick", {
    picks = cloneStringList(self._selectedCardList)
  })
  self._isCardPickPending = true
  self:setStatus("카드 선택 확정 요청 전송...", Constants.COLOR_TEXT_SUB)
end

function MatchScene:getPlayingCardPanelRect()
  local panelW = 300
  local panelH = 140
  return {
    x = self._boardX - panelW - 18,
    y = self._boardY + 12,
    w = panelW,
    h = panelH
  }
end

function MatchScene:getResultPanelRect()
  local panelW = 460
  local panelH = 280
  return {
    x = (Constants.BASE_WORLD_W - panelW) * 0.5,
    y = (Constants.BASE_WORLD_H - panelH) * 0.5,
    w = panelW,
    h = panelH
  }
end

function MatchScene:canUseCardInTurn(cardId)
  if not self:isPlayingPhase() then
    return false
  end
  if not self:isMyTurn() then
    return false
  end
  if self._isCardUsePending or self._isPlayingAwaitingSnapshot then
    return false
  end
  if self._hasUsedCardThisTurn then
    return false
  end
  if self._playingShotUsed > 0 then
    return false
  end
  if self._pendingCardTargetId then
    return false
  end
  return cardId == "agile" or cardId == "reinforcement" or cardId == "rockfall" or cardId == "invincible" or cardId == "shockwave"
end

function MatchScene:rebuildPlayingCardButtons()
  self._playingCardButtonList = {}
  local rect = self:getPlayingCardPanelRect()
  for index, cardId in ipairs(self._myPickedCardList) do
    local button = Button.new({
      x = rect.x + 12,
      y = rect.y + 34 + (index - 1) * 40,
      w = rect.w - 24,
      h = 34,
      label = getCardLabel(cardId),
      onClick = function()
        self:requestTurnCardUse(cardId)
      end
    })
    self._playingCardButtonList[#self._playingCardButtonList + 1] = {
      cardId = cardId,
      button = button
    }
  end
end

function MatchScene:requestTurnCardUse(cardId)
  if not self:canUseCardInTurn(cardId) then
    self:setStatus("지금은 카드를 사용할 수 없습니다.", Constants.COLOR_DANGER)
    return
  end

  if cardId == "rockfall" or cardId == "reinforcement" then
    self._pendingCardTargetId = cardId
    self._isAimDragging = false
    self._aimStoneId = nil
    if cardId == "rockfall" then
      self:setStatus("낙석 대상 선택: 보드 위를 클릭해 장애물을 배치하세요. ESC/우클릭 취소", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("신병 대상 선택: 보드 위를 클릭해 알을 배치하세요. ESC/우클릭 취소", Constants.COLOR_TEXT_SUB)
    end
    return
  end

  local payload = {
    turnIndex = self._playingTurnIndex,
    cardId = cardId
  }

  self._app:sendWsEnvelope("client.match.turn.cardUse", payload)
  self._isCardUsePending = true
  self:setStatus("카드 사용 요청 전송...", Constants.COLOR_TEXT_SUB)
end

function MatchScene:cancelPendingCardTarget()
  if not self._pendingCardTargetId then
    return
  end
  self._pendingCardTargetId = nil
  self:setStatus("카드 대상 선택을 취소했습니다.", Constants.COLOR_TEXT_SUB)
end

function MatchScene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
  local width = Constants.ROCK_OBSTACLE_WIDTH
  local height = Constants.ROCK_OBSTACLE_HEIGHT
  local halfW = width * 0.5
  local halfH = height * 0.5
  local margin = Constants.ROCK_OBSTACLE_MARGIN

  if canonicalX - halfW < margin or canonicalX + halfW > Constants.BOARD_W - margin then
    return false, "장애물은 보드 경계에서 5px 안쪽에만 배치할 수 있습니다."
  end
  if canonicalY - halfH < margin or canonicalY + halfH > Constants.BOARD_H - margin then
    return false, "장애물은 보드 경계에서 5px 안쪽에만 배치할 수 있습니다."
  end

  local previewObstacle = {
    x = canonicalX,
    y = canonicalY,
    width = width,
    height = height
  }

  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and intersectsStoneAndObstacle(stone.x, stone.y, previewObstacle) then
      return false, "장애물은 알과 겹칠 수 없습니다."
    end
  end

  for _, obstacle in ipairs(self._obstacleList) do
    if intersectsObstacleAndObstacle(previewObstacle, obstacle) then
      return false, "기존 장애물과 겹칠 수 없습니다."
    end
  end

  return true, nil
end

function MatchScene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  if canonicalX < minX or canonicalX > maxX or canonicalY < minY or canonicalY > maxY then
    return false, "신병 알은 보드 안쪽 경계에서만 배치할 수 있습니다."
  end

  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false then
      local dx = stone.x - canonicalX
      local dy = stone.y - canonicalY
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < Constants.MIN_PLACE_DISTANCE then
        return false, "기존 알과 너무 가깝습니다."
      end
    end
  end

  local previewStone = {
    x = canonicalX,
    y = canonicalY
  }
  for _, obstacle in ipairs(self._obstacleList) do
    if intersectsStoneAndObstacle(previewStone.x, previewStone.y, obstacle) then
      return false, "장애물과 겹치는 위치에는 배치할 수 없습니다."
    end
  end

  return true, nil
end

function MatchScene:commitPendingCardTargetByWorld(worldX, worldY)
  if self._pendingCardTargetId ~= "rockfall" and self._pendingCardTargetId ~= "reinforcement" then
    return false
  end
  local pendingCardId = self._pendingCardTargetId
  if not self:isMyTurn() or self._hasUsedCardThisTurn or self._playingShotUsed > 0 then
    self._pendingCardTargetId = nil
    self:setStatus("지금은 카드를 사용할 수 없습니다.", Constants.COLOR_DANGER)
    return true
  end

  local boardLocalX, boardLocalY = self:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    if pendingCardId == "reinforcement" then
      self:setStatus("보드 안을 클릭해 신병 위치를 선택하세요.", Constants.COLOR_DANGER)
    else
      self:setStatus("보드 안을 클릭해 낙석 위치를 선택하세요.", Constants.COLOR_DANGER)
    end
    return true
  end

  local canonicalX, canonicalY = self:localToCanonical(boardLocalX, boardLocalY)
  local canPlace, reason
  if pendingCardId == "rockfall" then
    canPlace, reason = self:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
  else
    canPlace, reason = self:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
  end
  if not canPlace then
    self:setStatus(reason or "해당 위치에는 배치할 수 없습니다.", Constants.COLOR_DANGER)
    return true
  end

  self._app:sendWsEnvelope("client.match.turn.cardUse", {
    turnIndex = self._playingTurnIndex,
    cardId = pendingCardId,
    target = {
      x = canonicalX,
      y = canonicalY
    }
  })
  self._pendingCardTargetId = nil
  self._isCardUsePending = true
  if pendingCardId == "rockfall" then
    self:setStatus("낙석 카드 사용 요청 전송...", Constants.COLOR_TEXT_SUB)
  else
    self:setStatus("신병 카드 사용 요청 전송...", Constants.COLOR_TEXT_SUB)
  end
  return true
end

function MatchScene:requestSurrender()
  if not self:isPlayingPhase() then
    self:setStatus("지금은 기권할 수 없습니다.", Constants.COLOR_DANGER)
    return
  end
  if self._isSurrenderPending then
    return
  end
  self._pendingCardTargetId = nil
  self._isAimDragging = false
  self._aimStoneId = nil
  self._app:sendWsEnvelope("client.match.surrender", {})
  self._isSurrenderPending = true
  self:setStatus("기권 요청 전송...", Constants.COLOR_DANGER)
end

function MatchScene:requestResultVote(action)
  if self._roomState.phase ~= Constants.PHASE_RESULT then
    self:setStatus("지금은 결과 투표를 할 수 없습니다.", Constants.COLOR_DANGER)
    return
  end
  if action ~= "rematch" and action ~= "to_lobby" then
    return
  end
  if self._isResultVotePending then
    return
  end

  self._app:sendWsEnvelope("client.match.rematch.vote", {
    action = action
  })
  self._isResultVotePending = true
  if action == "rematch" then
    self:setStatus("재대결 투표 전송...", Constants.COLOR_TEXT_SUB)
  else
    self:setStatus("로비 복귀 투표 전송...", Constants.COLOR_TEXT_SUB)
  end
end

function MatchScene:beginAimDrag(worldX, worldY)
  if not self:isShotInputEnabled() then
    return
  end

  local stone = self:findAimStoneAt(worldX, worldY)
  if not stone then
    return
  end

  self._isAimDragging = true
  self._aimStoneId = stone.id
  self:setStatus("조준 중... 마우스를 놓아 발사, ESC/우클릭으로 취소", Constants.COLOR_TEXT_SUB)
end

function MatchScene:cancelAimDrag()
  if not self._isAimDragging then
    return
  end
  self._isAimDragging = false
  self._aimStoneId = nil
  self:setStatus("발사를 취소했습니다.", Constants.COLOR_TEXT_SUB)
end

function MatchScene:commitAimDrag(worldX, worldY)
  if not self._isAimDragging then
    return
  end
  if not self:isShotInputEnabled() then
    self:cancelAimDrag()
    return
  end

  local stone = self:getAliveStoneById(self._aimStoneId)
  self._isAimDragging = false
  self._aimStoneId = nil
  if not stone then
    self:setStatus("발사할 알을 찾지 못했습니다.", Constants.COLOR_DANGER)
    return
  end

  local stoneLocalX, stoneLocalY = self:canonicalToLocal(stone.x, stone.y)
  local mouseLocalX, mouseLocalY = self:toBoardLocalNoClamp(worldX, worldY)

  local dirLocalX = stoneLocalX - mouseLocalX
  local dirLocalY = stoneLocalY - mouseLocalY
  local dragLength = math.sqrt(dirLocalX * dirLocalX + dirLocalY * dirLocalY)
  if dragLength < 1 then
    self:setStatus("드래그 거리가 너무 짧습니다.", Constants.COLOR_DANGER)
    return
  end

  local dirCanonicalX = dirLocalX
  local dirCanonicalY = dirLocalY
  if self:getMyRole() == "guest" then
    dirCanonicalY = -dirCanonicalY
  end

  local canonicalLen = math.sqrt(dirCanonicalX * dirCanonicalX + dirCanonicalY * dirCanonicalY)
  if canonicalLen <= 0 then
    self:setStatus("발사 방향 계산 실패", Constants.COLOR_DANGER)
    return
  end

  local power = math.min(Constants.MAX_SHOT_POWER, dragLength * Constants.POWER_PER_PIXEL)
  self._app:sendWsEnvelope("client.match.turn.shot", {
    turnIndex = self._playingTurnIndex,
    stoneId = stone.id,
    dirX = dirCanonicalX / canonicalLen,
    dirY = dirCanonicalY / canonicalLen,
    power = power
  })
  self._isTurnShotPending = true
  self:setStatus("발사 요청 전송...", Constants.COLOR_TEXT_SUB)
end

function MatchScene:sendHostSnapshotIfNeeded(turnIndex, reason)
  local session = self._app:getSession()
  if not session or session.role ~= "host" then
    return
  end
  if not turnIndex or turnIndex ~= self._playingTurnIndex then
    return
  end
  if self._lastAutoSnapshotTurnIndex == turnIndex then
    return
  end
  if self._isShotSimulating then
    self._shouldSendSnapshotAfterSim = true
    return
  end

  self._lastAutoSnapshotTurnIndex = turnIndex
  self._app:sendWsEnvelope("client.match.turn.snapshot", {
    turnIndex = turnIndex,
    stones = clonePlayingStoneList(self._playingStoneList)
  })
  self:setStatus("턴 스냅샷 제출 (" .. tostring(reason or "auto") .. ")", Constants.COLOR_TEXT_SUB)
end

function MatchScene:applyRoomState(payload)
  if payload.phase == Constants.PHASE_WAITING then
    self._app:goWaitingRoom({
      roomState = payload,
      statusText = "재대결 대기 상태로 복귀했습니다.",
      statusColor = Constants.COLOR_TEXT_SUB
    })
    return
  end

  self._roomState = payload

  if type(payload.result) == "table" then
    self._myResultVote = payload.result.myVote
    self._opponentResultVote = payload.result.opponentVote
    if self._myResultVote then
      self._isResultVotePending = false
    end
  else
    self._myResultVote = nil
    self._opponentResultVote = nil
  end

  local placement = payload.match and payload.match.placement or nil
  if type(placement) == "table" then
    if type(placement.mySubmitted) == "boolean" then
      self._isPlacementSubmitted = placement.mySubmitted
      if self._isPlacementSubmitted then
        self._isSubmitPending = false
      end
    end

    if type(placement.myStones) == "table" then
      self._myStoneList = cloneStoneList(placement.myStones)
    end

    local revealStones = placement.revealStones
    if type(revealStones) == "table" and type(revealStones.host) == "table" and type(revealStones.guest) == "table" then
      self._revealStoneMap = {
        host = cloneStoneList(revealStones.host),
        guest = cloneStoneList(revealStones.guest)
      }
    end
  end

  local cardSelect = payload.match and payload.match.cardSelect or nil
  if type(cardSelect) == "table" then
    if type(cardSelect.myDealtCards) == "table" then
      self._myDealtCardList = cloneStringList(cardSelect.myDealtCards)
    end
    if type(cardSelect.myPickedCards) == "table" then
      self._myPickedCardList = cloneStringList(cardSelect.myPickedCards)
    end
    if type(cardSelect.myPickCount) == "number" then
      self._myPickCount = cardSelect.myPickCount
    end
    if type(cardSelect.myLocked) == "boolean" then
      self._isMyCardLocked = cardSelect.myLocked
      if self._isMyCardLocked then
        self._selectedCardList = cloneStringList(self._myPickedCardList)
        self._isCardPickPending = false
      end
    end
    if type(cardSelect.opponentLocked) == "boolean" then
      self._isOpponentCardLocked = cardSelect.opponentLocked
    end
    if type(cardSelect.selectEndsAtMs) == "number" then
      self._cardSelectEndsAtMs = cardSelect.selectEndsAtMs
    else
      self._cardSelectEndsAtMs = nil
    end

    if not self._isMyCardLocked then
      local filtered = {}
      for _, cardId in ipairs(self._selectedCardList) do
        if containsString(self._myDealtCardList, cardId) then
          filtered[#filtered + 1] = cardId
        end
      end
      self._selectedCardList = filtered
      while #self._selectedCardList > self._myPickCount do
        table.remove(self._selectedCardList)
      end
    end

    self:rebuildCardOptionButtons()
  end

  local playing = payload.match and payload.match.playing or nil
  if type(playing) == "table" then
    local turnIndexFromPayload = type(playing.turnIndex) == "number" and playing.turnIndex or nil
    local canOverwriteStoneList = true
    if self._isShotSimulating and turnIndexFromPayload and turnIndexFromPayload == self._playingTurnIndex then
      canOverwriteStoneList = false
    end

    if type(playing.turnIndex) == "number" then
      self._playingTurnIndex = playing.turnIndex
    end
    if type(playing.activePlayerIndex) == "number" then
      self._activePlayerIndex = playing.activePlayerIndex
    end
    if type(playing.turnEndsAtMs) == "number" then
      self._turnEndsAtMs = playing.turnEndsAtMs
    else
      self._turnEndsAtMs = nil
    end
    if type(playing.shotBudget) == "number" then
      self._playingShotBudget = playing.shotBudget
    end
    if type(playing.shotUsed) == "number" then
      self._playingShotUsed = playing.shotUsed
      if playing.shotUsed <= 0 then
        self._shockwaveSourceStoneId = nil
      end
    end
    if type(playing.hasCardUsedThisTurn) == "boolean" then
      self._hasUsedCardThisTurn = playing.hasCardUsedThisTurn
      if playing.hasCardUsedThisTurn then
        self._isCardUsePending = false
      end
    end
    if type(playing.lockedStoneIds) == "table" then
      self._lockedStoneIdSet = listToSet(playing.lockedStoneIds)
    else
      self._lockedStoneIdSet = {}
    end
    if type(playing.obstacles) == "table" then
      self._obstacleList = cloneObstacleList(playing.obstacles)
    else
      self._obstacleList = {}
    end
    self._invincibleTurnByPlayer = normalizeInvincibleTurnByPlayer(playing.invincibleTurnByPlayer)
    if playing.shockwaveOwnerPlayerIndex == 1 or playing.shockwaveOwnerPlayerIndex == 2 then
      self._shockwaveOwnerPlayerIndex = playing.shockwaveOwnerPlayerIndex
    else
      self._shockwaveOwnerPlayerIndex = nil
    end
    if type(playing.shotCommitted) == "boolean" then
      self._isPlayingShotCommitted = playing.shotCommitted
      if playing.shotCommitted then
        self._isTurnShotPending = false
      end
    end
    if type(playing.awaitingSnapshot) == "boolean" then
      self._isPlayingAwaitingSnapshot = playing.awaitingSnapshot
      if playing.awaitingSnapshot then
        self._isTurnShotPending = false
        self._isAimDragging = false
        self._aimStoneId = nil
      end
    end
    if canOverwriteStoneList and type(playing.stones) == "table" then
      self._playingStoneList = clonePlayingStoneList(playing.stones)
      self:syncStoneVelocityMap()
    end
    if self._pendingCardTargetId and (not self:isMyTurn() or self._hasUsedCardThisTurn or self._playingShotUsed > 0 or self._isCardUsePending) then
      self._pendingCardTargetId = nil
    end
    self:rebuildPlayingCardButtons()
  end

  if payload.phase ~= Constants.PHASE_PLAYING then
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self:resetStoneVelocities()
    self._shockwaveOwnerPlayerIndex = nil
    self._shockwaveSourceStoneId = nil
    self._lockedStoneIdSet = {}
    self._pendingCardTargetId = nil
    self._isSurrenderPending = false
    if self._effectManager then
      self._effectManager:clear()
    end
  end
  if payload.phase ~= Constants.PHASE_RESULT then
    self._isResultVotePending = false
    self._myResultVote = nil
    self._opponentResultVote = nil
  end

  if payload.phase == Constants.PHASE_PLACEMENT_PRIVATE then
    self:setStatus("배치 단계: 클릭으로 7개를 배치한 뒤 제출하세요.", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLACEMENT_REVEAL then
    self:setStatus("배치 공개 중...", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_CARD_SELECT then
    self:setStatus("카드 선택 단계입니다.", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLAYING then
    if self._pendingCardTargetId then
      self:setStatus("낙석 대상 선택: 보드 위를 클릭해 장애물을 배치하세요. ESC/우클릭 취소", Constants.COLOR_TEXT_SUB)
    elseif self:isMyTurn() then
      self:setStatus("내 턴입니다. 알을 드래그해 발사하세요.", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("상대 턴 진행 중...", Constants.COLOR_TEXT_SUB)
    end
    if self._isPlayingAwaitingSnapshot then
      self:sendHostSnapshotIfNeeded(self._playingTurnIndex, "state_sync")
    end
  elseif payload.phase == Constants.PHASE_RESULT then
    local myVoteLabelMap = {
      rematch = "재대결",
      to_lobby = "로비"
    }
    local myVoteLabel = self._myResultVote and (myVoteLabelMap[self._myResultVote] or tostring(self._myResultVote)) or "없음"
    self:setStatus("결과 단계: 후속 동작 투표 (내 투표: " .. myVoteLabel .. ")", Constants.COLOR_DANGER)
  end
end

function MatchScene:update(dt)
  if self._effectManager then
    self._effectManager:update(dt)
  end
  if self:isPlayingPhase() then
    self:updateShotSimulation(dt)
  end
end

function MatchScene:drawBoardFrame()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  local centerWorldY = self._boardY + Constants.BOARD_H * 0.5
  local stripY = centerWorldY - Constants.NO_PLACE_BUFFER
  local stripH = Constants.NO_PLACE_BUFFER * 2

  if self._roomState.phase ~= Constants.PHASE_PLAYING and self._roomState.phase ~= Constants.PHASE_RESULT then
    love.graphics.setColor(0.65, 0.18, 0.22, 0.20)
    love.graphics.rectangle("fill", self._boardX, stripY, Constants.BOARD_W, stripH)
  end

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.line(self._boardX, centerWorldY, self._boardX + Constants.BOARD_W, centerWorldY)

  if self:isPlacementPhase() then
    love.graphics.setColor(0.20, 0.45, 0.27, 0.16)
    love.graphics.rectangle(
      "fill",
      self._boardX,
      self._boardY + Constants.BOARD_H * 0.5 + Constants.NO_PLACE_BUFFER,
      Constants.BOARD_W,
      Constants.BOARD_H * 0.5 - Constants.NO_PLACE_BUFFER
    )
  end
end

function MatchScene:drawStoneList(stoneList, color)
  love.graphics.setColor(color)
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false then
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      love.graphics.circle("fill", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
    end
  end

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false then
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      love.graphics.circle("line", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
    end
  end
end

function MatchScene:drawObstacleList(obstacleList)
  love.graphics.setColor(0.44, 0.42, 0.40, 1.0)
  for _, obstacle in ipairs(obstacleList or {}) do
    local localX, localY = self:canonicalToLocal(obstacle.x, obstacle.y)
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.rectangle("fill", self._boardX + localX - width * 0.5, self._boardY + localY - height * 0.5, width, height, 6, 6)
  end

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  for _, obstacle in ipairs(obstacleList or {}) do
    local localX, localY = self:canonicalToLocal(obstacle.x, obstacle.y)
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.rectangle("line", self._boardX + localX - width * 0.5, self._boardY + localY - height * 0.5, width, height, 6, 6)
  end
end

function MatchScene:drawPlacementInfo()
  local placement = self._roomState.match and self._roomState.match.placement or nil
  local mySubmitted = placement and placement.mySubmitted and "완료" or "진행중"
  local opponentSubmitted = placement and placement.opponentSubmitted and "완료" or "대기중"
  local timerText = ""
  local phaseEndsAtMs = self._roomState.timers and self._roomState.timers.phaseEndsAtMs or nil
  if phaseEndsAtMs and self._roomState.phase == Constants.PHASE_PLACEMENT_REVEAL then
    local remainSec = math.max(0, math.ceil((phaseEndsAtMs - nowEpochMs()) / 1000))
    timerText = string.format(" / 공개 남은 시간: %ds", remainSec)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(
    string.format("내 배치: %s (%d/%d) | 상대 배치: %s%s", mySubmitted, #self._myStoneList, Constants.STONE_COUNT_PER_PLAYER, opponentSubmitted, timerText),
    0,
    636,
    Constants.BASE_WORLD_W,
    "center"
  )
end

function MatchScene:drawPlayingInfo()
  local remainSec = 0
  if self._turnEndsAtMs then
    remainSec = math.max(0, math.ceil((self._turnEndsAtMs - nowEpochMs()) / 1000))
  end

  local turnOwnerText = self._activePlayerIndex == self:getMyPlayerIndex() and "내 턴" or "상대 턴"
  local stateText = "조준 가능"
  if self._isPlayingAwaitingSnapshot then
    stateText = "스냅샷 대기"
  elseif self._pendingCardTargetId then
    stateText = "카드 대상 선택 중"
  elseif self._isCardUsePending then
    stateText = "카드 요청 전송 중"
  elseif self._isPlayingShotCommitted then
    stateText = "발사 완료"
    if self._isShotSimulating then
      stateText = "물리 시뮬레이션 중"
    end
  elseif self._isTurnShotPending then
    stateText = "발사 요청 전송 중"
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(
    string.format("턴 %d | %s | 남은 시간: %ds | 샷 %d/%d | 카드사용:%s | 상태: %s", self._playingTurnIndex, turnOwnerText, remainSec, self._playingShotUsed, self._playingShotBudget, self._hasUsedCardThisTurn and "Y" or "N", stateText),
    0,
    636,
    Constants.BASE_WORLD_W,
    "center"
  )
end

function MatchScene:drawPlayingCardPanel(mouseX, mouseY)
  if not self:isPlayingPhase() then
    return
  end

  local rect = self:getPlayingCardPanelRect()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("TURN 카드", rect.x, rect.y + 8, rect.w, "center")

  for _, entry in ipairs(self._playingCardButtonList) do
    local canUse = self:canUseCardInTurn(entry.cardId)
    entry.button.isEnabled = canUse
    entry.button.color = canUse and Constants.COLOR_BUTTON or Constants.COLOR_BUTTON_DISABLED
    entry.button:draw(mouseX, mouseY)
  end

  if self._pendingCardTargetId then
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    local hintText = self._pendingCardTargetId == "reinforcement" and "신병 위치를 보드에서 클릭" or "낙석 위치를 보드에서 클릭"
    love.graphics.printf(hintText, rect.x, rect.y + rect.h - 18, rect.w, "center")
  end
end

function MatchScene:drawAimGuide(mouseX, mouseY)
  if not self._isAimDragging then
    return
  end
  local stone = self:getAliveStoneById(self._aimStoneId)
  if not stone then
    return
  end

  local localX, localY = self:canonicalToLocal(stone.x, stone.y)
  local stoneWorldX = self._boardX + localX
  local stoneWorldY = self._boardY + localY
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

function MatchScene:drawPendingCardPreview(mouseX, mouseY)
  if self._pendingCardTargetId ~= "rockfall" and self._pendingCardTargetId ~= "reinforcement" then
    return
  end
  if not self:isPlayingPhase() or not self:isMyTurn() then
    return
  end

  local boardLocalX, boardLocalY = self:toBoardLocal(mouseX, mouseY)
  if not boardLocalX then
    return
  end

  local canonicalX, canonicalY = self:localToCanonical(boardLocalX, boardLocalY)
  local canPlace = false
  if self._pendingCardTargetId == "rockfall" then
    canPlace = self:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
    local width = Constants.ROCK_OBSTACLE_WIDTH
    local height = Constants.ROCK_OBSTACLE_HEIGHT
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", mouseX - width * 0.5, mouseY - height * 0.5, width, height, 6, 6)
  else
    canPlace = self:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
    local radius = Constants.STONE_RADIUS
    local color = canPlace and { 0.36, 0.90, 0.50, 0.35 } or { 0.90, 0.30, 0.30, 0.35 }
    local borderColor = canPlace and { 0.36, 0.90, 0.50, 1.0 } or { 0.90, 0.30, 0.30, 1.0 }
    love.graphics.setColor(color)
    love.graphics.circle("fill", mouseX, mouseY, radius)
    love.graphics.setColor(borderColor)
    love.graphics.circle("line", mouseX, mouseY, radius)
  end
end

function MatchScene:drawCardSelectPanel(mouseX, mouseY)
  local rect = getCardSelectPanelRect(self._boardX, self._boardY)
  local panelX = rect.x
  local panelY = rect.y
  local panelW = rect.w
  local panelH = rect.h

  love.graphics.setColor(Constants.COLOR_OVERLAY_DIM)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 10, 10)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 10, 10)

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("카드 선택", panelX, panelY + 22, panelW, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)

  local remainSec = 0
  if self._cardSelectEndsAtMs then
    remainSec = math.max(0, math.ceil((self._cardSelectEndsAtMs - nowEpochMs()) / 1000))
  end

  love.graphics.printf(
    string.format("선택 수: %d장 / 선택됨: %d장 / 남은 시간: %ds", self._myPickCount, #self._selectedCardList, remainSec),
    panelX,
    panelY + 56,
    panelW,
    "center"
  )

  for _, entry in ipairs(self._cardOptionButtonList) do
    local isSelected = containsString(self._selectedCardList, entry.cardId)
    entry.button.color = isSelected and Constants.COLOR_BUTTON_SELECTED_ALT or Constants.COLOR_BUTTON
    entry.button.isEnabled = not self._isMyCardLocked and not self._isCardPickPending
    entry.button:draw(mouseX, mouseY)
  end

  self._cardConfirmButton.isEnabled = (not self._isMyCardLocked) and (not self._isCardPickPending) and (#self._selectedCardList == self._myPickCount)
  self._cardConfirmButton:draw(mouseX, mouseY)

  local lockText = self._isMyCardLocked and "내 선택 확정 완료" or "내 선택 대기중"
  local opponentText = self._isOpponentCardLocked and "상대 확정 완료" or "상대 선택 중"
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(lockText .. " | " .. opponentText, panelX, panelY + panelH - 40, panelW, "center")
end

function MatchScene:drawResultPanel(mouseX, mouseY)
  local rect = self:getResultPanelRect()
  local payload = self._roomState.result or {}
  local winnerPlayerIndex = payload.winnerPlayerIndex
  local reason = payload.reason or "unknown"

  local resultTitle = "무승부"
  if winnerPlayerIndex == self:getMyPlayerIndex() then
    resultTitle = "승리"
  elseif winnerPlayerIndex == nil then
    resultTitle = "무승부"
  else
    resultTitle = "패배"
  end

  local reasonLabelMap = {
    stone_zero = "상대 알 전멸",
    draw = "무승부",
    player_left = "상대 이탈",
    surrender = "기권"
  }
  local reasonLabel = reasonLabelMap[reason] or tostring(reason)
  local voteLabelMap = {
    rematch = "재대결",
    to_lobby = "로비"
  }
  local myVoteText = self._myResultVote and (voteLabelMap[self._myResultVote] or tostring(self._myResultVote)) or "없음"
  local opponentVoteText = self._opponentResultVote and (voteLabelMap[self._opponentResultVote] or tostring(self._opponentResultVote)) or "없음"

  love.graphics.setColor(Constants.COLOR_OVERLAY_DIM)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 10, 10)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 10, 10)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("RESULT - " .. resultTitle, rect.x, rect.y + 18, rect.w, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("사유: " .. reasonLabel, rect.x, rect.y + 76, rect.w, "center")
  love.graphics.printf("내 투표: " .. myVoteText .. " | 상대 투표: " .. opponentVoteText, rect.x, rect.y + 112, rect.w, "center")

  local buttonY = rect.y + rect.h - 82
  self._resultRematchButton.x = rect.x + 30
  self._resultRematchButton.y = buttonY
  self._resultLobbyButton.x = rect.x + rect.w - self._resultLobbyButton.w - 30
  self._resultLobbyButton.y = buttonY

  self._resultRematchButton.isEnabled = not self._isResultVotePending
  self._resultLobbyButton.isEnabled = not self._isResultVotePending
  self._resultRematchButton.color = self._myResultVote == "rematch" and Constants.COLOR_BUTTON_SELECTED or Constants.COLOR_BUTTON
  self._resultLobbyButton.color = self._myResultVote == "to_lobby" and { 0.75, 0.28, 0.30, 1.0 } or Constants.COLOR_DANGER

  self._resultRematchButton:draw(mouseX, mouseY)
  self._resultLobbyButton:draw(mouseX, mouseY)
end

function MatchScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("Match Phase", 0, 16, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("현재 Phase: " .. tostring(self._roomState.phase), 0, 48, Constants.BASE_WORLD_W, "center")

  self:drawBoardFrame()

  if self._roomState.phase == Constants.PHASE_PLAYING or self._roomState.phase == Constants.PHASE_RESULT then
    local hostStoneList = {}
    local guestStoneList = {}
    for _, stone in ipairs(self._playingStoneList) do
      if stone.ownerPlayerIndex == 1 then
        hostStoneList[#hostStoneList + 1] = stone
      else
        guestStoneList[#guestStoneList + 1] = stone
      end
    end
    self:drawObstacleList(self._obstacleList)
    self:drawStoneList(hostStoneList, Constants.COLOR_STONE_HOST)
    self:drawStoneList(guestStoneList, Constants.COLOR_STONE_GUEST)
  elseif self:isRevealVisiblePhase() and self._revealStoneMap then
    self:drawStoneList(self._revealStoneMap.host, Constants.COLOR_STONE_HOST)
    self:drawStoneList(self._revealStoneMap.guest, Constants.COLOR_STONE_GUEST)
  else
    local role = self:getMyRole()
    local color = role == "guest" and Constants.COLOR_STONE_GUEST or Constants.COLOR_STONE_HOST
    self:drawStoneList(self._myStoneList, color)
  end

  self:drawPendingCardPreview(mouseX, mouseY)
  self:drawAimGuide(mouseX, mouseY)
  if self._effectManager then
    self._effectManager:draw(self._boardX, self._boardY, function(canonicalX, canonicalY)
      return self:canonicalToLocal(canonicalX, canonicalY)
    end)
  end

  if self:isPlacementPhase() then
    local canSubmit = (not self._isPlacementSubmitted) and (not self._isSubmitPending) and #self._myStoneList == Constants.STONE_COUNT_PER_PLAYER
    self._submitButton.isEnabled = canSubmit
    self._submitButton:draw(mouseX, mouseY)
  end

  if self._roomState.phase == Constants.PHASE_CARD_SELECT then
    self:drawCardSelectPanel(mouseX, mouseY)
  elseif self._roomState.phase == Constants.PHASE_PLAYING then
    self:drawPlayingInfo()
    self:drawPlayingCardPanel(mouseX, mouseY)
    self._surrenderButton.isEnabled = not self._isSurrenderPending
    self._surrenderButton:draw(mouseX, mouseY)
  elseif self._roomState.phase == Constants.PHASE_RESULT then
    self:drawResultPanel(mouseX, mouseY)
  else
    self:drawPlacementInfo()
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function MatchScene:mousepressed(mouseX, mouseY, button)
  if self:isPlayingPhase() and button == 2 then
    if self._pendingCardTargetId then
      self:cancelPendingCardTarget()
    else
      self:cancelAimDrag()
    end
    return
  end

  if button ~= 1 then
    return
  end

  if self:isCardSelectPhase() then
    for _, entry in ipairs(self._cardOptionButtonList) do
      if entry.button:isHovered(mouseX, mouseY) and entry.button.isEnabled then
        entry.button:onClick()
        return
      end
    end
    if self._cardConfirmButton:isHovered(mouseX, mouseY) and self._cardConfirmButton.isEnabled then
      self._cardConfirmButton:onClick()
      return
    end
    return
  end

  if self:isPlayingPhase() then
    if self._surrenderButton:isHovered(mouseX, mouseY) and self._surrenderButton.isEnabled then
      self._surrenderButton:onClick()
      return
    end
    if self._pendingCardTargetId then
      self:commitPendingCardTargetByWorld(mouseX, mouseY)
      return
    end
    for _, entry in ipairs(self._playingCardButtonList) do
      if entry.button:isHovered(mouseX, mouseY) and entry.button.isEnabled then
        entry.button:onClick()
        return
      end
    end
    self:beginAimDrag(mouseX, mouseY)
    return
  end

  if self._roomState.phase == Constants.PHASE_RESULT then
    if self._resultRematchButton:isHovered(mouseX, mouseY) and self._resultRematchButton.isEnabled then
      self._resultRematchButton:onClick()
      return
    end
    if self._resultLobbyButton:isHovered(mouseX, mouseY) and self._resultLobbyButton.isEnabled then
      self._resultLobbyButton:onClick()
      return
    end
    return
  end

  if self._submitButton:isHovered(mouseX, mouseY) and self._submitButton.isEnabled then
    self._submitButton:onClick()
    return
  end

  if self:isPlacementPhase() then
    self:addPlacementByWorld(mouseX, mouseY)
  end
end

function MatchScene:mousereleased(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self:isPlayingPhase() and self._isAimDragging then
    self:commitAimDrag(mouseX, mouseY)
  end
end

function MatchScene:textinput(_text)
end

function MatchScene:textedited(_text, _start, _length)
end

function MatchScene:keypressed(key)
  if key == "escape" and self._pendingCardTargetId then
    self:cancelPendingCardTarget()
    return
  end
  if key == "escape" and self._isAimDragging then
    self:cancelAimDrag()
    return
  end
  if key == "escape" and self._roomState.phase == Constants.PHASE_RESULT then
    self:requestResultVote("to_lobby")
    return
  end
end

function MatchScene:onWsEnvelope(envelope)
  if envelope.type == "room.state" and type(envelope.payload) == "table" then
    self:applyRoomState(envelope.payload)
    return
  end

  if envelope.type == "match.turnOrder" then
    local payload = envelope.payload or {}
    self:setStatus("턴 순서 결정됨: 선공 P" .. tostring(payload.firstPlayerIndex or "?"), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.phaseChanged" then
    local payload = envelope.payload or {}
    self:setStatus(string.format("Phase 변경: %s -> %s", tostring(payload.from), tostring(payload.to)), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.placement.revealStart" then
    local payload = envelope.payload or {}
    if type(payload.stones) == "table" then
      local hostStones = type(payload.stones.host) == "table" and payload.stones.host or {}
      local guestStones = type(payload.stones.guest) == "table" and payload.stones.guest or {}
      self._revealStoneMap = {
        host = cloneStoneList(hostStones),
        guest = cloneStoneList(guestStones)
      }
    end
    self:setStatus("배치 공개가 시작되었습니다.", Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.cards.dealt" then
    local payload = envelope.payload or {}
    if type(payload.pickCount) == "number" then
      self._myPickCount = payload.pickCount
    end
    if type(payload.dealtCards) == "table" then
      self._myDealtCardList = cloneStringList(payload.dealtCards)
      self:rebuildCardOptionButtons()
    end
    if type(payload.selectEndsAtMs) == "number" then
      self._cardSelectEndsAtMs = payload.selectEndsAtMs
    end
    self:setStatus("카드가 분배되었습니다. 선택 후 확정하세요.", Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.cards.locked" then
    local payload = envelope.payload or {}
    local myPlayerIndex = self:getMyPlayerIndex()
    if payload.playerIndex == myPlayerIndex then
      self._isMyCardLocked = true
      self._isCardPickPending = false
      if type(payload.pickedCards) == "table" then
        self._myPickedCardList = cloneStringList(payload.pickedCards)
        self._selectedCardList = cloneStringList(payload.pickedCards)
        self:rebuildPlayingCardButtons()
      end
      self:setStatus("내 카드 선택이 확정되었습니다.", Constants.COLOR_TEXT_SUB)
    else
      self._isOpponentCardLocked = true
      self:setStatus("상대가 카드 선택을 확정했습니다.", Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.start" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.activePlayerIndex) == "number" then
      self._activePlayerIndex = payload.activePlayerIndex
    end
    if type(payload.turnEndsAtMs) == "number" then
      self._turnEndsAtMs = payload.turnEndsAtMs
    else
      self._turnEndsAtMs = nil
    end
    if type(payload.shotBudget) == "number" then
      self._playingShotBudget = payload.shotBudget
    else
      self._playingShotBudget = 1
    end
    if type(payload.shotUsed) == "number" then
      self._playingShotUsed = payload.shotUsed
    else
      self._playingShotUsed = 0
    end
    self._shockwaveSourceStoneId = nil
    self._shockwaveOwnerPlayerIndex = nil
    if type(payload.hasCardUsedThisTurn) == "boolean" then
      self._hasUsedCardThisTurn = payload.hasCardUsedThisTurn
    else
      self._hasUsedCardThisTurn = false
    end
    self._isPlayingShotCommitted = false
    self._isPlayingAwaitingSnapshot = false
    self._isTurnShotPending = false
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self._isSurrenderPending = false
    self._isAimDragging = false
    self._aimStoneId = nil
    if self._effectManager then
      self._effectManager:clear()
    end
    self._lastAutoSnapshotTurnIndex = nil
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self:resetStoneVelocities()
    self:rebuildPlayingCardButtons()
    if self:isMyTurn() then
      self:setStatus("내 턴 시작. 드래그해서 발사하세요.", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("상대 턴 시작", Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.cardCue" then
    local payload = envelope.payload or {}
    self:setStatus("카드 사용 연출: P" .. tostring(payload.playerIndex or "?") .. " / " .. tostring(getCardLabel(payload.cardId)), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.turn.cardApplied" then
    local payload = envelope.payload or {}
    local myPlayerIndex = self:getMyPlayerIndex()
    if payload.playerIndex == myPlayerIndex then
      self._isCardUsePending = false
      self._hasUsedCardThisTurn = true
      if type(payload.cardId) == "string" then
        removeString(self._myPickedCardList, payload.cardId)
      end
      if type(payload.effect) == "table" and type(payload.effect.shotBudget) == "number" then
        self._playingShotBudget = payload.effect.shotBudget
      end
      if type(payload.effect) == "table" and type(payload.effect.lockedStoneIds) == "table" then
        self._lockedStoneIdSet = listToSet(payload.effect.lockedStoneIds)
      end
      if type(payload.effect) == "table" and type(payload.effect.spawnStone) == "table" then
        self._playingStoneList[#self._playingStoneList + 1] = {
          id = payload.effect.spawnStone.id,
          ownerPlayerIndex = payload.effect.spawnStone.ownerPlayerIndex,
          x = payload.effect.spawnStone.x,
          y = payload.effect.spawnStone.y,
          alive = payload.effect.spawnStone.alive ~= false
        }
      end
      if type(payload.effect) == "table" and type(payload.effect.obstacle) == "table" then
        self._obstacleList[#self._obstacleList + 1] = {
          id = payload.effect.obstacle.id,
          x = payload.effect.obstacle.x,
          y = payload.effect.obstacle.y,
          width = payload.effect.obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
          height = payload.effect.obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
        }
      end
      if type(payload.effect) == "table" and type(payload.effect.invincibleTurnByPlayer) == "table" then
        self._invincibleTurnByPlayer = normalizeInvincibleTurnByPlayer(payload.effect.invincibleTurnByPlayer)
      end
      if type(payload.effect) == "table" and (payload.effect.shockwaveOwnerPlayerIndex == 1 or payload.effect.shockwaveOwnerPlayerIndex == 2) then
        self._shockwaveOwnerPlayerIndex = payload.effect.shockwaveOwnerPlayerIndex
      end
      self:rebuildPlayingCardButtons()
    else
      if type(payload.effect) == "table" and type(payload.effect.shotBudget) == "number" then
        self._playingShotBudget = payload.effect.shotBudget
      end
      if type(payload.effect) == "table" and type(payload.effect.lockedStoneIds) == "table" then
        self._lockedStoneIdSet = listToSet(payload.effect.lockedStoneIds)
      end
      if type(payload.effect) == "table" and type(payload.effect.spawnStone) == "table" then
        self._playingStoneList[#self._playingStoneList + 1] = {
          id = payload.effect.spawnStone.id,
          ownerPlayerIndex = payload.effect.spawnStone.ownerPlayerIndex,
          x = payload.effect.spawnStone.x,
          y = payload.effect.spawnStone.y,
          alive = payload.effect.spawnStone.alive ~= false
        }
      end
      if type(payload.effect) == "table" and type(payload.effect.obstacle) == "table" then
        self._obstacleList[#self._obstacleList + 1] = {
          id = payload.effect.obstacle.id,
          x = payload.effect.obstacle.x,
          y = payload.effect.obstacle.y,
          width = payload.effect.obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
          height = payload.effect.obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
        }
      end
      if type(payload.effect) == "table" and type(payload.effect.invincibleTurnByPlayer) == "table" then
        self._invincibleTurnByPlayer = normalizeInvincibleTurnByPlayer(payload.effect.invincibleTurnByPlayer)
      end
      if type(payload.effect) == "table" and (payload.effect.shockwaveOwnerPlayerIndex == 1 or payload.effect.shockwaveOwnerPlayerIndex == 2) then
        self._shockwaveOwnerPlayerIndex = payload.effect.shockwaveOwnerPlayerIndex
      end
    end
    self:setStatus("카드 효과 적용됨: " .. tostring(getCardLabel(payload.cardId)), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.turn.shotAccepted" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.shotUsed) == "number" then
      self._playingShotUsed = payload.shotUsed
    end
    if type(payload.shotBudget) == "number" then
      self._playingShotBudget = payload.shotBudget
    end
    self:applyShotImpulse(payload)
    self._isPlayingShotCommitted = self._playingShotUsed >= self._playingShotBudget
    self._isTurnShotPending = false
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self._isAimDragging = false
    self._aimStoneId = nil
    if self._playingShotUsed >= self._playingShotBudget then
      self:setStatus("발사 수락, 스냅샷 대기 중...", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("발사 수락, 추가 발사 가능", Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.snapshotRequested" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    self._isPlayingAwaitingSnapshot = true
    self._turnEndsAtMs = nil
    self._isTurnShotPending = false
    self._isCardUsePending = false
    self._isAimDragging = false
    self._aimStoneId = nil
    self:setStatus("서버가 턴 스냅샷을 요청했습니다.", Constants.COLOR_TEXT_SUB)
    self:sendHostSnapshotIfNeeded(payload.turnIndex, payload.reason)
    return
  end

  if envelope.type == "match.turn.snapshotApplied" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.stones) == "table" then
      self._playingStoneList = clonePlayingStoneList(payload.stones)
      self:resetStoneVelocities()
    end
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self._isPlayingAwaitingSnapshot = false
    self._isPlayingShotCommitted = false
    self._shockwaveSourceStoneId = nil
    if self._effectManager then
      self._effectManager:clear()
    end
    self._isTurnShotPending = false
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self:setStatus("턴 스냅샷 적용 완료", Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.result" then
    local payload = envelope.payload or {}
    self._isSurrenderPending = false
    self._pendingCardTargetId = nil
    self._isResultVotePending = false
    self:setStatus("결과: winner P" .. tostring(payload.winnerPlayerIndex or "?"), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "error.generic" then
    local payload = envelope.payload or {}
    if self._isSurrenderPending then
      self._isSurrenderPending = false
    end
    if self._isResultVotePending then
      self._isResultVotePending = false
    end
    if payload.code == "invalid_placement" or payload.code == "already_submitted" then
      self._isSubmitPending = false
    end
    if payload.code == "invalid_card_pick" or payload.code == "already_locked" then
      self._isCardPickPending = false
    end
    if payload.code == "card_already_used" or payload.code == "card_use_window_closed" or payload.code == "card_not_owned" or payload.code == "card_not_implemented" or payload.code == "invalid_card_id" or payload.code == "invalid_card_target" then
      self._isCardUsePending = false
    end
    if payload.code == "invalid_shot_power" or payload.code == "invalid_shot_dir" or payload.code == "invalid_shot_stone" or payload.code == "not_your_turn" or payload.code == "timeout" or payload.code == "turn_mismatch" or payload.code == "already_shot" or payload.code == "shot_budget_exceeded" or payload.code == "stone_locked_this_turn" then
      self._isTurnShotPending = false
      self._isPlayingShotCommitted = false
      self._isAimDragging = false
      self._aimStoneId = nil
      self._shouldSendSnapshotAfterSim = false
      self:stopShotSimulation()
      self:resetStoneVelocities()
    end
    self:setStatus("서버 오류: " .. tostring(payload.code or "unknown"), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "room.closed" then
    self._app:goLobby({
      statusText = "방이 종료되었습니다.",
      statusColor = Constants.COLOR_DANGER
    })
  end
end

function MatchScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
    return
  end

  if event.type == "ws_envelope" then
    self:onWsEnvelope(event.envelope)
    return
  end

  if event.type == "ws_close" then
    self:setStatus("WS 연결 종료: " .. tostring(event.reason), Constants.COLOR_DANGER)
    return
  end

  if event.type == "ws_error" then
    self:setStatus("WS 오류: " .. tostring(event.message), Constants.COLOR_DANGER)
  end
end

return MatchScene
