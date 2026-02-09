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
        shotCommitted = false,
        awaitingSnapshot = false,
        stones = {}
      }
    }
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
    _isPlayingShotCommitted = false,
    _isPlayingAwaitingSnapshot = false,
    _isTurnShotPending = false,
    _isAimDragging = false,
    _aimStoneId = nil,
    _lastAutoSnapshotTurnIndex = nil
  }
  setmetatable(instance, MatchScene)

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
  self._isPlayingShotCommitted = false
  self._isPlayingAwaitingSnapshot = false
  self._isTurnShotPending = false
  self._isAimDragging = false
  self._aimStoneId = nil
  self._lastAutoSnapshotTurnIndex = nil

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
  return self:isMyTurn() and (not self._isPlayingShotCommitted) and (not self._isPlayingAwaitingSnapshot) and (not self._isTurnShotPending)
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
    if stone.alive ~= false and stone.ownerPlayerIndex == myPlayerIndex then
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

function MatchScene:applySimpleShotToPlayingState(shotPayload)
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

  local distance = math.max(0, shotPayload.power / Constants.POWER_PER_PIXEL)
  local nextX = stone.x + shotPayload.dirX * distance
  local nextY = stone.y + shotPayload.dirY * distance
  local isInside = nextX >= Constants.STONE_RADIUS and nextX <= Constants.BOARD_W - Constants.STONE_RADIUS and nextY >= Constants.STONE_RADIUS and nextY <= Constants.BOARD_H - Constants.STONE_RADIUS

  stone.x = nextX
  stone.y = nextY
  if not isInside then
    stone.alive = false
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

  self._lastAutoSnapshotTurnIndex = turnIndex
  self._app:sendWsEnvelope("client.match.turn.snapshot", {
    turnIndex = turnIndex,
    stones = clonePlayingStoneList(self._playingStoneList)
  })
  self:setStatus("턴 스냅샷 제출 (" .. tostring(reason or "auto") .. ")", Constants.COLOR_TEXT_SUB)
end

function MatchScene:applyRoomState(payload)
  self._roomState = payload

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
    if type(playing.stones) == "table" then
      self._playingStoneList = clonePlayingStoneList(playing.stones)
    end
  end

  if payload.phase == Constants.PHASE_PLACEMENT_PRIVATE then
    self:setStatus("배치 단계: 클릭으로 7개를 배치한 뒤 제출하세요.", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLACEMENT_REVEAL then
    self:setStatus("배치 공개 중...", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_CARD_SELECT then
    self:setStatus("카드 선택 단계입니다.", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLAYING then
    if self:isMyTurn() then
      self:setStatus("내 턴입니다. 알을 드래그해 발사하세요.", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("상대 턴 진행 중...", Constants.COLOR_TEXT_SUB)
    end
    if self._isPlayingAwaitingSnapshot then
      self:sendHostSnapshotIfNeeded(self._playingTurnIndex, "state_sync")
    end
  elseif payload.phase == Constants.PHASE_RESULT then
    self:setStatus("결과 단계 진입", Constants.COLOR_DANGER)
  end
end

function MatchScene:update(_dt)
end

function MatchScene:drawBoardFrame()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  local centerWorldY = self._boardY + Constants.BOARD_H * 0.5
  local stripY = centerWorldY - Constants.NO_PLACE_BUFFER
  local stripH = Constants.NO_PLACE_BUFFER * 2

  love.graphics.setColor(0.65, 0.18, 0.22, 0.20)
  love.graphics.rectangle("fill", self._boardX, stripY, Constants.BOARD_W, stripH)

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
  elseif self._isPlayingShotCommitted then
    stateText = "발사 완료"
  elseif self._isTurnShotPending then
    stateText = "발사 요청 전송 중"
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(
    string.format("턴 %d | %s | 남은 시간: %ds | 상태: %s", self._playingTurnIndex, turnOwnerText, remainSec, stateText),
    0,
    636,
    Constants.BASE_WORLD_W,
    "center"
  )
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

  self:drawAimGuide(mouseX, mouseY)

  if self:isPlacementPhase() then
    local canSubmit = (not self._isPlacementSubmitted) and (not self._isSubmitPending) and #self._myStoneList == Constants.STONE_COUNT_PER_PLAYER
    self._submitButton.isEnabled = canSubmit
    self._submitButton:draw(mouseX, mouseY)
  end

  if self._roomState.phase == Constants.PHASE_CARD_SELECT then
    self:drawCardSelectPanel(mouseX, mouseY)
  elseif self._roomState.phase == Constants.PHASE_PLAYING or self._roomState.phase == Constants.PHASE_RESULT then
    self:drawPlayingInfo()
  else
    self:drawPlacementInfo()
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function MatchScene:mousepressed(mouseX, mouseY, button)
  if self:isPlayingPhase() and button == 2 then
    self:cancelAimDrag()
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
    self:beginAimDrag(mouseX, mouseY)
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
  if key == "escape" and self._isAimDragging then
    self:cancelAimDrag()
    return
  end
  if key == "escape" and self._roomState.phase == Constants.PHASE_RESULT then
    self._app:goLobby({
      statusText = "RESULT에서 로비로 복귀했습니다.",
      statusColor = Constants.COLOR_TEXT_SUB
    })
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
    self._isPlayingShotCommitted = false
    self._isPlayingAwaitingSnapshot = false
    self._isTurnShotPending = false
    self._isAimDragging = false
    self._aimStoneId = nil
    if self:isMyTurn() then
      self:setStatus("내 턴 시작. 드래그해서 발사하세요.", Constants.COLOR_TEXT_SUB)
    else
      self:setStatus("상대 턴 시작", Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.shotAccepted" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    self:applySimpleShotToPlayingState(payload)
    self._isPlayingShotCommitted = true
    self._isTurnShotPending = false
    self._isAimDragging = false
    self._aimStoneId = nil
    self:setStatus("발사 수락, 스냅샷 대기 중...", Constants.COLOR_TEXT_SUB)
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
    end
    self._isPlayingAwaitingSnapshot = false
    self._isPlayingShotCommitted = false
    self._isTurnShotPending = false
    self:setStatus("턴 스냅샷 적용 완료", Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.result" then
    local payload = envelope.payload or {}
    self:setStatus("결과: winner P" .. tostring(payload.winnerPlayerIndex or "?"), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "error.generic" then
    local payload = envelope.payload or {}
    if payload.code == "invalid_placement" or payload.code == "already_submitted" then
      self._isSubmitPending = false
    end
    if payload.code == "invalid_card_pick" or payload.code == "already_locked" then
      self._isCardPickPending = false
    end
    if payload.code == "invalid_shot_power" or payload.code == "invalid_shot_dir" or payload.code == "invalid_shot_stone" or payload.code == "not_your_turn" or payload.code == "timeout" or payload.code == "turn_mismatch" or payload.code == "already_shot" then
      self._isTurnShotPending = false
      self._isPlayingShotCommitted = false
      self._isAimDragging = false
      self._aimStoneId = nil
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
