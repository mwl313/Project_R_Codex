--[[
파일명: json.lua
모듈명: Json

역할:
- JSON encode/decode 제공
- 네트워크 payload 직렬화/역직렬화 담당

외부에서 사용 가능한 함수:
- Json.encode(value)
- Json.decode(text)

주의:
- Phase 2에서 필요한 JSON 타입(object/array/string/number/bool/null)만 지원
]]

local Json = {}

local function isArray(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end

  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

local function escapeString(value)
  local escaped = value
  escaped = escaped:gsub("\\", "\\\\")
  escaped = escaped:gsub("\"", "\\\"")
  escaped = escaped:gsub("\b", "\\b")
  escaped = escaped:gsub("\f", "\\f")
  escaped = escaped:gsub("\n", "\\n")
  escaped = escaped:gsub("\r", "\\r")
  escaped = escaped:gsub("\t", "\\t")
  return "\"" .. escaped .. "\""
end

local function encodeValue(value)
  local valueType = type(value)
  if valueType == "nil" then
    return "null"
  end
  if valueType == "boolean" then
    return value and "true" or "false"
  end
  if valueType == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("Invalid number for JSON encode")
    end
    return tostring(value)
  end
  if valueType == "string" then
    return escapeString(value)
  end
  if valueType == "table" then
    if isArray(value) then
      local partList = {}
      for index = 1, #value do
        partList[#partList + 1] = encodeValue(value[index])
      end
      return "[" .. table.concat(partList, ",") .. "]"
    end

    local partList = {}
    for key, item in pairs(value) do
      if type(key) ~= "string" then
        error("Object key must be string")
      end
      partList[#partList + 1] = escapeString(key) .. ":" .. encodeValue(item)
    end
    return "{" .. table.concat(partList, ",") .. "}"
  end

  error("Unsupported type for JSON encode: " .. valueType)
end

function Json.encode(value)
  return encodeValue(value)
end

local function decodeError(text, index, message)
  error("JSON decode error at " .. tostring(index) .. ": " .. message .. " near " .. text:sub(index, index + 20))
end

local function skipWhitespace(text, index)
  while true do
    local character = text:sub(index, index)
    if character == " " or character == "\t" or character == "\n" or character == "\r" then
      index = index + 1
    else
      return index
    end
  end
end

local decodeValue

local function decodeString(text, index)
  index = index + 1
  local partList = {}

  while index <= #text do
    local character = text:sub(index, index)
    if character == "\"" then
      return table.concat(partList), index + 1
    end
    if character == "\\" then
      local escaped = text:sub(index + 1, index + 1)
      if escaped == "\"" or escaped == "\\" or escaped == "/" then
        partList[#partList + 1] = escaped
      elseif escaped == "b" then
        partList[#partList + 1] = "\b"
      elseif escaped == "f" then
        partList[#partList + 1] = "\f"
      elseif escaped == "n" then
        partList[#partList + 1] = "\n"
      elseif escaped == "r" then
        partList[#partList + 1] = "\r"
      elseif escaped == "t" then
        partList[#partList + 1] = "\t"
      elseif escaped == "u" then
        decodeError(text, index, "unicode escape is not supported in this phase")
      else
        decodeError(text, index, "invalid escape sequence")
      end
      index = index + 2
    else
      partList[#partList + 1] = character
      index = index + 1
    end
  end

  decodeError(text, index, "unterminated string")
end

local function decodeNumber(text, index)
  local startIndex = index
  while index <= #text do
    local character = text:sub(index, index)
    if character:match("[%d%+%-%e%E%.]") then
      index = index + 1
    else
      break
    end
  end
  local numberText = text:sub(startIndex, index - 1)
  local parsed = tonumber(numberText)
  if parsed == nil then
    decodeError(text, startIndex, "invalid number")
  end
  return parsed, index
end

local function decodeLiteral(text, index)
  if text:sub(index, index + 3) == "true" then
    return true, index + 4
  end
  if text:sub(index, index + 4) == "false" then
    return false, index + 5
  end
  if text:sub(index, index + 3) == "null" then
    return nil, index + 4
  end
  decodeError(text, index, "invalid literal")
end

local function decodeArray(text, index)
  local result = {}
  index = skipWhitespace(text, index + 1)
  if text:sub(index, index) == "]" then
    return result, index + 1
  end

  while true do
    local value
    value, index = decodeValue(text, index)
    result[#result + 1] = value
    index = skipWhitespace(text, index)

    local character = text:sub(index, index)
    if character == "]" then
      return result, index + 1
    end
    if character ~= "," then
      decodeError(text, index, "expected , or ]")
    end
    index = skipWhitespace(text, index + 1)
  end
end

local function decodeObject(text, index)
  local result = {}
  index = skipWhitespace(text, index + 1)
  if text:sub(index, index) == "}" then
    return result, index + 1
  end

  while true do
    if text:sub(index, index) ~= "\"" then
      decodeError(text, index, "expected string key")
    end

    local key
    key, index = decodeString(text, index)
    index = skipWhitespace(text, index)

    if text:sub(index, index) ~= ":" then
      decodeError(text, index, "expected :")
    end
    index = skipWhitespace(text, index + 1)

    local value
    value, index = decodeValue(text, index)
    result[key] = value
    index = skipWhitespace(text, index)

    local character = text:sub(index, index)
    if character == "}" then
      return result, index + 1
    end
    if character ~= "," then
      decodeError(text, index, "expected , or }")
    end
    index = skipWhitespace(text, index + 1)
  end
end

decodeValue = function(text, index)
  index = skipWhitespace(text, index)
  local character = text:sub(index, index)
  if character == "\"" then
    return decodeString(text, index)
  end
  if character == "[" then
    return decodeArray(text, index)
  end
  if character == "{" then
    return decodeObject(text, index)
  end
  if character:match("[%d%-]") then
    return decodeNumber(text, index)
  end
  return decodeLiteral(text, index)
end

function Json.decode(text)
  if type(text) ~= "string" then
    error("Json.decode expects string")
  end
  local value, nextIndex = decodeValue(text, 1)
  nextIndex = skipWhitespace(text, nextIndex)
  if nextIndex <= #text then
    decodeError(text, nextIndex, "unexpected trailing characters")
  end
  return value
end

return Json
