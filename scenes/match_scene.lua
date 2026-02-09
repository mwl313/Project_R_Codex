--[[
파일명: match_scene.lua
모듈명: MatchScene

역할:
- Phase 3 매치 진행 화면(배치/공개/카드선택 진입 전)
- 배치 클릭 입력, 제출, 공개 렌더링 처리

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

local function nowEpochMs()
  return os.time() * 1000
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
      }
    }
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
    _submitButton = nil
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

  return instance
end

function MatchScene:enter(params)
  self._roomState = createDefaultRoomState()
  self._myStoneList = {}
  self._isPlacementSubmitted = false
  self._isSubmitPending = false
  self._revealStoneMap = nil

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

  if payload.phase == Constants.PHASE_PLACEMENT_PRIVATE then
    self:setStatus("배치 단계: 클릭으로 7개를 배치한 뒤 제출하세요.", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLACEMENT_REVEAL then
    self:setStatus("배치 공개 중...", Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_CARD_SELECT then
    self:setStatus("카드 선택 단계 진입 (후속 구현 예정)", Constants.COLOR_TEXT_SUB)
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
    local localX, localY = self:canonicalToLocal(stone.x, stone.y)
    love.graphics.circle("fill", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
  end

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  for _, stone in ipairs(stoneList or {}) do
    local localX, localY = self:canonicalToLocal(stone.x, stone.y)
    love.graphics.circle("line", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
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

function MatchScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("Match Phase", 0, 16, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("현재 Phase: " .. tostring(self._roomState.phase), 0, 48, Constants.BASE_WORLD_W, "center")

  self:drawBoardFrame()

  if self:isRevealVisiblePhase() and self._revealStoneMap then
    self:drawStoneList(self._revealStoneMap.host, Constants.COLOR_STONE_HOST)
    self:drawStoneList(self._revealStoneMap.guest, Constants.COLOR_STONE_GUEST)
  else
    local role = self:getMyRole()
    local color = role == "guest" and Constants.COLOR_STONE_GUEST or Constants.COLOR_STONE_HOST
    self:drawStoneList(self._myStoneList, color)
  end

  local canSubmit = self:isPlacementPhase() and (not self._isPlacementSubmitted) and (not self._isSubmitPending) and #self._myStoneList == Constants.STONE_COUNT_PER_PLAYER
  self._submitButton.isEnabled = canSubmit
  self._submitButton:draw(mouseX, mouseY)

  self:drawPlacementInfo()

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function MatchScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
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

function MatchScene:textinput(_text)
end

function MatchScene:textedited(_text, _start, _length)
end

function MatchScene:keypressed(key)
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
