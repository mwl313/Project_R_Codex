--[[
파일명: ws_worker.lua
모듈명: WsWorker

역할:
- WebSocket 연결/송수신 처리 전용 스레드
- 텍스트 프레임 기반 이벤트를 메인 스레드로 전달

외부에서 사용 가능한 함수:
- 스레드 진입 시 자동 실행

주의:
- ws:// 프로토콜만 지원한다 (wss 미지원)
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

local hasSocket, socketModule = pcall(require, "socket")
local hasBit, bitModule = pcall(require, "bit")
if not hasBit then
  hasBit, bitModule = pcall(require, "bit32")
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

  if hasSocket and socketModule and socketModule.sleep then
    local isOk = pcall(socketModule.sleep, safeDurationSec)
    if isOk then
      return
    end
  end

  local targetMs = nowMs() + safeMs
  while nowMs() < targetMs do
  end
end

math.randomseed(os.time() + math.floor(nowMs()))

local function pushEvent(eventTable)
  eventChannel:push(Json.encode(eventTable))
end

local function parseWsUrl(url)
  if type(url) ~= "string" then
    return nil, "invalid_url"
  end
  local host, portText, path = url:match("^ws://([^:/]+):?(%d*)(/?.*)$")
  if not host then
    return nil, "only_ws_protocol_supported"
  end
  local port = tonumber(portText)
  if not port then
    port = 80
  end
  if not path or path == "" then
    path = "/"
  end
  return {
    host = host,
    port = port,
    path = path
  }
end

local base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function toBase64(binaryText)
  local result = {}
  local length = #binaryText
  local index = 1

  while index <= length do
    local a = binaryText:byte(index) or 0
    local b = binaryText:byte(index + 1) or 0
    local c = binaryText:byte(index + 2) or 0
    local triple = a * 65536 + b * 256 + c

    local first = math.floor(triple / 262144) % 64 + 1
    local second = math.floor(triple / 4096) % 64 + 1
    local third = math.floor(triple / 64) % 64 + 1
    local fourth = triple % 64 + 1

    result[#result + 1] = base64Alphabet:sub(first, first)
    result[#result + 1] = base64Alphabet:sub(second, second)
    result[#result + 1] = index + 1 <= length and base64Alphabet:sub(third, third) or "="
    result[#result + 1] = index + 2 <= length and base64Alphabet:sub(fourth, fourth) or "="

    index = index + 3
  end

  return table.concat(result)
end

local function generateSecKey()
  local bytes = {}
  for index = 1, 16 do
    bytes[index] = string.char(math.random(0, 255))
  end
  return toBase64(table.concat(bytes))
end

local function buildHandshakeRequest(connectionInfo, secKey)
  return table.concat({
    "GET " .. connectionInfo.path .. " HTTP/1.1\r\n",
    "Host: " .. connectionInfo.host .. ":" .. tostring(connectionInfo.port) .. "\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    "Sec-WebSocket-Key: " .. secKey .. "\r\n",
    "Sec-WebSocket-Version: 13\r\n",
    "\r\n"
  })
end

local function receiveHttpHeaders(tcpSocket)
  local statusLine, statusError = tcpSocket:receive("*l")
  if not statusLine then
    return nil, statusError or "handshake_failed"
  end

  local headerLines = {}
  while true do
    local line, lineError = tcpSocket:receive("*l")
    if not line then
      return nil, lineError or "handshake_failed"
    end
    if line == "" then
      break
    end
    headerLines[#headerLines + 1] = line
  end
  return {
    statusLine = statusLine,
    headerLines = headerLines
  }, nil
end

local bxor = hasBit and bitModule.bxor or nil
local band = hasBit and bitModule.band or nil
local rshift = hasBit and bitModule.rshift or nil

local function buildMaskedFrame(opcode, payload)
  local payloadText = payload or ""
  local payloadLength = #payloadText

  local header = { string.char(0x80 + opcode) }
  if payloadLength < 126 then
    header[#header + 1] = string.char(0x80 + payloadLength)
  elseif payloadLength < 65536 then
    header[#header + 1] = string.char(0x80 + 126)
    header[#header + 1] = string.char(math.floor(payloadLength / 256) % 256)
    header[#header + 1] = string.char(payloadLength % 256)
  else
    header[#header + 1] = string.char(0x80 + 127)
    for index = 7, 0, -1 do
      local value = math.floor(payloadLength / (2 ^ (8 * index))) % 256
      header[#header + 1] = string.char(value)
    end
  end

  local maskBytes = {
    math.random(0, 255),
    math.random(0, 255),
    math.random(0, 255),
    math.random(0, 255)
  }
  header[#header + 1] = string.char(maskBytes[1], maskBytes[2], maskBytes[3], maskBytes[4])

  local maskedParts = {}
  for index = 1, payloadLength do
    local sourceByte = payloadText:byte(index)
    local maskByte = maskBytes[((index - 1) % 4) + 1]
    maskedParts[index] = string.char(bxor(sourceByte, maskByte))
  end

  return table.concat(header) .. table.concat(maskedParts)
end

local function parseNextFrame(bufferText)
  if #bufferText < 2 then
    return nil, 0
  end

  local first = bufferText:byte(1)
  local second = bufferText:byte(2)
  local opcode = band(first, 0x0F)
  local hasMask = band(second, 0x80) ~= 0
  local payloadLength = band(second, 0x7F)
  local index = 3

  if payloadLength == 126 then
    if #bufferText < 4 then
      return nil, 0
    end
    local byte1 = bufferText:byte(3)
    local byte2 = bufferText:byte(4)
    payloadLength = byte1 * 256 + byte2
    index = 5
  elseif payloadLength == 127 then
    if #bufferText < 10 then
      return nil, 0
    end
    payloadLength = 0
    for i = 3, 10 do
      payloadLength = payloadLength * 256 + bufferText:byte(i)
    end
    index = 11
  end

  local maskBytes
  if hasMask then
    if #bufferText < index + 3 then
      return nil, 0
    end
    maskBytes = {
      bufferText:byte(index),
      bufferText:byte(index + 1),
      bufferText:byte(index + 2),
      bufferText:byte(index + 3)
    }
    index = index + 4
  end

  local payloadLastIndex = index + payloadLength - 1
  if #bufferText < payloadLastIndex then
    return nil, 0
  end

  local payloadText = ""
  if payloadLength > 0 then
    payloadText = bufferText:sub(index, payloadLastIndex)
    if hasMask then
      local unmaskedParts = {}
      for charIndex = 1, #payloadText do
        local sourceByte = payloadText:byte(charIndex)
        local maskByte = maskBytes[((charIndex - 1) % 4) + 1]
        unmaskedParts[charIndex] = string.char(bxor(sourceByte, maskByte))
      end
      payloadText = table.concat(unmaskedParts)
    end
  end

  return {
    opcode = opcode,
    payload = payloadText
  }, payloadLastIndex
end

local tcpSocket = nil
local isConnected = false
local receiveBuffer = ""

local function closeSocketOnly()
  if tcpSocket then
    pcall(function()
      tcpSocket:close()
    end)
    tcpSocket = nil
  end
end

local function notifyClosed(reason)
  if isConnected then
    pushEvent({
      type = "ws_close",
      reason = reason or "closed"
    })
  end
  isConnected = false
end

local function disconnectSocket(reason, shouldNotify)
  if tcpSocket and isConnected then
    pcall(function()
      tcpSocket:send(buildMaskedFrame(0x8, ""))
    end)
  end
  closeSocketOnly()
  receiveBuffer = ""
  if shouldNotify ~= false then
    notifyClosed(reason or "closed")
  else
    isConnected = false
  end
end

local function connectSocket(url)
  if not hasSocket then
    pushEvent({
      type = "ws_error",
      message = "socket_module_not_available"
    })
    return
  end
  if not hasBit then
    pushEvent({
      type = "ws_error",
      message = "bit_module_not_available"
    })
    return
  end

  local info, parseError = parseWsUrl(url)
  if not info then
    pushEvent({
      type = "ws_error",
      message = parseError
    })
    return
  end

  disconnectSocket("reconnect", false)

  local socketValue = socketModule.tcp()
  if not socketValue then
    pushEvent({
      type = "ws_error",
      message = "tcp_create_failed"
    })
    return
  end

  socketValue:settimeout(5)
  local isSuccess, connectError = socketValue:connect(info.host, info.port)
  if not isSuccess then
    socketValue:close()
    pushEvent({
      type = "ws_error",
      message = "connect_failed:" .. tostring(connectError)
    })
    return
  end

  local secKey = generateSecKey()
  local requestText = buildHandshakeRequest(info, secKey)
  local sendOk, sendError = socketValue:send(requestText)
  if not sendOk then
    socketValue:close()
    pushEvent({
      type = "ws_error",
      message = "handshake_send_failed:" .. tostring(sendError)
    })
    return
  end

  local handshake, handshakeError = receiveHttpHeaders(socketValue)
  if not handshake then
    socketValue:close()
    pushEvent({
      type = "ws_error",
      message = "handshake_failed:" .. tostring(handshakeError)
    })
    return
  end
  if not handshake.statusLine:find("101", 1, true) then
    socketValue:close()
    pushEvent({
      type = "ws_error",
      message = "handshake_status_not_101:" .. handshake.statusLine
    })
    return
  end

  socketValue:settimeout(0)
  tcpSocket = socketValue
  receiveBuffer = ""
  isConnected = true

  pushEvent({
    type = "ws_open",
    url = url
  })
end

local function sendFrame(opcode, payloadText)
  if not tcpSocket or not isConnected then
    return
  end
  local frameText = buildMaskedFrame(opcode, payloadText or "")
  local isSent, sendError = tcpSocket:send(frameText)
  if not isSent and sendError ~= "timeout" then
    pushEvent({
      type = "ws_error",
      message = "send_failed:" .. tostring(sendError)
    })
    disconnectSocket("send_failed", true)
  end
end

local function handleFrame(frame)
  if frame.opcode == 0x1 then
    pushEvent({
      type = "ws_message",
      text = frame.payload
    })
  elseif frame.opcode == 0x8 then
    disconnectSocket("remote_close", true)
  elseif frame.opcode == 0x9 then
    sendFrame(0xA, frame.payload)
  elseif frame.opcode == 0xA then
    -- pong
  end
end

local function pumpSocketRead()
  if not tcpSocket or not isConnected then
    return
  end

  while true do
    local chunk, receiveError, partial = tcpSocket:receive(2048)
    local data = chunk or partial
    if data and #data > 0 then
      receiveBuffer = receiveBuffer .. data
    end

    if receiveError == "closed" then
      disconnectSocket("remote_closed", true)
      return
    end
    if receiveError == "timeout" or not receiveError then
      break
    end
    if receiveError then
      pushEvent({
        type = "ws_error",
        message = "receive_failed:" .. tostring(receiveError)
      })
      disconnectSocket("receive_failed", true)
      return
    end
  end

  while true do
    local frame, consumedLength = parseNextFrame(receiveBuffer)
    if not frame or consumedLength <= 0 then
      break
    end
    receiveBuffer = receiveBuffer:sub(consumedLength + 1)
    handleFrame(frame)
  end
end

local isRunning = true
while isRunning do
  local commandRaw = commandChannel:pop()
  if commandRaw then
    local isDecoded, command = pcall(Json.decode, commandRaw)
    if isDecoded and command then
      if command.type == "connect" then
        connectSocket(command.url)
      elseif command.type == "send" then
        sendFrame(0x1, command.payload or "")
      elseif command.type == "disconnect" then
        disconnectSocket("client_disconnect", true)
      elseif command.type == "shutdown" then
        isRunning = false
      end
    end
  end

  pumpSocketRead()
  sleepMs(10)
end

disconnectSocket("shutdown", false)
