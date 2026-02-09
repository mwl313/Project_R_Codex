--[[
파일명: ws_client.lua
모듈명: WsClient

역할:
- WebSocket 연결/송수신을 별도 스레드에서 처리
- 메인 스레드에 이벤트 큐 형태로 전달

외부에서 사용 가능한 함수:
- WsClient.new()
- WsClient:connect(url)
- WsClient:sendEnvelope(envelopeTable)
- WsClient:disconnect()
- WsClient:pollEvents(maxCount)
- WsClient:shutdown()

주의:
- envelopeTable은 Json.encode 가능한 테이블이어야 한다
]]

local Json = require("utils.json")

local WsClient = {}
WsClient.__index = WsClient

local function createChannelName(prefix)
  local randomValue = math.random(100000, 999999)
  return string.format("%s_%d_%d", prefix, os.time(), randomValue)
end

function WsClient.new()
  local commandChannelName = createChannelName("ws_command")
  local eventChannelName = createChannelName("ws_event")

  local instance = {
    _commandChannelName = commandChannelName,
    _eventChannelName = eventChannelName,
    _commandChannel = love.thread.getChannel(commandChannelName),
    _eventChannel = love.thread.getChannel(eventChannelName),
    _thread = love.thread.newThread("threads/ws_worker.lua")
  }
  setmetatable(instance, WsClient)

  instance._thread:start(commandChannelName, eventChannelName)
  return instance
end

function WsClient:connect(url)
  self._commandChannel:push(Json.encode({
    type = "connect",
    url = url
  }))
end

function WsClient:sendEnvelope(envelopeTable)
  self._commandChannel:push(Json.encode({
    type = "send",
    payload = Json.encode(envelopeTable)
  }))
end

function WsClient:disconnect()
  self._commandChannel:push(Json.encode({
    type = "disconnect"
  }))
end

function WsClient:pollEvents(maxCount)
  local eventList = {}
  local readCount = 0
  local safeMax = maxCount or 40

  while readCount < safeMax do
    local eventRaw = self._eventChannel:pop()
    if not eventRaw then
      break
    end
    local isDecoded, eventValue = pcall(Json.decode, eventRaw)
    if isDecoded and eventValue then
      eventList[#eventList + 1] = eventValue
      readCount = readCount + 1
    end
  end

  return eventList
end

function WsClient:shutdown()
  self._commandChannel:push(Json.encode({
    type = "shutdown"
  }))
end

return WsClient
