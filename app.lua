--[[
파일명: app.lua
모듈명: App

역할:
- Phase 2 클라이언트 전체 상태 관리
- 씬 전환, HTTP/WS 이벤트 처리, 세션 상태 관리

외부에서 사용 가능한 함수:
- App.new(renderScale)
- App:update(dt)
- App:draw()
- App:mousepressed(x, y, button)
- App:mousereleased(x, y, button)
- App:keypressed(key)
- App:textinput(text)
- App:textedited(text, start, length)

주의:
- 네트워크 이벤트는 poll 방식으로 프레임 단위 처리한다
]]

local Constants = require("constants")
local Json = require("utils.json")
local FontManager = require("assets.font_manager")
local SceneManager = require("managers.scene_manager")
local SettingsManager = require("managers.settings_manager")
local SoundManager = require("managers.sound_manager")
local HttpClient = require("net.http_client")
local WsClient = require("net.ws_client")

local App = {}
App.__index = App

local function createSceneFactoryTable()
  return {
    lobby = function(app)
      return require("scenes.lobby_scene").new(app)
    end,
    roomSearch = function(app)
      return require("scenes.room_search_scene").new(app)
    end,
    waitingRoom = function(app)
      return require("scenes.waiting_room_scene").new(app)
    end,
    match = function(app)
      return require("scenes.match_scene").new(app)
    end
  }
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local CLIENT_ENVELOPE_SOUND_HOOK_MAP = {
  ["client.chat.send"] = "chat_send",
  ["client.room.leave"] = "room_leave_request",
  ["client.match.start"] = "match_start_request",
  ["client.match.placement.submit"] = "placement_submit",
  ["client.match.cards.pick"] = "card_pick_submit",
  ["client.match.turn.cardUse"] = "card_use_request",
  ["client.match.rematch.vote"] = "result_vote_submit",
  ["client.match.surrender"] = "match_surrender_request",
  ["client.match.turn.shot"] = "shot_request",
  ["client.match.turn.snapshot"] = "snapshot_submit"
}

local SERVER_ENVELOPE_SOUND_HOOK_MAP = {
  ["server.welcome"] = "ws_welcome",
  ["room.joined"] = "room_joined",
  ["room.left"] = "room_left",
  ["room.closed"] = "room_closed",
  ["chat.message"] = "chat_received",
  ["chat.denied"] = "chat_denied",
  ["match.turnOrder"] = "match_turn_order",
  ["match.phaseChanged"] = "match_phase_changed",
  ["match.placement.revealStart"] = "placement_reveal_start",
  ["match.cards.dealt"] = "cards_dealt",
  ["match.cards.locked"] = "cards_locked",
  ["match.turn.cardCue"] = "card_cue",
  ["match.turn.cardApplied"] = "card_applied",
  ["match.turn.start"] = "turn_start",
  ["match.turn.shotAccepted"] = "shot_accepted",
  ["match.turn.snapshotRequested"] = "snapshot_requested",
  ["match.turn.snapshotApplied"] = "snapshot_applied",
  ["match.result"] = "match_result",
  ["error.generic"] = "error_generic"
}

local NETWORK_EVENT_SOUND_HOOK_MAP = {
  ws_open = "ws_open",
  ws_close = "ws_close",
  ws_error = "ws_error"
}

function App.new(renderScale)
  local instance = {
    _renderScale = renderScale,
    _httpClient = HttpClient.new(),
    _wsClient = WsClient.new(),
    _settingsManager = SettingsManager.new(),
    _soundManager = SoundManager.new(),
    _sceneManager = nil,
    _pendingHttpMap = {},
    _session = {
      roomCode = nil,
      token = nil,
      wsUrl = nil,
      role = nil
    },
    _nickname = "Player",
    _displayMode = Constants.DISPLAY_MODE_WINDOWED,
    _fontWarningText = FontManager.getWarningMessage(),
    _worldMouseX = 0,
    _worldMouseY = 0,
    _pendingBootWarningText = nil
  }
  setmetatable(instance, App)

  instance:loadPersistentSettings()
  instance._sceneManager = SceneManager.new(createSceneFactoryTable(), instance)
  instance._sceneManager:setScene("lobby")
  if instance._pendingBootWarningText then
    instance:emitUiStatus(instance._pendingBootWarningText, Constants.COLOR_DANGER)
  end
  return instance
end

function App:playSoundHook(hookId)
  if not self._soundManager then
    return
  end
  self._soundManager:playHook(hookId)
end

function App:getNickname()
  return self._nickname
end

function App:setNickname(nickname)
  local normalized = self._settingsManager:normalizeSettings({
    nickname = nickname,
    displayMode = self._displayMode
  })
  self._nickname = normalized.nickname
end

function App:getDisplayMode()
  return self._displayMode
end

function App:getSettingsDebugPath()
  return self._settingsManager:getSettingsDebugPath()
end

function App:loadPersistentSettings()
  local loadedSettings, loadError = self._settingsManager:loadSettings()
  local normalizedSettings = self._settingsManager:normalizeSettings(loadedSettings)

  self._nickname = normalizedSettings.nickname
  local appliedDisplayMode, applyError = self._settingsManager:applyDisplayMode(normalizedSettings.displayMode)
  self._displayMode = appliedDisplayMode
  self:resize(love.graphics.getDimensions())

  if loadError then
    self._pendingBootWarningText = "settings.ini 로드 실패, 기본값 사용: " .. tostring(loadError)
    return
  end
  if applyError then
    self._pendingBootWarningText = "디스플레이 적용 실패, 창모드 사용: " .. tostring(applyError)
  end
end

function App:savePersistentSettings(patchSettings)
  local mergedSettings = self._settingsManager:normalizeSettings({
    nickname = patchSettings and patchSettings.nickname or self._nickname,
    displayMode = patchSettings and patchSettings.displayMode or self._displayMode
  })

  local applyWarning = nil
  if mergedSettings.displayMode ~= self._displayMode then
    local appliedDisplayMode, applyError = self._settingsManager:applyDisplayMode(mergedSettings.displayMode)
    self._displayMode = appliedDisplayMode
    mergedSettings.displayMode = appliedDisplayMode
    self:resize(love.graphics.getDimensions())
    applyWarning = applyError
  end

  self._nickname = mergedSettings.nickname

  local isSaved, saveError = self._settingsManager:saveSettings(mergedSettings)
  if not isSaved then
    return false, "settings.ini 저장 실패: " .. tostring(saveError)
  end

  if applyWarning then
    return true, "디스플레이 모드 적용 경고: " .. tostring(applyWarning)
  end
  return true, nil
end

function App:getSession()
  return self._session
end

function App:getMouseWorldPosition()
  return self._worldMouseX, self._worldMouseY
end

function App:updateMouseFromScreen(screenX, screenY)
  self._worldMouseX, self._worldMouseY = self._renderScale:toWorld(screenX, screenY)
end

function App:goLobby(params)
  self._sceneManager:setScene("lobby", params)
end

function App:goRoomSearch(params)
  self._sceneManager:setScene("roomSearch", params)
end

function App:goWaitingRoom(params)
  self._sceneManager:setScene("waitingRoom", params)
end

function App:goMatch(params)
  self._sceneManager:setScene("match", params)
end

function App:emitUiStatus(text, color)
  self._sceneManager:dispatch("onAppEvent", {
    type = "ui_status",
    text = text,
    color = color or Constants.COLOR_TEXT_SUB
  })
end

function App:buildHttpUrl(path)
  return Constants.SERVER_HTTP_BASE_URL .. path
end

function App:buildWsUrl(pathOrAbsolute)
  if startsWith(pathOrAbsolute, "ws://") then
    return pathOrAbsolute
  end
  return Constants.SERVER_WS_BASE_URL .. pathOrAbsolute
end

function App:createRoom()
  self:playSoundHook("room_create_request")
  local requestId = self._httpClient:request("POST", self:buildHttpUrl("/room/create"), {
    nickname = self._nickname
  }, {
    ["content-type"] = "application/json"
  })
  self._pendingHttpMap[requestId] = { kind = "createRoom" }
end

function App:joinRoom(roomCode)
  self:playSoundHook("room_join_request")
  local requestId = self._httpClient:request("POST", self:buildHttpUrl("/room/join"), {
    roomCode = roomCode,
    nickname = self._nickname
  }, {
    ["content-type"] = "application/json"
  })
  self._pendingHttpMap[requestId] = { kind = "joinRoom" }
end

function App:connectWebSocket()
  if not self._session.wsUrl then
    self:playSoundHook("error_generic")
    self:emitUiStatus("WS URL이 없습니다.", Constants.COLOR_DANGER)
    return
  end
  self._wsClient:connect(self:buildWsUrl(self._session.wsUrl))
end

function App:sendWsEnvelope(envelopeType, payload)
  self._wsClient:sendEnvelope({
    type = envelopeType,
    payload = payload or {}
  })
  local hookId = CLIENT_ENVELOPE_SOUND_HOOK_MAP[envelopeType]
  if hookId then
    self:playSoundHook(hookId)
  end
end

function App:sendChat(text)
  self:sendWsEnvelope("client.chat.send", {
    text = text
  })
end

function App:leaveRoom()
  self:sendWsEnvelope("client.room.leave", {})
  self._wsClient:disconnect()
  self._session = {
    roomCode = nil,
    token = nil,
    wsUrl = nil,
    role = nil
  }
end

function App:handleHttpResponse(event)
  local requestMeta = self._pendingHttpMap[event.requestId]
  if not requestMeta then
    return
  end
  self._pendingHttpMap[event.requestId] = nil

  local bodyTable = {}
  if event.body and event.body ~= "" then
    local isDecoded, parsed = pcall(Json.decode, event.body)
    if isDecoded and parsed then
      bodyTable = parsed
    else
      self:playSoundHook("http_parse_error")
      self:emitUiStatus("응답 파싱 실패", Constants.COLOR_DANGER)
      return
    end
  end

  if not event.ok or not bodyTable.ok then
    self:playSoundHook("http_error")
    local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
    self:emitUiStatus("요청 실패: " .. tostring(reason), Constants.COLOR_DANGER)
    return
  end

  self._session.roomCode = bodyTable.roomCode
  self._session.token = bodyTable.token
  self._session.wsUrl = bodyTable.wsUrl
  self._session.role = nil

  if requestMeta.kind == "createRoom" or requestMeta.kind == "joinRoom" then
    if requestMeta.kind == "createRoom" then
      self:playSoundHook("room_create_success")
    else
      self:playSoundHook("room_join_success")
    end
    self:goWaitingRoom()
    self:connectWebSocket()
  end
end

function App:handleWsEnvelope(envelope)
  local hookId = SERVER_ENVELOPE_SOUND_HOOK_MAP[envelope.type]
  if hookId then
    self:playSoundHook(hookId)
  end

  if envelope.type == "server.welcome" then
    local payload = envelope.payload or {}
    self._session.role = payload.role
  elseif envelope.type == "room.closed" then
    self._wsClient:disconnect()
    self._session = {
      roomCode = nil,
      token = nil,
      wsUrl = nil,
      role = nil
    }
  end
  self._sceneManager:dispatch("onAppEvent", {
    type = "ws_envelope",
    envelope = envelope
  })
end

function App:pollNetworkEvents()
  local httpEvents = self._httpClient:pollEvents(20)
  for _, event in ipairs(httpEvents) do
    if event.type == "response" then
      self:handleHttpResponse(event)
    end
  end

  local wsEvents = self._wsClient:pollEvents(50)
  for _, event in ipairs(wsEvents) do
    if event.type == "ws_message" then
      local isDecoded, envelope = pcall(Json.decode, event.text)
      if isDecoded and envelope then
        self:handleWsEnvelope(envelope)
      else
        self:playSoundHook("ws_parse_error")
        self:emitUiStatus("WS 메시지 파싱 실패", Constants.COLOR_DANGER)
      end
    else
      local hookId = NETWORK_EVENT_SOUND_HOOK_MAP[event.type]
      if hookId then
        self:playSoundHook(hookId)
      end
      self._sceneManager:dispatch("onAppEvent", event)
    end
  end
end

function App:update(dt)
  local mouseX, mouseY = love.mouse.getPosition()
  self:updateMouseFromScreen(mouseX, mouseY)
  self:pollNetworkEvents()
  self._sceneManager:update(dt)
end

function App:drawBackground()
  love.graphics.setColor(Constants.COLOR_BG)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
end

function App:draw()
  self:drawBackground()
  self._sceneManager:draw()
  self:drawFontWarning()
end

function App:drawFontWarning()
  if not self._fontWarningText or self._fontWarningText == "" then
    return
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_DANGER)
  love.graphics.printf(self._fontWarningText, 18, 8, Constants.BASE_WORLD_W - 36, "left")
end

function App:mousepressed(screenX, screenY, button)
  local worldX, worldY = self._renderScale:toWorld(screenX, screenY)
  self._sceneManager:dispatch("mousepressed", worldX, worldY, button)
end

function App:mousereleased(screenX, screenY, button)
  local worldX, worldY = self._renderScale:toWorld(screenX, screenY)
  self._sceneManager:dispatch("mousereleased", worldX, worldY, button)
end

function App:keypressed(key)
  self._sceneManager:dispatch("keypressed", key)
end

function App:textinput(text)
  self._sceneManager:dispatch("textinput", text)
end

function App:textedited(text, start, length)
  self._sceneManager:dispatch("textedited", text, start, length)
end

function App:resize(screenW, screenH)
  self._renderScale:update(screenW, screenH)
end

function App:shutdown()
  if self._soundManager then
    self._soundManager:stopAll()
  end
  self._httpClient:shutdown()
  self._wsClient:shutdown()
end

return App
