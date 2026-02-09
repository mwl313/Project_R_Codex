--[[
파일명: http_client.lua
모듈명: HttpClient

역할:
- HTTP 요청을 별도 스레드에서 처리
- 메인 스레드 블로킹 없이 응답 이벤트 전달

외부에서 사용 가능한 함수:
- HttpClient.new()
- HttpClient:request(method, url, bodyTable, headersTable)
- HttpClient:pollEvents(maxCount)
- HttpClient:shutdown()

주의:
- request body는 Lua table 또는 nil
]]

local Json = require("utils.json")

local HttpClient = {}
HttpClient.__index = HttpClient

local function createChannelName(prefix)
  local randomValue = math.random(100000, 999999)
  return string.format("%s_%d_%d", prefix, os.time(), randomValue)
end

function HttpClient.new()
  local commandChannelName = createChannelName("http_command")
  local eventChannelName = createChannelName("http_event")

  local instance = {
    _commandChannelName = commandChannelName,
    _eventChannelName = eventChannelName,
    _commandChannel = love.thread.getChannel(commandChannelName),
    _eventChannel = love.thread.getChannel(eventChannelName),
    _thread = love.thread.newThread("threads/http_worker.lua"),
    _nextRequestId = 1
  }
  setmetatable(instance, HttpClient)

  instance._thread:start(commandChannelName, eventChannelName)
  return instance
end

function HttpClient:request(method, url, bodyTable, headersTable)
  local requestId = tostring(self._nextRequestId)
  self._nextRequestId = self._nextRequestId + 1

  local command = {
    type = "request",
    requestId = requestId,
    method = method,
    url = url,
    body = bodyTable and Json.encode(bodyTable) or nil,
    headers = headersTable or {}
  }
  self._commandChannel:push(Json.encode(command))
  return requestId
end

function HttpClient:pollEvents(maxCount)
  local eventList = {}
  local readCount = 0
  local safeMax = maxCount or 20

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

function HttpClient:shutdown()
  self._commandChannel:push(Json.encode({ type = "shutdown" }))
end

return HttpClient
