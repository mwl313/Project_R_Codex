--[[
파일명: utf8_utils.lua
모듈명: Utf8Utils

역할:
- UTF-8 안전 문자열 편집 유틸 제공
- 백스페이스 처리 시 멀티바이트 손상 방지
- utf8 의존성 브릿지(love.utf8 우선) 제공

외부에서 사용 가능한 함수:
- Utf8Utils.removeLast(text)
- Utf8Utils.truncateToLength(text, maxChars)
- Utf8Utils.length(text)
- Utf8Utils.splitAt(text, charIndex)

주의:
- utf8 모듈이 없는 환경에서도 절대 크래시하지 않아야 한다
]]

local Utf8Utils = {}
local utfModule = nil

do
  if love and love.utf8 then
    utfModule = love.utf8
  else
    local isLoaded, moduleValue = pcall(require, "utf8")
    if isLoaded then
      utfModule = moduleValue
    end
  end
end

local function removeLastWithFallback(textValue)
  local length = #textValue
  if length <= 1 then
    return ""
  end
  return string.sub(textValue, 1, length - 1)
end

local function truncateWithFallback(textValue, maxChars)
  if maxChars <= 0 then
    return ""
  end
  if #textValue <= maxChars then
    return textValue
  end
  return string.sub(textValue, 1, maxChars)
end

function Utf8Utils.removeLast(text)
  local textValue = type(text) == "string" and text or ""
  if textValue == "" then
    return ""
  end

  if utfModule and type(utfModule.offset) == "function" then
    local isOk, offset = pcall(utfModule.offset, textValue, -1)
    if isOk and type(offset) == "number" then
      return string.sub(textValue, 1, offset - 1)
    end
    return ""
  end

  return removeLastWithFallback(textValue)
end

function Utf8Utils.truncateToLength(text, maxChars)
  local textValue = type(text) == "string" and text or ""
  local safeMax = tonumber(maxChars) or 0
  if safeMax <= 0 then
    return ""
  end
  if textValue == "" then
    return ""
  end

  if utfModule and type(utfModule.offset) == "function" then
    local isOk, offset = pcall(utfModule.offset, textValue, safeMax + 1)
    if isOk and type(offset) == "number" then
      return string.sub(textValue, 1, offset - 1)
    end
  end

  return truncateWithFallback(textValue, safeMax)
end

function Utf8Utils.length(text)
  local textValue = type(text) == "string" and text or ""
  if textValue == "" then
    return 0
  end

  if utfModule and type(utfModule.len) == "function" then
    local isOk, lengthValue = pcall(utfModule.len, textValue)
    if isOk and type(lengthValue) == "number" then
      return math.max(0, lengthValue)
    end
  end

  return #textValue
end

function Utf8Utils.splitAt(text, charIndex)
  local textValue = type(text) == "string" and text or ""
  local totalLength = Utf8Utils.length(textValue)
  local safeIndex = tonumber(charIndex) or 0
  safeIndex = math.floor(safeIndex)
  if safeIndex <= 0 then
    return "", textValue
  end
  if safeIndex >= totalLength then
    return textValue, ""
  end

  if utfModule and type(utfModule.offset) == "function" then
    local isOk, byteOffset = pcall(utfModule.offset, textValue, safeIndex + 1)
    if isOk and type(byteOffset) == "number" then
      return string.sub(textValue, 1, byteOffset - 1), string.sub(textValue, byteOffset)
    end
  end

  return string.sub(textValue, 1, safeIndex), string.sub(textValue, safeIndex + 1)
end

return Utf8Utils
