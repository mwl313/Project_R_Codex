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
    end
  }
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

function App.new(renderScale)
  local instance = {
    _renderScale = renderScale,
    _httpClient = HttpClient.new(),
    _wsClient = WsClient.new(),
    _sceneManager = nil,
    _pendingHttpMap = {},
    _session = {
      roomCode = nil,
      token = nil,
      wsUrl = nil,
      role = nil
    },
    _nickname = "Player",
    _fontWarningText = FontManager.getWarningMessage(),
    _worldMouseX = 0,
    _worldMouseY = 0
  }
  setmetatable(instance, App)

  instance._sceneManager = SceneManager.new(createSceneFactoryTable(), instance)
  instance._sceneManager:setScene("lobby")
  return instance
end

function App:getNickname()
  return self._nickname
end

function App:setNickname(nickname)
  self._nickname = nickname
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
  local requestId = self._httpClient:request("POST", self:buildHttpUrl("/room/create"), {
    nickname = self._nickname
  }, {
    ["content-type"] = "application/json"
  })
  self._pendingHttpMap[requestId] = { kind = "createRoom" }
end

function App:joinRoom(roomCode)
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
      self:emitUiStatus("응답 파싱 실패", Constants.COLOR_DANGER)
      return
    end
  end

  if not event.ok or not bodyTable.ok then
    local reason = bodyTable.error or event.error or ("http_status_" .. tostring(event.status))
    self:emitUiStatus("요청 실패: " .. tostring(reason), Constants.COLOR_DANGER)
    return
  end

  self._session.roomCode = bodyTable.roomCode
  self._session.token = bodyTable.token
  self._session.wsUrl = bodyTable.wsUrl
  self._session.role = nil

  if requestMeta.kind == "createRoom" or requestMeta.kind == "joinRoom" then
    self:goWaitingRoom()
    self:connectWebSocket()
  end
end

function App:handleWsEnvelope(envelope)
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
        self:emitUiStatus("WS 메시지 파싱 실패", Constants.COLOR_DANGER)
      end
    else
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
  self._httpClient:shutdown()
  self._wsClient:shutdown()
end

return App
