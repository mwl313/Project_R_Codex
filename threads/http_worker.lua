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

local canUseSocket = false
local httpModule
local ltn12Module

local hasHttp, httpValue = pcall(require, "socket.http")
local hasLtn12, ltn12Value = pcall(require, "ltn12")
if hasHttp and hasLtn12 then
  canUseSocket = true
  httpModule = httpValue
  ltn12Module = ltn12Value
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

local function handleCommand(commandRaw)
  local isDecoded, command = pcall(Json.decode, commandRaw)
  if not isDecoded or type(command) ~= "table" then
    return true
  end

  if command.type == "shutdown" then
    return false
  end

  if command.type == "request" then
    local isSuccess, response = pcall(executeRequest, command)
    if isSuccess then
      pushEvent(response)
    else
      pushEvent(buildResultFromError(command.requestId, response))
    end
  end

  return true
end

local isRunning = true
while isRunning do
  local commandRaw = commandChannel:demand()
  if commandRaw then
    local shouldContinue = handleCommand(commandRaw)
    if shouldContinue == false then
      isRunning = false
    end
  end
end
