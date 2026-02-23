--[[
파일명: single_json_loader.lua
모듈명: SingleJsonLoader

역할:
- 싱글 SSOT JSON 로딩 공통 유틸.
- 개발 모드에서는 경고를 출력하고, 릴리즈에서는 크래시 없이 폴백한다.
]]

local Json = require("utils.json")

local SingleJsonLoader = {}

local function isDevMode()
  if not love or not love.filesystem or type(love.filesystem.isFused) ~= "function" then
    return false
  end
  return love.filesystem.isFused() ~= true
end

function SingleJsonLoader.deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copied = {}
  for key, nestedValue in pairs(value) do
    copied[key] = SingleJsonLoader.deepCopy(nestedValue)
  end
  return copied
end

function SingleJsonLoader.warn(scope, message)
  if not isDevMode() then
    return
  end
  print(string.format("[SingleData][%s] %s", tostring(scope), tostring(message)))
end

function SingleJsonLoader.readJson(path, scope)
  if not love or not love.filesystem then
    SingleJsonLoader.warn(scope, "filesystem_unavailable")
    return nil
  end

  local readOk, rawOrError = pcall(love.filesystem.read, path)
  if not readOk or type(rawOrError) ~= "string" or rawOrError == "" then
    SingleJsonLoader.warn(scope, "read_failed:" .. tostring(rawOrError))
    return nil
  end

  local decodeOk, decodedOrError = pcall(Json.decode, rawOrError)
  if not decodeOk or type(decodedOrError) ~= "table" then
    SingleJsonLoader.warn(scope, "decode_failed:" .. tostring(decodedOrError))
    return nil
  end
  return decodedOrError
end

function SingleJsonLoader.toNumber(value, fallback)
  if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
    return value
  end
  return fallback
end

function SingleJsonLoader.toBoolean(value, fallback)
  if type(value) == "boolean" then
    return value
  end
  return fallback
end

function SingleJsonLoader.toString(value, fallback)
  if type(value) == "string" and value ~= "" then
    return value
  end
  return fallback
end

function SingleJsonLoader.toTable(value, fallback)
  if type(value) == "table" then
    return value
  end
  return fallback or {}
end

function SingleJsonLoader.toArray(value, fallback)
  if type(value) == "table" then
    return value
  end
  return fallback or {}
end

return SingleJsonLoader
