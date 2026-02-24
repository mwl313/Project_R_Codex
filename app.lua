--[[
파일명: app.lua
모듈명: App

역할:
- Phase 2 클라이언트 전체 상태 관리
- 씬 전환, HTTP long-poll 이벤트 처리, 세션 상태 관리

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
local InputCaptureGuard = require("utils.input_capture_guard")
local ServerEnv = require("net.server_env")

local App = {}
App.__index = App

local function t(key, vars)
  return I18n.t(key, vars)
end

local function shortToken(token)
  if type(token) ~= "string" or token == "" then
    return ""
  end
  if #token <= 10 then
    return token
  end
  return string.sub(token, 1, 6) .. "..." .. string.sub(token, -4)
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
    single_campaign = function(app)
      return require("scenes.single_campaign_scene").new(app)
    end,
    single_deck_manage = function(app)
      return require("scenes.single_deck_manage_scene").new(app)
    end,
    single_map = function(app)
      return require("scenes.single_map_scene").new(app)
    end,
    single_combat = function(app)
      return require("scenes.single_combat_scene").new(app)
    end,
    single_shop = function(app)
      return require("scenes.single_shop_scene").new(app)
    end,
    single_rest = function(app)
      return require("scenes.single_rest_scene").new(app)
    end,
    single_deck_clean = function(app)
      return require("scenes.single_deck_clean_scene").new(app)
    end,
    single_event = function(app)
      return require("scenes.single_event_scene").new(app)
    end,
    single_reward = function(app)
      return require("scenes.single_reward_scene").new(app)
    end,
    single_discard = function(app)
      return require("scenes.single_discard_scene").new(app)
    end,
    single_result = function(app)
      return require("scenes.single_result_scene").new(app)
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
  server_open = "ws_open",
  server_close = "ws_close",
  server_error = "ws_error"
}

function App.new(renderScale)
  local instance = {
    _renderScale = renderScale,
    _httpClient = HttpClient.new(),
    _pollHttpClient = HttpClient.new(),
    _settingsManager = SettingsManager.new(),
    _soundManager = SoundManager.new(),
    _sceneManager = nil,
    _pendingHttpMap = {},
    _poll = {
      isActive = false,
      cursor = 0,
      inFlightRequestId = nil,
      nextPollAtMs = 0,
      backoffMs = 0,
      generation = 0,
      lastIssued = nil
    },
    _session = {
      roomCode = nil,
      token = nil,
      role = nil,
      serverRulesVersion = nil,
      lastRoomState = nil
    },
    _nickname = "Player",
    _displayMode = Constants.DISPLAY_MODE_WINDOWED,
    _language = "ko",
    _serverEnv = Constants.SERVER_ENV_DEFAULT,
    _serverStreamConnected = false,
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

function App:networkLog(tag, payload)
  if Constants.NETWORK_DIAG_LOG ~= true then
    return
  end
  local encodedPayload = "{}"
  if payload ~= nil then
    local isEncoded, encodedOrError = pcall(Json.encode, payload)
    if isEncoded and type(encodedOrError) == "string" then
      encodedPayload = encodedOrError
    else
      encodedPayload = "{\"encodeError\":true}"
    end
  end
  print(string.format("[NET][%s] %s", tostring(tag), encodedPayload))
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
    displayMode = self._displayMode,
    language = self._language,
    serverEnv = self._serverEnv
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

function App:getServerEnv()
  return self._serverEnv
end

function App:getServerHttpBase(env)
  return ServerEnv.getHttpBase(env)
end

function App:getServerWsBase(env)
  -- Deprecated: 클라이언트 런타임은 WS를 사용하지 않는다.
  -- 하위호환 조회가 남아있는 경우를 위해서만 유지한다.
  return ServerEnv.getWsBase(env, false)
end

function App:isNetworkSessionActive()
  if self._poll and self._poll.isActive then
    return true
  end
  if next(self._pendingHttpMap) ~= nil then
    return true
  end
  if self._session.roomCode or self._session.token then
    return true
  end
  return false
end

function App:canSwitchServerEnv()
  if self:isNetworkSessionActive() then
    return false
  end
  return true
end

function App:setServerEnv(serverEnv)
  if not self:canSwitchServerEnv() then
    return false, t("debug_menu.status.server_env_locked")
  end

  local previousEnv = self._serverEnv
  local normalizedEnv = ServerEnv.set(serverEnv)
  self._serverEnv = normalizedEnv

  local isSaved, saveMessage = self:savePersistentSettings({
    serverEnv = normalizedEnv
  })
  if not isSaved then
    self._serverEnv = ServerEnv.set(previousEnv)
    return false, saveMessage
  end

  return true, t("debug_menu.status.server_env_applied", {
    env = normalizedEnv == Constants.SERVER_ENV_LOCAL and t("debug_menu.network.local") or t("debug_menu.network.cloud")
  })
end

function App:loadPersistentSettings()
  local loadedSettings, loadError = self._settingsManager:loadSettings()
  local normalizedSettings = self._settingsManager:normalizeSettings(loadedSettings)

  self._nickname = normalizedSettings.nickname
  self._language = I18n.setLanguage(normalizedSettings.language)
  self._serverEnv = ServerEnv.set(normalizedSettings.serverEnv)
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
    language = patchSettings and patchSettings.language or self._language,
    serverEnv = patchSettings and patchSettings.serverEnv or self._serverEnv
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
  self._serverEnv = ServerEnv.set(mergedSettings.serverEnv)

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

function App:goSingleCampaign(params, transitionDirection, transitionOpts)
  self:goScene("single_campaign", params, transitionDirection, transitionOpts)
end

function App:goSingleDeckManage(params, transitionDirection, transitionOpts)
  self:goScene("single_deck_manage", params, transitionDirection, transitionOpts)
end

function App:goSingleMap(params, transitionDirection, transitionOpts)
  self:goScene("single_map", params, transitionDirection, transitionOpts)
end

function App:goSingleCombat(params, transitionDirection, transitionOpts)
  self:goScene("single_combat", params, transitionDirection, transitionOpts)
end

function App:goSingleShop(params, transitionDirection, transitionOpts)
  self:goScene("single_shop", params, transitionDirection, transitionOpts)
end

function App:goSingleRest(params, transitionDirection, transitionOpts)
  self:goScene("single_rest", params, transitionDirection, transitionOpts)
end

function App:goSingleDeckClean(params, transitionDirection, transitionOpts)
  self:goScene("single_deck_clean", params, transitionDirection, transitionOpts)
end

function App:goSingleEvent(params, transitionDirection, transitionOpts)
  self:goScene("single_event", params, transitionDirection, transitionOpts)
end

function App:goSingleReward(params, transitionDirection, transitionOpts)
  self:goScene("single_reward", params, transitionDirection, transitionOpts)
end

function App:goSingleDiscard(params, transitionDirection, transitionOpts)
  self:goScene("single_discard", params, transitionDirection, transitionOpts)
end

function App:goSingleResult(params, transitionDirection, transitionOpts)
  self:goScene("single_result", params, transitionDirection, transitionOpts)
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
  return ServerEnv.getHttpBase() .. path
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
  self._pendingHttpMap["main:" .. requestId] = { kind = "createRoom" }
end

function App:joinRoom(roomCode)
  self:playSoundHook("room_join_request")
  local requestId = self._httpClient:request("POST", self:buildHttpUrl("/room/join"), {
    roomCode = roomCode,
    nickname = self._nickname
  }, {
    ["content-type"] = "application/json"
  })
  self._pendingHttpMap["main:" .. requestId] = { kind = "joinRoom" }
end

function App:getNowMs()
  if love and love.timer and love.timer.getTime then
    return math.floor(love.timer.getTime() * 1000)
  end
  return math.floor(os.clock() * 1000)
end

function App:resetPollState()
  for requestKey, requestMeta in pairs(self._pendingHttpMap) do
    if type(requestMeta) == "table" and requestMeta.kind == "poll" then
      self._pendingHttpMap[requestKey] = nil
    end
  end
  self._poll.isActive = false
  self._poll.cursor = 0
  self._poll.inFlightRequestId = nil
  self._poll.nextPollAtMs = 0
  self._poll.backoffMs = 0
  self._poll.generation = (self._poll.generation or 0) + 1
  self._poll.lastIssued = nil
end

function App:startPolling()
  if not self._session.roomCode or not self._session.token then
    return
  end
  self:resetPollState()
  self._poll.isActive = true
  self._poll.nextPollAtMs = self:getNowMs()
  self._serverStreamConnected = true
  self:networkLog("POLL_START", {
    roomCode = self._session.roomCode,
    token = shortToken(self._session.token),
    generation = self._poll.generation,
    serverEnv = self._serverEnv,
    httpBase = self:getServerHttpBase(self._serverEnv)
  })
  self:playSoundHook(NETWORK_EVENT_SOUND_HOOK_MAP.server_open)
  self._sceneManager:dispatch("onAppEvent", {
    type = "server_open"
  })
end

function App:stopPolling(reason)
  if not self._poll.isActive and not self._serverStreamConnected then
    return
  end
  self:resetPollState()
  self._serverStreamConnected = false
  self:networkLog("POLL_STOP", {
    reason = reason or "poll_stopped",
    roomCode = self._session.roomCode,
    token = shortToken(self._session.token),
    serverEnv = self._serverEnv,
    httpBase = self:getServerHttpBase(self._serverEnv)
  })
  self:playSoundHook(NETWORK_EVENT_SOUND_HOOK_MAP.server_close)
  self._sceneManager:dispatch("onAppEvent", {
    type = "server_close",
    reason = reason or "poll_stopped"
  })
end

function App:buildSendRetryMeta(envelopeType, payload, options)
  local opts = options or {}
  local critical = opts.critical == true
  return {
    kind = "sendEnvelope",
    envelopeType = envelopeType,
    payload = payload or {},
    critical = critical,
    retryCount = opts.retryCount or 0,
    maxRetry = opts.maxRetry or Constants.NETWORK_SEND_RETRY_MAX,
    silent = opts.silent == true
  }
end

function App:requestSendEnvelope(envelopeType, payload, options)
  if not self._session.roomCode or not self._session.token then
    self:emitUiStatus(t("app.ui.request_failed", {
      reason = "session_missing"
    }), Constants.COLOR_DANGER)
    return nil
  end
  local requestId = self._httpClient:request("POST", self:buildHttpUrl("/room/send"), {
    roomCode = self._session.roomCode,
    token = self._session.token,
    envelope = {
      type = envelopeType,
      payload = payload or {}
    }
  }, {
    ["content-type"] = "application/json"
  })
  self._pendingHttpMap["main:" .. requestId] = self:buildSendRetryMeta(envelopeType, payload, options)
  return requestId
end

function App:sendClientEnvelope(envelopeType, payload, options)
  local requestId = self:requestSendEnvelope(envelopeType, payload, options)
  if not requestId then
    return
  end
  local hookId = CLIENT_ENVELOPE_SOUND_HOOK_MAP[envelopeType]
  if hookId then
    self:playSoundHook(hookId)
  end
  local shouldTriggerEarlyPoll = options and options.critical == true
  if shouldTriggerEarlyPoll and self._poll.isActive and not self._poll.inFlightRequestId then
    self._poll.nextPollAtMs = self:getNowMs()
  end
end

function App:sendEnvelope(envelopeType, payload)
  local criticalEnvelopeTypeMap = {
    ["client.match.turn.shot"] = true,
    ["client.match.turn.snapshot"] = true,
    ["client.match.turn.cardUse"] = true,
    ["client.match.cards.pick"] = true,
    ["client.match.placement.submit"] = true,
    ["client.match.start"] = true,
    ["client.room.ready"] = true,
    ["client.match.rematch.vote"] = true,
    ["client.match.surrender"] = true
  }
  self:sendClientEnvelope(envelopeType, payload, {
    critical = criticalEnvelopeTypeMap[envelopeType] == true
  })
end

function App:sendChat(text)
  self:sendEnvelope("client.chat.send", {
    text = text
  })
end

function App:handlePollFatalError(reason)
  local reasonCode = tostring(reason or "")
  if reasonCode ~= "invalid_token" and reasonCode ~= "invalid_room_code" then
    return false
  end

  local httpBase = self:getServerHttpBase(self._serverEnv)
  local statusMessage = t("app.ui.poll_session_invalid", {
    reason = reasonCode,
    env = self._serverEnv,
    base = httpBase
  })

  self:networkLog("POLL_FATAL", {
    reason = reasonCode,
    roomCode = self._session.roomCode,
    token = shortToken(self._session.token),
    cursor = self._poll.cursor,
    serverEnv = self._serverEnv,
    httpBase = httpBase
  })

  self:stopPolling(reasonCode)
  self._session = {
    roomCode = nil,
    token = nil,
    role = nil,
    serverRulesVersion = nil,
    lastRoomState = nil
  }

  self:emitUiStatus(statusMessage, Constants.COLOR_DANGER)
  self:goLobby({
    statusText = statusMessage,
    statusColor = Constants.COLOR_DANGER
  }, Config.TRANSITION_BACK)

  return true
end

function App:leaveRoom()
  self:sendClientEnvelope("client.room.leave", {}, {
    silent = true
  })
  self:stopPolling("leave_room")
  self._session = {
    roomCode = nil,
    token = nil,
    role = nil,
    serverRulesVersion = nil,
    lastRoomState = nil
  }
end

function App:handleHttpResponse(event, sourceTag)
  local source = sourceTag or "main"
  local requestKey = source .. ":" .. tostring(event.requestId)
  local requestMeta = self._pendingHttpMap[requestKey]
  if not requestMeta then
    return
  end
  self._pendingHttpMap[requestKey] = nil

  local bodyTable = {}
  if event.body and event.body ~= "" then
    local isDecoded, parsed = pcall(Json.decode, event.body)
    if isDecoded and type(parsed) == "table" then
      bodyTable = parsed
    else
      self:playSoundHook("http_parse_error")
      self:emitUiStatus(t("app.ui.response_parse_failed"), Constants.COLOR_DANGER)
      return
    end
  end

  local requestOk = event.ok and bodyTable.ok
  if requestMeta.kind == "createRoom" or requestMeta.kind == "joinRoom" then
    if not requestOk then
      self:playSoundHook("http_error")
      local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
      self:emitUiStatus(t("app.ui.request_failed", {
        reason = reason
      }), Constants.COLOR_DANGER)
      return
    end
    self._session.roomCode = bodyTable.roomCode
    self._session.token = bodyTable.token
    self._session.role = nil
    self._session.lastRoomState = nil
    self:checkRulesVersion(bodyTable.rulesVersion)

    if requestMeta.kind == "createRoom" then
      self:playSoundHook("room_create_success")
    else
      self:playSoundHook("room_join_success")
    end
    self:goWaitingRoom(nil, Config.TRANSITION_FORWARD)
    self:startPolling()
    return
  end

  if requestMeta.kind == "poll" then
    local isValidPollResponse = requestOk and type(bodyTable.nextCursor) == "number" and type(bodyTable.events) == "table"
    self:networkLog("POLL_RESPONSE", {
      requestId = tostring(event.requestId),
      httpOk = event.ok == true,
      httpStatus = event.status,
      transportError = event.error,
      bodyOk = bodyTable.ok,
      bodyError = bodyTable.error,
      nextCursor = bodyTable.nextCursor,
      eventsCount = type(bodyTable.events) == "table" and #bodyTable.events or nil,
      generation = requestMeta.generation,
      activeGeneration = self._poll.generation,
      activeRoomCode = self._session.roomCode,
      activeToken = shortToken(self._session.token),
      inFlightRequestId = tostring(self._poll.inFlightRequestId or ""),
      serverEnv = self._serverEnv,
      httpBase = self:getServerHttpBase(self._serverEnv)
    })
    if requestMeta.generation ~= self._poll.generation then
      return
    end
    if self._poll.inFlightRequestId == event.requestId then
      self._poll.inFlightRequestId = nil
    end
    if not isValidPollResponse then
      local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
      local currentBackoff = self._poll.backoffMs
      if currentBackoff <= 0 then
        currentBackoff = Constants.NETWORK_POLL_BACKOFF_INITIAL_MS
      else
        currentBackoff = math.min(currentBackoff * 2, Constants.NETWORK_POLL_BACKOFF_MAX_MS)
      end
      self._poll.backoffMs = currentBackoff
      local jitterRatio = Constants.NETWORK_POLL_BACKOFF_JITTER_RATIO
      local jitter = (math.random() * 2 - 1) * jitterRatio * currentBackoff
      local waitMs = math.max(0, math.floor(currentBackoff + jitter))
      self._poll.nextPollAtMs = self:getNowMs() + waitMs
      self:playSoundHook(NETWORK_EVENT_SOUND_HOOK_MAP.server_error)
      self._sceneManager:dispatch("onAppEvent", {
        type = "server_error",
        message = reason
      })
      self:networkLog("POLL_RESPONSE_INVALID", {
        requestId = tostring(event.requestId),
        reason = tostring(reason),
        retryBackoffMs = self._poll.backoffMs,
        nextPollAtMs = self._poll.nextPollAtMs,
        roomCode = self._session.roomCode,
        token = shortToken(self._session.token),
        cursor = self._poll.cursor,
        serverEnv = self._serverEnv,
        httpBase = self:getServerHttpBase(self._serverEnv)
      })
      if self:handlePollFatalError(reason) then
        return
      end
      return
    end

    self._poll.backoffMs = 0
    self._poll.cursor = bodyTable.nextCursor
    self._poll.nextPollAtMs = self:getNowMs()

    for _, envelope in ipairs(bodyTable.events) do
      if type(envelope) == "table" and type(envelope.type) == "string" then
        self:handleServerEnvelope(envelope)
      end
    end
    return
  end

  if requestMeta.kind == "sendEnvelope" then
    if requestOk then
      return
    end
    local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
    if self:handlePollFatalError(reason) then
      return
    end
    local retryCount = requestMeta.retryCount or 0
    local maxRetry = requestMeta.maxRetry or 0
    local canRetry = requestMeta.critical == true and retryCount < maxRetry and self._session.roomCode and self._session.token
    if canRetry then
      self:requestSendEnvelope(requestMeta.envelopeType, requestMeta.payload, {
        critical = true,
        retryCount = retryCount + 1,
        maxRetry = maxRetry,
        silent = requestMeta.silent == true
      })
      return
    end
    if requestMeta.silent ~= true then
      self:emitUiStatus(t("app.ui.request_failed", {
        reason = reason
      }), Constants.COLOR_DANGER)
    end
    return
  end

  if not requestOk then
    self:playSoundHook("http_error")
    local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
    self:emitUiStatus(t("app.ui.request_failed", {
      reason = reason
    }), Constants.COLOR_DANGER)
  end
end

function App:handleServerEnvelope(envelope)
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
    self:stopPolling("room_closed")
    self._session = {
      roomCode = nil,
      token = nil,
      role = nil,
      serverRulesVersion = nil,
      lastRoomState = nil
    }
  end
  if not shouldDispatch then
    return
  end
  self._sceneManager:dispatch("onAppEvent", {
    type = "server_envelope",
    envelope = envelope
  })
end

function App:issuePollRequest(nowMs)
  if not self._poll.isActive then
    return
  end
  if self._poll.inFlightRequestId ~= nil then
    return
  end
  if not self._session.roomCode or not self._session.token then
    return
  end
  local nowValue = nowMs or self:getNowMs()
  if nowValue < (self._poll.nextPollAtMs or 0) then
    return
  end

  local requestId = self._pollHttpClient:request("POST", self:buildHttpUrl("/room/poll"), {
    roomCode = self._session.roomCode,
    token = self._session.token,
    cursor = self._poll.cursor,
    timeoutMs = Constants.NETWORK_POLL_TIMEOUT_MS
  }, {
    ["content-type"] = "application/json"
  })
  self._poll.inFlightRequestId = requestId
  self._poll.lastIssued = {
    requestId = requestId,
    roomCode = self._session.roomCode,
    token = shortToken(self._session.token),
    cursor = self._poll.cursor,
    timeoutMs = Constants.NETWORK_POLL_TIMEOUT_MS,
    issuedAtMs = nowValue,
    generation = self._poll.generation,
    serverEnv = self._serverEnv,
    httpBase = self:getServerHttpBase(self._serverEnv)
  }
  self:networkLog("POLL_REQUEST", self._poll.lastIssued)
  self._pendingHttpMap["poll:" .. requestId] = {
    kind = "poll",
    generation = self._poll.generation
  }
end

function App:pollNetworkEvents()
  local httpEvents = self._httpClient:pollEvents(30)
  for _, event in ipairs(httpEvents) do
    if event.type == "response" then
      self:handleHttpResponse(event, "main")
    end
  end
  local pollEvents = self._pollHttpClient:pollEvents(8)
  for _, event in ipairs(pollEvents) do
    if event.type == "response" then
      self:handleHttpResponse(event, "poll")
    end
  end
  self:issuePollRequest(self:getNowMs())
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
  self:stopPolling("shutdown")
  self._httpClient:shutdown()
  self._pollHttpClient:shutdown()
end

return App
