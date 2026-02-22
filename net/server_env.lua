--[[
파일명: server_env.lua
모듈명: ServerEnv

역할:
- 클라이언트 서버 접속 환경(local/cloud)을 중앙 관리한다.
- HTTP base URL을 단일 경로로 제공한다.

외부에서 사용 가능한 함수:
- ServerEnv.normalize(env)
- ServerEnv.set(env)
- ServerEnv.get()
- ServerEnv.getHttpBase(env)
- ServerEnv.getWsBase(env) -- deprecated (legacy compatibility only)
]]

local Constants = require("constants")

local ServerEnv = {}

local function normalizeEnv(env)
  local value = tostring(env or ""):lower()
  if value == Constants.SERVER_ENV_LOCAL or value == Constants.SERVER_ENV_CLOUD then
    return value
  end
  return Constants.SERVER_ENV_DEFAULT
end

local currentEnv = normalizeEnv(Constants.SERVER_ENV_DEFAULT)

function ServerEnv.normalize(env)
  return normalizeEnv(env)
end

function ServerEnv.set(env)
  currentEnv = normalizeEnv(env)
  return currentEnv
end

function ServerEnv.get()
  return currentEnv
end

function ServerEnv.getHttpBase(env)
  local resolvedEnv = normalizeEnv(env or currentEnv)
  if resolvedEnv == Constants.SERVER_ENV_LOCAL then
    return Constants.SERVER_HTTP_BASE_URL_LOCAL
  end
  return Constants.SERVER_HTTP_BASE_URL_CLOUD
end

function ServerEnv.getWsBase(env, preferInsecureCloud)
  -- Deprecated: 런타임 클라이언트는 WS를 사용하지 않는다.
  -- 기존 호출부와의 호환을 위해서만 남겨둔다.
  local resolvedEnv = normalizeEnv(env or currentEnv)
  if resolvedEnv == Constants.SERVER_ENV_LOCAL then
    return Constants.SERVER_WS_BASE_URL_LOCAL
  end
  if preferInsecureCloud == true and type(Constants.SERVER_WS_BASE_URL_CLOUD_INSECURE) == "string" and Constants.SERVER_WS_BASE_URL_CLOUD_INSECURE ~= "" then
    return Constants.SERVER_WS_BASE_URL_CLOUD_INSECURE
  end
  return Constants.SERVER_WS_BASE_URL_CLOUD
end

return ServerEnv
