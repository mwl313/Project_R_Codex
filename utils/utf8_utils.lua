--[[
파일명: utf8_utils.lua
모듈명: Utf8Utils

역할:
- UTF-8 안전 문자열 편집 유틸 제공
- 백스페이스 처리 시 멀티바이트 손상 방지
- utf8 의존성 브릿지(love.utf8 우선) 제공

외부에서 사용 가능한 함수:
- Utf8Utils.removeLast(text)

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

return Utf8Utils
