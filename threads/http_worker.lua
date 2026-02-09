--[[
파일명: http_worker.lua
모듈명: HttpWorker

역할:
- HttpClient 전용 백그라운드 스레드
- blocking HTTP를 워커 스레드에서 수행 후 이벤트 반환

외부에서 사용 가능한 함수:
- 스레드 진입 시 자동 실행

주의:
- 메인 스레드로 직접 접근하지 않는다
]]

local Json = require("utils.json")

local commandChannelName = ...
local eventChannelName = select(2, ...)

local commandChannel = love.thread.getChannel(commandChannelName)
local eventChannel = love.thread.getChannel(eventChannelName)

local hasLoveTimer, loveTimerModule = pcall(require, "love.timer")
if not hasLoveTimer then
  loveTimerModule = nil
end

local canUseSocket = false
local httpModule
local ltn12Module
local socketModule

do
  local hasSocket, socketValue = pcall(require, "socket")
  local hasHttp, httpValue = pcall(require, "socket.http")
  local hasLtn12, ltn12Value = pcall(require, "ltn12")
  if hasSocket then
    socketModule = socketValue
  end
  if hasHttp and hasLtn12 then
    canUseSocket = true
    httpModule = httpValue
    ltn12Module = ltn12Value
  end
end

local function nowMs()
  if loveTimerModule and loveTimerModule.getTime then
    local isOk, value = pcall(loveTimerModule.getTime)
    if isOk and type(value) == "number" then
      return value * 1000
    end
  end
  return os.clock() * 1000
end

local function sleepMs(durationMs)
  local safeMs = tonumber(durationMs) or 0
  if safeMs <= 0 then
    return
  end
  local safeDurationSec = safeMs / 1000

  if loveTimerModule and loveTimerModule.sleep then
    local isOk = pcall(loveTimerModule.sleep, safeDurationSec)
    if isOk then
      return
    end
  end

  if socketModule and socketModule.sleep then
    local isOk = pcall(socketModule.sleep, safeDurationSec)
    if isOk then
      return
    end
  end

  local targetMs = nowMs() + safeMs
  while nowMs() < targetMs do
  end
end

local function pushEvent(eventTable)
  eventChannel:push(Json.encode(eventTable))
end

local function buildResultFromError(requestId, errorMessage)
  return {
    type = "response",
    requestId = requestId,
    ok = false,
    status = 0,
    body = "",
    error = errorMessage
  }
end

local function executeRequest(command)
  if not canUseSocket then
    return buildResultFromError(command.requestId, "socket.http_not_available")
  end

  local responseChunks = {}
  local headers = command.headers or {}
  if command.body then
    headers["content-type"] = headers["content-type"] or "application/json"
    headers["content-length"] = tostring(#command.body)
  end

  local requestTable = {
    url = command.url,
    method = command.method,
    headers = headers,
    sink = ltn12Module.sink.table(responseChunks)
  }

  if command.body then
    requestTable.source = ltn12Module.source.string(command.body)
  end

  local _, statusCode, _, statusLine = httpModule.request(requestTable)
  local responseBody = table.concat(responseChunks)
  local codeNumber = tonumber(statusCode) or 0
  local isOk = codeNumber >= 200 and codeNumber < 300

  return {
    type = "response",
    requestId = command.requestId,
    ok = isOk,
    status = codeNumber,
    body = responseBody,
    error = isOk and nil or (statusLine or "http_error")
  }
end

local isRunning = true
while isRunning do
  local commandRaw = commandChannel:pop()
  if not commandRaw then
    sleepMs(10)
  else
    local isDecoded, command = pcall(Json.decode, commandRaw)
    if isDecoded and command then
      if command.type == "shutdown" then
        isRunning = false
      elseif command.type == "request" then
        local isSuccess, response = pcall(executeRequest, command)
        if isSuccess then
          pushEvent(response)
        else
          pushEvent(buildResultFromError(command.requestId, response))
        end
      end
    end
  end
end
