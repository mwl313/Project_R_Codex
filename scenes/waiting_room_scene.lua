--[[
파일명: waiting_room_scene.lua
모듈명: WaitingRoomScene

역할:
- 대기방 상태(room.state) 표시
- 채팅 송수신 및 leave 처리

외부에서 사용 가능한 함수:
- WaitingRoomScene.new(app)

주의:
- 채팅 입력은 UTF-8 안전 입력 처리 경로를 사용한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local TextInput = require("ui.text_input")

local WaitingRoomScene = {}
WaitingRoomScene.__index = WaitingRoomScene

local function createDefaultRoomState()
  return {
    phase = "WAITING",
    host = { connected = false, nickname = "Host" },
    guest = nil
  }
end

function WaitingRoomScene.new(app)
  local chatInput = TextInput.new({
    x = 120,
    y = 615,
    w = 850,
    h = 42,
    placeholder = "채팅 입력 (Enter 전송)",
    onEnter = function()
      -- Scene instance에서 처리
    end
  })

  local instance = {
    _app = app,
    _roomState = createDefaultRoomState(),
    _chatMessageList = {},
    _statusText = "WS 연결 대기 중...",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _chatInput = chatInput,
    _sendButton = nil,
    _leaveButton = nil
  }
  setmetatable(instance, WaitingRoomScene)

  instance._sendButton = Button.new({
    x = 985,
    y = 615,
    w = 170,
    h = 42,
    label = "전송",
    onClick = function()
      instance:sendChat()
    end
  })

  instance._leaveButton = Button.new({
    x = 1050,
    y = 38,
    w = 120,
    h = 42,
    label = "나가기",
    color = Constants.COLOR_DANGER,
    onClick = function()
      instance:leaveRoom()
    end
  })

  instance._chatInput.onEnter = function()
    instance:sendChat()
  end

  return instance
end

function WaitingRoomScene:enter(_params)
  self._chatInput:setFocus(true)
  self._roomState = createDefaultRoomState()
  self._chatMessageList = {}
end

function WaitingRoomScene:addChatLine(line)
  self._chatMessageList[#self._chatMessageList + 1] = line
  while #self._chatMessageList > Constants.CHAT_MAX_MESSAGES do
    table.remove(self._chatMessageList, 1)
  end
end

function WaitingRoomScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function WaitingRoomScene:sendChat()
  local text = self._chatInput:getText()
  if text == "" then
    return
  end
  self._app:sendChat(text)
  self._chatInput:setText("")
  self._chatInput.compositionText = ""
end

function WaitingRoomScene:leaveRoom()
  self._app:leaveRoom()
  self._app:goLobby({
    statusText = "대기방에서 나왔습니다.",
    statusColor = Constants.COLOR_TEXT_SUB
  })
end

function WaitingRoomScene:update(_dt)
end

function WaitingRoomScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local session = self._app:getSession()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("대기방", 80, 40, 380, "left")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.printf("Room: " .. (session.roomCode or "-"), 80, 78, 600, "left")

  local roleText = session.role and ("Role: " .. session.role) or "Role: -"
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(roleText, 80, 108, 400, "left")

  self._leaveButton:draw(mouseX, mouseY)

  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 80, 150, 1120, 430, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 80, 150, 1120, 430, 8, 8)

  local hostText = string.format("HOST: %s [%s]", self._roomState.host.nickname or "Host", self._roomState.host.connected and "online" or "offline")
  local guestData = self._roomState.guest
  local guestText = "GUEST: (empty)"
  if guestData then
    guestText = string.format("GUEST: %s [%s]", guestData.nickname or "Guest", guestData.connected and "online" or "offline")
  end

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.print(hostText, 100, 172)
  love.graphics.print(guestText, 100, 198)

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.print("Phase: " .. tostring(self._roomState.phase or "WAITING"), 100, 224)

  love.graphics.setColor(Constants.COLOR_TEXT)
  local chatY = 260
  love.graphics.setFont(FontManager.getFont("small"))
  for _, line in ipairs(self._chatMessageList) do
    love.graphics.print(line, 100, chatY)
    chatY = chatY + 18
  end

  self._chatInput:draw()
  self._sendButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 670, Constants.BASE_WORLD_W, "center")
end

function WaitingRoomScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._leaveButton:isHovered(mouseX, mouseY) then
    self._leaveButton:onClick()
    return
  end
  if self._sendButton:isHovered(mouseX, mouseY) then
    self._sendButton:onClick()
    return
  end
  if self._chatInput:mousepressed(mouseX, mouseY, button) then
    return
  end
  self._chatInput:setFocus(false)
end

function WaitingRoomScene:textinput(text)
  self._chatInput:textinput(text)
end

function WaitingRoomScene:textedited(text, start, length)
  self._chatInput:textedited(text, start, length)
end

function WaitingRoomScene:keypressed(key)
  if self._chatInput:keypressed(key) then
    return
  end
  if key == "escape" then
    self:leaveRoom()
  end
end

function WaitingRoomScene:onWsEnvelope(envelope)
  if envelope.type == "room.state" then
    if type(envelope.payload) == "table" then
      self._roomState = envelope.payload
    end
    return
  end

  if envelope.type == "room.joined" then
    self:addChatLine(string.format("[SYSTEM] player %s joined", tostring(envelope.payload.playerIndex)))
    return
  end

  if envelope.type == "room.left" then
    self:addChatLine(string.format("[SYSTEM] player %s left (%s)", tostring(envelope.payload.playerIndex), tostring(envelope.payload.reason)))
    return
  end

  if envelope.type == "chat.message" then
    local payload = envelope.payload or {}
    self:addChatLine(string.format("[%s] %s", tostring(payload.nickname or "?"), tostring(payload.text or "")))
    return
  end

  if envelope.type == "chat.denied" then
    local payload = envelope.payload or {}
    self:setStatus("채팅 거부: " .. tostring(payload.reason or "unknown"), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "server.welcome" then
    local payload = envelope.payload or {}
    self:setStatus("연결됨 (" .. tostring(payload.role or "?") .. ")", Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "room.closed" then
    self._app:goLobby({
      statusText = "방이 종료되었습니다: " .. tostring(envelope.payload and envelope.payload.reason or "closed"),
      statusColor = Constants.COLOR_DANGER
    })
    return
  end

  if envelope.type == "error.generic" then
    self:setStatus("서버 오류: " .. tostring(envelope.payload and envelope.payload.code or "unknown"), Constants.COLOR_DANGER)
  end
end

function WaitingRoomScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
    return
  end

  if event.type == "ws_open" then
    self:setStatus("WS 연결 성공", Constants.COLOR_TEXT_SUB)
    return
  end
  if event.type == "ws_close" then
    self:setStatus("WS 연결 종료: " .. tostring(event.reason), Constants.COLOR_DANGER)
    return
  end
  if event.type == "ws_error" then
    self:setStatus("WS 오류: " .. tostring(event.message), Constants.COLOR_DANGER)
    return
  end
  if event.type == "ws_envelope" then
    self:onWsEnvelope(event.envelope)
  end
end

return WaitingRoomScene
