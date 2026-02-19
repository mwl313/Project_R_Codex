--[[
파일명: ws_worker.lua
모듈명: WsWorker

역할:
- WebSocket 연결/송수신 처리 전용 스레드
- 텍스트 프레임 기반 이벤트를 메인 스레드로 전달

외부에서 사용 가능한 함수:
- 스레드 진입 시 자동 실행

주의:
- ws://, wss:// 프로토콜을 지원한다
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
local hasSsl, sslModule = pcall(require, "ssl")
local hasBit, bitModule = pcall(require, "bit")
if not hasBit then
  hasBit, bitModule = pcall(require, "bit32")
end

local bxor = hasBit and bitModule.bxor or nil
local band = hasBit and bitModule.band or nil
local rshift = hasBit and bitModule.rshift or nil
local bor = hasBit and bitModule.bor or nil
local lshift = hasBit and bitModule.lshift or nil
local bnot = hasBit and bitModule.bnot or nil

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
    pcall(socketModule.sleep, safeDurationSec)
  end
end

math.randomseed(os.time() + math.floor(os.clock() * 1000))

local function pushEvent(eventTable)
  eventChannel:push(Json.encode(eventTable))
end

local function parseWsUrl(url)
  if type(url) ~= "string" then
    return nil, "invalid_url"
  end
  local scheme, host, portText, path = url:match("^(wss?)://([^:/]+):?(%d*)(/?.*)$")
  if not host then
    return nil, "only_ws_or_wss_protocol_supported"
  end
  local isSecure = scheme == "wss"
  local port = tonumber(portText)
  if not port then
    port = isSecure and 443 or 80
  end
  if not path or path == "" then
    path = "/"
  end
  return {
    scheme = scheme,
    isSecure = isSecure,
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

local function leftRotate32(value, bitCount)
  local safeBits = bitCount % 32
  return band(bor(lshift(value, safeBits), rshift(value, 32 - safeBits)), 0xFFFFFFFF)
end

local function sha1Binary(text)
  local bytes = { string.byte(text, 1, #text) }
  local bitLength = #bytes * 8

  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do
    bytes[#bytes + 1] = 0
  end

  local high = math.floor(bitLength / 2 ^ 32)
  local low = bitLength % 2 ^ 32
  for shift = 24, 0, -8 do
    bytes[#bytes + 1] = band(rshift(high, shift), 0xFF)
  end
  for shift = 24, 0, -8 do
    bytes[#bytes + 1] = band(rshift(low, shift), 0xFF)
  end

  local h0 = 0x67452301
  local h1 = 0xEFCDAB89
  local h2 = 0x98BADCFE
  local h3 = 0x10325476
  local h4 = 0xC3D2E1F0

  local words = {}
  for chunkStart = 1, #bytes, 64 do
    for wordIndex = 0, 15 do
      local base = chunkStart + wordIndex * 4
      words[wordIndex] = bor(
        lshift(bytes[base] or 0, 24),
        bor(lshift(bytes[base + 1] or 0, 16), bor(lshift(bytes[base + 2] or 0, 8), bytes[base + 3] or 0))
      )
    end

    for wordIndex = 16, 79 do
      words[wordIndex] = leftRotate32(
        bxor(bxor(words[wordIndex - 3], words[wordIndex - 8]), bxor(words[wordIndex - 14], words[wordIndex - 16])),
        1
      )
    end

    local a = h0
    local b = h1
    local c = h2
    local d = h3
    local e = h4

    for index = 0, 79 do
      local f
      local k
      if index <= 19 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif index <= 39 then
        f = bxor(b, bxor(c, d))
        k = 0x6ED9EBA1
      elseif index <= 59 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(b, bxor(c, d))
        k = 0xCA62C1D6
      end

      local temp = band(leftRotate32(a, 5) + f + e + k + words[index], 0xFFFFFFFF)
      e = d
      d = c
      c = leftRotate32(b, 30)
      b = a
      a = temp
    end

    h0 = band(h0 + a, 0xFFFFFFFF)
    h1 = band(h1 + b, 0xFFFFFFFF)
    h2 = band(h2 + c, 0xFFFFFFFF)
    h3 = band(h3 + d, 0xFFFFFFFF)
    h4 = band(h4 + e, 0xFFFFFFFF)
  end

  local out = {}
  local hashParts = { h0, h1, h2, h3, h4 }
  for _, part in ipairs(hashParts) do
    out[#out + 1] = string.char(band(rshift(part, 24), 0xFF))
    out[#out + 1] = string.char(band(rshift(part, 16), 0xFF))
    out[#out + 1] = string.char(band(rshift(part, 8), 0xFF))
    out[#out + 1] = string.char(band(part, 0xFF))
  end
  return table.concat(out)
end

local function buildExpectedAcceptKey(secKey)
  return toBase64(sha1Binary(secKey .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
end

local function parseHeaderMap(headerLines)
  local headerMap = {}
  for _, line in ipairs(headerLines or {}) do
    local key, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
    if key and value then
      headerMap[string.lower(key)] = value
    end
  end
  return headerMap
end

local function headerContainsToken(headerValue, targetToken)
  if type(headerValue) ~= "string" then
    return false
  end
  local target = string.lower(targetToken or "")
  for token in string.gmatch(string.lower(headerValue), "[^,]+") do
    local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == target then
      return true
    end
  end
  return false
end

local function generateSecKey()
  local bytes = {}
  for index = 1, 16 do
    bytes[index] = string.char(math.random(0, 255))
  end
  return toBase64(table.concat(bytes))
end

local function buildHandshakeRequest(connectionInfo, secKey)
  local hostHeader = connectionInfo.host
  local isDefaultPort = (connectionInfo.isSecure and connectionInfo.port == 443) or (not connectionInfo.isSecure and connectionInfo.port == 80)
  if not isDefaultPort then
    hostHeader = hostHeader .. ":" .. tostring(connectionInfo.port)
  end

  return table.concat({
    "GET " .. connectionInfo.path .. " HTTP/1.1\r\n",
    "Host: " .. hostHeader .. "\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    "Sec-WebSocket-Key: " .. secKey .. "\r\n",
    "Sec-WebSocket-Version: 13\r\n",
    "\r\n"
  })
end

local function receiveHttpHeaders(clientSocket)
  local statusLine, statusError = clientSocket:receive("*l")
  if not statusLine then
    return nil, statusError or "handshake_failed"
  end
  statusLine = statusLine:gsub("\r$", "")

  local headerLines = {}
  while true do
    local line, lineError = clientSocket:receive("*l")
    if not line then
      return nil, lineError or "handshake_failed"
    end
    line = line:gsub("\r$", "")
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

local function validateHandshake(handshake, expectedAcceptKey)
  local statusCodeText = handshake.statusLine:match("^HTTP/%d+%.%d+%s+(%d+)")
  local statusCode = tonumber(statusCodeText)
  if statusCode ~= 101 then
    return false, "handshake_status_not_101:" .. tostring(handshake.statusLine)
  end

  local headers = parseHeaderMap(handshake.headerLines)
  if not headerContainsToken(headers["upgrade"], "websocket") then
    return false, "handshake_missing_upgrade"
  end
  if not headerContainsToken(headers["connection"], "upgrade") then
    return false, "handshake_missing_connection_upgrade"
  end

  local acceptKey = headers["sec-websocket-accept"]
  if type(acceptKey) ~= "string" then
    return false, "handshake_missing_accept_key"
  end
  local normalizedAccept = acceptKey:gsub("^%s+", ""):gsub("%s+$", "")
  if normalizedAccept ~= expectedAcceptKey then
    return false, "handshake_invalid_accept_key"
  end

  return true, nil
end

local function performTlsHandshake(tlsSocket, timeoutSec)
  local deadline = os.clock() + (timeoutSec or 5)
  while true do
    local isOk, handshakeError = tlsSocket:dohandshake()
    if isOk then
      return true, nil
    end
    if handshakeError ~= "wantread" and handshakeError ~= "wantwrite" and handshakeError ~= "timeout" then
      return false, handshakeError
    end
    if os.clock() >= deadline then
      return false, "timeout"
    end
    sleepMs(10)
  end
end

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

  local rawSocket = socketModule.tcp()
  if not rawSocket then
    pushEvent({
      type = "ws_error",
      message = "tcp_create_failed"
    })
    return
  end

  rawSocket:settimeout(5)
  local isSuccess, connectError = rawSocket:connect(info.host, info.port)
  if not isSuccess then
    rawSocket:close()
    pushEvent({
      type = "ws_error",
      message = "connect_failed:" .. tostring(connectError)
    })
    return
  end

  local clientSocket = rawSocket
  if info.isSecure then
    if not hasSsl or not sslModule or not sslModule.wrap then
      rawSocket:close()
      pushEvent({
        type = "ws_error",
        message = "ssl_module_not_available"
      })
      return
    end

    local wrappedSocket, wrapError = sslModule.wrap(rawSocket, {
      mode = "client",
      protocol = "tlsv1_2",
      verify = "none",
      options = "all",
      server = info.host
    })
    if not wrappedSocket then
      rawSocket:close()
      pushEvent({
        type = "ws_error",
        message = "ssl_wrap_failed:" .. tostring(wrapError)
      })
      return
    end

    wrappedSocket:settimeout(5)
    local handshakeOk, handshakeError = performTlsHandshake(wrappedSocket, 5)
    if not handshakeOk then
      wrappedSocket:close()
      pushEvent({
        type = "ws_error",
        message = "ssl_handshake_failed:" .. tostring(handshakeError)
      })
      return
    end

    clientSocket = wrappedSocket
  end

  local secKey = generateSecKey()
  local expectedAcceptKey = buildExpectedAcceptKey(secKey)
  local requestText = buildHandshakeRequest(info, secKey)
  local sendOk, sendError = clientSocket:send(requestText)
  if not sendOk then
    clientSocket:close()
    pushEvent({
      type = "ws_error",
      message = "handshake_send_failed:" .. tostring(sendError)
    })
    return
  end

  local handshake, handshakeError = receiveHttpHeaders(clientSocket)
  if not handshake then
    clientSocket:close()
    pushEvent({
      type = "ws_error",
      message = "handshake_failed:" .. tostring(handshakeError)
    })
    return
  end

  local isHandshakeValid, handshakeValidationError = validateHandshake(handshake, expectedAcceptKey)
  if not isHandshakeValid then
    clientSocket:close()
    pushEvent({
      type = "ws_error",
      message = handshakeValidationError
    })
    return
  end

  clientSocket:settimeout(0)
  tcpSocket = clientSocket
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

    if receiveError == "timeout" then
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

    if not receiveError and (not data or #data == 0) then
      break
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

local function handleCommand(commandRaw)
  if not commandRaw then
    return
  end

  local isDecoded, command = pcall(Json.decode, commandRaw)
  if not isDecoded or type(command) ~= "table" then
    return
  end

  if command.type == "connect" then
    connectSocket(command.url)
  elseif command.type == "send" then
    sendFrame(0x1, command.payload or "")
  elseif command.type == "disconnect" then
    disconnectSocket("client_disconnect", true)
  elseif command.type == "shutdown" then
    return false
  end

  return true
end

local isRunning = true
while isRunning do
  local hadCommand = false

  while true do
    local commandRaw = commandChannel:pop()
    if not commandRaw then
      break
    end
    hadCommand = true
    local shouldContinue = handleCommand(commandRaw)
    if shouldContinue == false then
      isRunning = false
      break
    end
  end

  if not isRunning then
    break
  end

  if isConnected and tcpSocket then
    if hasSocket and socketModule and socketModule.select then
      local readableList, _, selectError = socketModule.select({ tcpSocket }, nil, 0.05)
      if selectError and selectError ~= "timeout" then
        pushEvent({
          type = "ws_error",
          message = "select_failed:" .. tostring(selectError)
        })
        disconnectSocket("select_failed", true)
      elseif readableList and #readableList > 0 then
        pumpSocketRead()
      end
    else
      pumpSocketRead()
      if not hadCommand then
        sleepMs(10)
      end
    end
  elseif not hadCommand then
    local blockingCommand = commandChannel:demand()
    local shouldContinue = handleCommand(blockingCommand)
    if shouldContinue == false then
      isRunning = false
    end
  end
end

disconnectSocket("shutdown", false)
