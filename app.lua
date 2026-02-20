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
- App:mousemoved(x, y, dx, dy)
- App:wheelmoved(x, y)
- App:keypressed(key)
- App:worldToScreen(worldX, worldY)
- App:textinput(text)
- App:textedited(text, start, length)

주의:
- 네트워크 이벤트는 poll 방식으로 프레임 단위 처리한다
]]

local Constants = require("constants")
local Config = require("config")
local Json = require("utils.json")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local UISkin = require("ui.ui_skin")
local UIDraw = require("ui.ui_draw")
local SceneManager = require("managers.scene_manager")
local SettingsManager = require("managers.settings_manager")
local SoundManager = require("managers.sound_manager")
local HttpClient = require("net.http_client")
local WsClient = require("net.ws_client")
local InputCaptureGuard = require("utils.input_capture_guard")

local App = {}
App.__index = App

local function t(key, vars)
  return I18n.t(key, vars)
end

local function createSceneFactoryTable()
  return {
    lobby = function(app)
      return require("scenes.lobby_scene").new(app)
    end,
    play = function(app)
      return require("scenes.play_scene").new(app)
    end,
    multiplayer = function(app)
      return require("scenes.multiplayer_scene").new(app)
    end,
    debugMenu = function(app)
      return require("scenes.debug_menu_scene").new(app)
    end,
    guide = function(app)
      return require("scenes.guide_scene").new(app)
    end,
    skin = function(app)
      return require("scenes.skin_scene").new(app)
    end,
    credits = function(app)
      return require("scenes.credits_scene").new(app)
    end,
    roomSearch = function(app)
      return require("scenes.room_search_scene").new(app)
    end,
    singleDummy = function(app)
      return require("scenes.single_dummy_scene").new(app)
    end,
    waitingRoom = function(app)
      return require("scenes.waiting_room_scene").new(app)
    end,
    coinTossFirst = function(app)
      return require("scenes.coin_toss_first_scene").new(app)
    end,
    coinTossSecond = function(app)
      return require("scenes.coin_toss_second_scene").new(app)
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
      role = nil,
      serverRulesVersion = nil,
      lastRoomState = nil
    },
    _nickname = "Player",
    _displayMode = Constants.DISPLAY_MODE_WINDOWED,
    _language = "ko",
    _fontWarningText = FontManager.getWarningMessage(),
    _worldMouseX = 0,
    _worldMouseY = 0,
    _pendingBootWarningText = nil,
    _lastRulesVersionWarningKey = nil,
    _uiSkin = nil,
    _queuedSceneIntent = nil
  }
  setmetatable(instance, App)

  instance:loadPersistentSettings()
  instance._fontWarningText = FontManager.getWarningMessage()
  instance._uiSkin = UISkin.load()
  UIDraw.setSkin(instance._uiSkin)
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

function App:getLanguage()
  return self._language
end

function App:setLanguage(language)
  self._language = I18n.setLanguage(language)
end

function App:getSettingsDebugPath()
  return self._settingsManager:getSettingsDebugPath()
end

function App:loadPersistentSettings()
  local loadedSettings, loadError = self._settingsManager:loadSettings()
  local normalizedSettings = self._settingsManager:normalizeSettings(loadedSettings)

  self._nickname = normalizedSettings.nickname
  self._language = I18n.setLanguage(normalizedSettings.language)
  local appliedDisplayMode, applyError = self._settingsManager:applyDisplayMode(normalizedSettings.displayMode)
  self._displayMode = appliedDisplayMode
  self:resize(love.graphics.getDimensions())

  if loadError then
    self._pendingBootWarningText = t("app.settings.load_failed_default", {
      error = loadError
    })
    return
  end
  if applyError then
    self._pendingBootWarningText = t("app.settings.apply_failed_windowed", {
      error = applyError
    })
  end
end

function App:savePersistentSettings(patchSettings)
  local mergedSettings = self._settingsManager:normalizeSettings({
    nickname = patchSettings and patchSettings.nickname or self._nickname,
    displayMode = patchSettings and patchSettings.displayMode or self._displayMode,
    language = patchSettings and patchSettings.language or self._language
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
  self._language = I18n.setLanguage(mergedSettings.language)

  local isSaved, saveError = self._settingsManager:saveSettings(mergedSettings)
  if not isSaved then
    return false, t("app.settings.save_failed", {
      error = saveError
    })
  end

  if applyWarning then
    return true, t("app.settings.apply_warning", {
      error = applyWarning
    })
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

function App:screenDeltaToWorldDelta(screenDx, screenDy)
  return self._renderScale:toWorldDelta(screenDx, screenDy)
end

function App:worldToScreen(worldX, worldY)
  return self._renderScale:toScreen(worldX, worldY)
end

function App:goLobby(params, transitionDirection, transitionOpts)
  self:goScene("lobby", params, transitionDirection, transitionOpts)
end

function App:goPlay(params, transitionDirection, transitionOpts)
  self:goScene("play", params, transitionDirection, transitionOpts)
end

function App:goMultiplayer(params, transitionDirection, transitionOpts)
  self:goScene("multiplayer", params, transitionDirection, transitionOpts)
end

function App:goDebugMenu(params, transitionDirection, transitionOpts)
  self:goScene("debugMenu", params, transitionDirection, transitionOpts)
end

function App:goGuide(params, transitionDirection, transitionOpts)
  self:goScene("guide", params, transitionDirection, transitionOpts)
end

function App:goSkin(params, transitionDirection, transitionOpts)
  self:goScene("skin", params, transitionDirection, transitionOpts)
end

function App:goCredits(params, transitionDirection, transitionOpts)
  self:goScene("credits", params, transitionDirection, transitionOpts)
end

function App:goRoomSearch(params, transitionDirection, transitionOpts)
  self:goScene("roomSearch", params, transitionDirection, transitionOpts)
end

function App:goSingleDummy(params, transitionDirection, transitionOpts)
  self:goScene("singleDummy", params, transitionDirection, transitionOpts)
end

function App:goWaitingRoom(params, transitionDirection, transitionOpts)
  self:goScene("waitingRoom", params, transitionDirection, transitionOpts)
end

function App:goMatch(params, transitionDirection, transitionOpts)
  self:goScene("match", params, transitionDirection, transitionOpts)
end

function App:goScene(sceneName, params, transitionDirection, transitionOpts)
  if self:isTransitioningScene() then
    self._queuedSceneIntent = {
      sceneName = sceneName,
      params = params,
      transitionDirection = transitionDirection,
      transitionOpts = transitionOpts
    }
    return
  end

  self._sceneManager:dispatch("onSceneWillChange", {
    toScene = sceneName,
    params = params
  })
  InputCaptureGuard.release()
  self._sceneManager:change(sceneName, params, transitionDirection, transitionOpts)
end

function App:flushQueuedSceneIntent()
  if self:isTransitioningScene() then
    return
  end
  local intent = self._queuedSceneIntent
  if not intent then
    return
  end
  self._queuedSceneIntent = nil
  self:goScene(intent.sceneName, intent.params, intent.transitionDirection, intent.transitionOpts)
end

function App:isTransitioningScene()
  return self._sceneManager and self._sceneManager.isTransitioning and self._sceneManager:isTransitioning()
end

function App:getCurrentSceneName()
  if not self._sceneManager or not self._sceneManager.getCurrentSceneName then
    return nil
  end
  return self._sceneManager:getCurrentSceneName()
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
  if startsWith(pathOrAbsolute, "ws://") or startsWith(pathOrAbsolute, "wss://") then
    return pathOrAbsolute
  end
  return Constants.SERVER_WS_BASE_URL .. pathOrAbsolute
end

function App:checkRulesVersion(serverVersion)
  if type(serverVersion) ~= "number" then
    return
  end
  self._session.serverRulesVersion = serverVersion
  if serverVersion == Constants.RULES_VERSION then
    return
  end
  local warningKey = tostring(serverVersion) .. ":" .. tostring(Constants.RULES_VERSION)
  if self._lastRulesVersionWarningKey == warningKey then
    return
  end
  self._lastRulesVersionWarningKey = warningKey
  self:emitUiStatus(t("app.ui.rules_version_mismatch", {
    clientVersion = tostring(Constants.RULES_VERSION),
    serverVersion = tostring(serverVersion)
  }), Constants.COLOR_DANGER)
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
    self:emitUiStatus(t("app.ui.ws_url_missing"), Constants.COLOR_DANGER)
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
    role = nil,
    serverRulesVersion = nil,
    lastRoomState = nil
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
      self:emitUiStatus(t("app.ui.response_parse_failed"), Constants.COLOR_DANGER)
      return
    end
  end

  if not event.ok or not bodyTable.ok then
    self:playSoundHook("http_error")
    local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
    self:emitUiStatus(t("app.ui.request_failed", {
      reason = reason
    }), Constants.COLOR_DANGER)
    return
  end

  self._session.roomCode = bodyTable.roomCode
  self._session.token = bodyTable.token
  self._session.wsUrl = bodyTable.wsUrl
  self._session.role = nil
  self._session.lastRoomState = nil
  self:checkRulesVersion(bodyTable.rulesVersion)

  if requestMeta.kind == "createRoom" or requestMeta.kind == "joinRoom" then
    if requestMeta.kind == "createRoom" then
      self:playSoundHook("room_create_success")
    else
      self:playSoundHook("room_join_success")
    end
    self:goWaitingRoom(nil, Config.TRANSITION_FORWARD)
    self:connectWebSocket()
  end
end

function App:handleWsEnvelope(envelope)
  local shouldDispatch = true
  local hookId = SERVER_ENVELOPE_SOUND_HOOK_MAP[envelope.type]
  if hookId then
    self:playSoundHook(hookId)
  end

  if envelope.type == "server.welcome" then
    local payload = envelope.payload or {}
    self._session.role = payload.role
    self:checkRulesVersion(payload.rulesVersion)
  elseif envelope.type == "room.state" then
    local payload = envelope.payload or {}
    self._session.lastRoomState = payload
    local sessionRoomCode = self._session.roomCode
    local payloadRoomCode = payload.roomCode
    if sessionRoomCode and payloadRoomCode and tostring(sessionRoomCode) ~= tostring(payloadRoomCode) then
      shouldDispatch = false
    end
    self:checkRulesVersion(payload.rulesVersion)
  elseif envelope.type == "room.closed" then
    self._wsClient:disconnect()
    self._session = {
      roomCode = nil,
      token = nil,
      wsUrl = nil,
      role = nil,
      serverRulesVersion = nil,
      lastRoomState = nil
    }
  end
  if not shouldDispatch then
    return
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
        self:emitUiStatus(t("app.ui.ws_message_parse_failed"), Constants.COLOR_DANGER)
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
  self:flushQueuedSceneIntent()
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

function App:mousemoved(screenX, screenY, screenDx, screenDy)
  self:updateMouseFromScreen(screenX, screenY)
  InputCaptureGuard.onMouseMoved(screenDx, screenDy)
  local worldDx, worldDy = self._renderScale:toWorldDelta(screenDx, screenDy)
  self._sceneManager:dispatch("mousemoved", self._worldMouseX, self._worldMouseY, worldDx, worldDy)
end

function App:wheelmoved(screenDx, screenDy)
  local mouseX, mouseY = love.mouse.getPosition()
  local worldX, worldY = self._renderScale:toWorld(mouseX, mouseY)
  self._sceneManager:dispatch("wheelmoved", worldX, worldY, screenDx, screenDy)
end

function App:keypressed(key)
  if key == "f7" then
    local currentSceneName = self:getCurrentSceneName() or "lobby"
    if currentSceneName ~= "debugMenu" then
      self:goDebugMenu({
        backScene = currentSceneName,
        statusText = t("debug_menu.status.opened_from", {
          scene = tostring(currentSceneName)
        }),
        statusColor = Constants.COLOR_TEXT_SUB
      }, Config.TRANSITION_FORWARD)
    end
    return
  end
  if key == "f6" then
    Config.UI_USE_NINESLICE = not Config.UI_USE_NINESLICE
    self:emitUiStatus(t("app.ui.ui_skin_toggle", {
      state = Config.UI_USE_NINESLICE and t("common.on") or t("common.off")
    }), Constants.COLOR_TEXT_SUB)
    return
  end
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

function App:focus(isFocused)
  if isFocused then
    return
  end
  InputCaptureGuard.release()
  self._sceneManager:dispatch("onAppEvent", {
    type = "focus_lost"
  })
end

function App:shutdown()
  InputCaptureGuard.release()
  if self._soundManager then
    self._soundManager:stopAll()
  end
  self._httpClient:shutdown()
  self._wsClient:shutdown()
end

return App
