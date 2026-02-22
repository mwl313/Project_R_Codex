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
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local TextInput = require("ui.text_input")

local WaitingRoomScene = {}
WaitingRoomScene.__index = WaitingRoomScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function createDefaultRoomState()
  return {
    phase = Constants.PHASE_WAITING,
    host = { connected = false, nickname = t("waiting_room.default_host_name") },
    guest = nil,
    guestReady = false
  }
end

function WaitingRoomScene.new(app)
  local chatInput = TextInput.new({
    x = 120,
    y = 615,
    w = 850,
    h = 42,
    placeholder = t("waiting_room.chat_placeholder"),
    onEnter = function()
      -- Scene instance에서 처리
    end
  })

  local instance = {
    _app = app,
    _roomState = createDefaultRoomState(),
    _chatMessageList = {},
    _statusText = t("waiting_room.status.server_waiting"),
    _statusColor = Constants.COLOR_TEXT_SUB,
    _chatInput = chatInput,
    _startButton = nil,
    _copyCodeButton = nil,
    _sendButton = nil,
    _leaveButton = nil,
    _lastLanguage = app:getLanguage(),
    _isCoinTossFlowStarted = false
  }
  setmetatable(instance, WaitingRoomScene)

  instance._startButton = Button.new({
    x = 900,
    y = 38,
    w = 135,
    h = 42,
    label = t("common.button.start_game"),
    onClick = function()
      instance:requestMatchStart()
    end
  })

  instance._copyCodeButton = Button.new({
    x = 0,
    y = 0,
    w = 88,
    h = 34,
    label = t("common.button.copy"),
    onClick = function()
      instance:copyRoomCode()
    end
  })

  instance._sendButton = Button.new({
    x = 985,
    y = 615,
    w = 170,
    h = 42,
    label = t("common.button.send"),
    onClick = function()
      instance:sendChat()
    end
  })

  instance._leaveButton = Button.new({
    x = 1050,
    y = 38,
    w = 120,
    h = 42,
    label = t("common.button.leave"),
    color = Constants.COLOR_DANGER,
    onClick = function()
      instance:leaveRoom()
    end
  })

  instance._chatInput.onEnter = function()
    instance:sendChat()
  end

  instance:rebuildLocalizedUi()
  return instance
end

function WaitingRoomScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._chatInput.placeholder = t("waiting_room.chat_placeholder")
  self._copyCodeButton.label = t("common.button.copy")
  self._sendButton.label = t("common.button.send")
  self._leaveButton.label = t("common.button.leave")
end

function WaitingRoomScene:enter(params)
  self._chatInput:setFocus(true)
  if params and type(params.roomState) == "table" then
    self._roomState = params.roomState
  else
    self._roomState = createDefaultRoomState()
  end
  self._chatMessageList = {}
  self._isCoinTossFlowStarted = false
  if params and params.statusText then
    self:setStatus(params.statusText, params.statusColor)
  end
  self:rebuildLocalizedUi()
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
  self._roomState.guestReady = false
  self._app:leaveRoom()
  self._app:goMultiplayer({
    backScene = "play",
    statusText = t("waiting_room.status.left_room"),
    statusColor = Constants.COLOR_TEXT_SUB
  }, Config.TRANSITION_BACK)
end

function WaitingRoomScene:canRequestMatchStart()
  local session = self._app:getSession()
  if not session or session.role ~= "host" then
    return false
  end
  if self._roomState.phase ~= Constants.PHASE_WAITING then
    return false
  end
  if self._roomState.guestReady ~= true then
    return false
  end
  return self._roomState.host and self._roomState.host.connected and self._roomState.guest and self._roomState.guest.connected
end

function WaitingRoomScene:canRequestGuestReady()
  local session = self._app:getSession()
  if not session or session.role ~= "guest" then
    return false
  end
  if self._roomState.phase ~= Constants.PHASE_WAITING then
    return false
  end
  if self._roomState.guestReady == true then
    return false
  end
  return true
end

function WaitingRoomScene:isGuestReady()
  return self._roomState and self._roomState.guestReady == true
end

function WaitingRoomScene:updateStartButtonState()
  local session = self._app:getSession()
  local role = session and session.role or nil
  self._startButton.isPressed = false
  self._startButton.color = Constants.COLOR_BUTTON
  self._startButton.hoverColor = nil

  if role == "guest" then
    if self:isGuestReady() then
      self._startButton.label = t("waiting_room.button.waiting")
      self._startButton.isEnabled = true
      self._startButton.isPressed = true
      self._startButton.color = Constants.COLOR_BUTTON_SELECTED
      self._startButton.hoverColor = Constants.COLOR_BUTTON_SELECTED
      return
    end
    self._startButton.label = t("waiting_room.button.ready")
    self._startButton.isEnabled = self:canRequestGuestReady()
    return
  end

  self._startButton.label = t("common.button.start_game")
  self._startButton.isEnabled = self:canRequestMatchStart()
end

function WaitingRoomScene:requestMatchStart()
  local session = self._app:getSession()
  if session and session.role == "guest" then
    self:requestGuestReady()
    return
  end

  if not self:canRequestMatchStart() then
    self:setStatus(t("waiting_room.status.start_condition_not_met"), Constants.COLOR_DANGER)
    return
  end
  self._app:sendEnvelope("client.match.start", {})
  self:setStatus(t("waiting_room.status.start_request_sent"), Constants.COLOR_TEXT_SUB)
end

function WaitingRoomScene:requestGuestReady()
  if not self:canRequestGuestReady() then
    if self:isGuestReady() then
      self:setStatus(t("waiting_room.status.already_ready"), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("waiting_room.status.start_condition_not_met"), Constants.COLOR_DANGER)
    end
    return
  end
  self._app:sendEnvelope("client.room.ready", {})
  self:setStatus(t("waiting_room.status.ready_request_sent"), Constants.COLOR_TEXT_SUB)
end

function WaitingRoomScene:copyRoomCode()
  local session = self._app:getSession()
  local roomCode = session and session.roomCode or nil
  if not roomCode or roomCode == "" then
    self:setStatus(t("waiting_room.status.no_room_code"), Constants.COLOR_DANGER)
    return
  end

  if not love.system or not love.system.setClipboardText then
    self:setStatus(t("waiting_room.status.clipboard_not_available"), Constants.COLOR_DANGER)
    return
  end

  local isOk, errorText = pcall(love.system.setClipboardText, roomCode)
  if not isOk then
    self:setStatus(t("waiting_room.status.room_copy_failed", {
      error = errorText
    }), Constants.COLOR_DANGER)
    return
  end

  self:setStatus(t("waiting_room.status.room_copied", {
    roomCode = roomCode
  }), Constants.COLOR_TEXT_SUB)
end

function WaitingRoomScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function WaitingRoomScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local session = self._app:getSession()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("waiting_room.title"), 80, 40, 380, "left")

  love.graphics.setFont(FontManager.getFont("ui"))
  local roomCode = session.roomCode or "-"
  local roomLabel = t("waiting_room.room_label", {
    roomCode = roomCode
  })
  love.graphics.printf(roomLabel, 80, 78, 600, "left")
  self._copyCodeButton.x = 80 + FontManager.getFont("ui"):getWidth(roomLabel) + 16
  self._copyCodeButton.y = 84
  self._copyCodeButton.isEnabled = session.roomCode and session.roomCode ~= ""
  self._copyCodeButton:draw(mouseX, mouseY)

  local roleText = session.role and t("waiting_room.role_label", {
    role = session.role
  }) or t("waiting_room.role_unknown")
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(roleText, 80, 108, 400, "left")

  self:updateStartButtonState()
  self._startButton:draw(mouseX, mouseY)
  self._leaveButton:draw(mouseX, mouseY)

  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 80, 150, 1120, 430, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 80, 150, 1120, 430, 8, 8)

  local hostText = t("waiting_room.host_line", {
    nickname = self._roomState.host.nickname or t("waiting_room.default_host_name"),
    state = self._roomState.host.connected and t("waiting_room.online") or t("waiting_room.offline")
  })
  local guestData = self._roomState.guest
  local guestText = t("waiting_room.guest_empty")
  if guestData then
    guestText = t("waiting_room.guest_line", {
      nickname = guestData.nickname or t("waiting_room.default_guest_name"),
      state = guestData.connected and t("waiting_room.online") or t("waiting_room.offline")
    })
  end

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.print(hostText, 100, 172)
  love.graphics.print(guestText, 100, 198)

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.print(t("waiting_room.phase_line", {
    phase = tostring(self._roomState.phase or "WAITING")
  }), 100, 224)

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
  if self._copyCodeButton:isHovered(mouseX, mouseY) and self._copyCodeButton.isEnabled then
    self._copyCodeButton:onClick()
    return
  end
  local session = self._app:getSession()
  if session and session.role == "guest" and self:isGuestReady() and self._startButton:isHovered(mouseX, mouseY) then
    return
  end
  if self._startButton:isHovered(mouseX, mouseY) and self._startButton.isEnabled then
    self._startButton:onClick()
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

function WaitingRoomScene:onServerEnvelope(envelope)
  if envelope.type == "room.state" then
    if type(envelope.payload) == "table" then
      self._roomState = envelope.payload
      if self._isCoinTossFlowStarted then
        return
      end
      if self._roomState.phase and self._roomState.phase ~= Constants.PHASE_WAITING then
        self._app:goMatch({
          roomState = self._roomState
        }, Config.TRANSITION_FORWARD)
        return
      end
    end
    return
  end

  if envelope.type == "room.joined" then
    self:addChatLine(t("waiting_room.system.player_joined", {
      playerIndex = tostring(envelope.payload.playerIndex)
    }))
    return
  end

  if envelope.type == "room.left" then
    local payload = envelope.payload or {}
    if payload.playerIndex == 2 then
      self._roomState.guestReady = false
    end
    self:addChatLine(t("waiting_room.system.player_left", {
      playerIndex = tostring(payload.playerIndex),
      reason = tostring(payload.reason)
    }))
    return
  end

  if envelope.type == "room.ready" then
    local payload = envelope.payload or {}
    if payload.ready == true then
      self:addChatLine(t("waiting_room.system.guest_ready", {
        nickname = tostring(payload.nickname or t("waiting_room.default_guest_name"))
      }))
    end
    return
  end

  if envelope.type == "chat.message" then
    local payload = envelope.payload or {}
    self:addChatLine(t("waiting_room.chat_line", {
      nickname = tostring(payload.nickname or "?"),
      text = tostring(payload.text or "")
    }))
    return
  end

  if envelope.type == "chat.denied" then
    local payload = envelope.payload or {}
    self:setStatus(t("waiting_room.status.chat_denied", {
      reason = tostring(payload.reason or t("common.unknown"))
    }), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "server.welcome" then
    local payload = envelope.payload or {}
    self:setStatus(t("waiting_room.status.connected", {
      role = tostring(payload.role or "?")
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.turnOrder" then
    local payload = envelope.payload or {}
    local firstPlayerIndex = payload.firstPlayerIndex
    local session = self._app:getSession()
    local myPlayerIndex = nil
    if session and session.role == "host" then
      myPlayerIndex = 1
    elseif session and session.role == "guest" then
      myPlayerIndex = 2
    end

    if (firstPlayerIndex == 1 or firstPlayerIndex == 2) and myPlayerIndex then
      self._isCoinTossFlowStarted = true
      local sceneName = myPlayerIndex == firstPlayerIndex and "coinTossFirst" or "coinTossSecond"
      self._app:goScene(sceneName, {
        roomState = self._roomState,
        nextSceneName = "match"
      }, Config.TRANSITION_FORWARD)
      return
    end

    self:setStatus(t("waiting_room.status.turn_order", {
      playerIndex = tostring(payload.firstPlayerIndex or "?")
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "room.closed" then
    self._app:goMultiplayer({
      backScene = "play",
      statusText = t("waiting_room.status.room_closed", {
        reason = tostring(envelope.payload and envelope.payload.reason or "closed")
      }),
      statusColor = Constants.COLOR_DANGER
    }, Config.TRANSITION_BACK)
    return
  end

  if envelope.type == "error.generic" then
    local code = tostring(envelope.payload and envelope.payload.code or t("common.unknown"))
    if code == "guest_not_ready" then
      self:setStatus(t("waiting_room.status.guest_not_ready"), Constants.COLOR_DANGER)
      return
    end
    if code == "already_ready" then
      self:setStatus(t("waiting_room.status.already_ready"), Constants.COLOR_TEXT_SUB)
      return
    end
    self:setStatus(t("waiting_room.status.server_error", {
      code = code
    }), Constants.COLOR_DANGER)
  end
end

function WaitingRoomScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
    return
  end

  if event.type == "server_open" then
    self:setStatus(t("waiting_room.status.server_open"), Constants.COLOR_TEXT_SUB)
    return
  end
  if event.type == "server_close" then
    self._roomState.guestReady = false
    self:setStatus(t("waiting_room.status.server_close", {
      reason = tostring(event.reason)
    }), Constants.COLOR_DANGER)
    return
  end
  if event.type == "server_error" then
    self:setStatus(t("waiting_room.status.server_error_event", {
      message = tostring(event.message)
    }), Constants.COLOR_DANGER)
    return
  end
  if event.type == "server_envelope" then
    self:onServerEnvelope(event.envelope)
  end
end

return WaitingRoomScene
