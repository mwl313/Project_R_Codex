--[[
파일명: settings_manager.lua
모듈명: SettingsManager

역할:
- settings.ini 로드/저장
- 닉네임/디스플레이 모드 기본값 관리
- 런타임 디스플레이 모드 적용

외부에서 사용 가능한 함수:
- SettingsManager.new()
- SettingsManager:loadSettings()
- SettingsManager:saveSettings(settings)
- SettingsManager:applyDisplayMode(displayMode)
- SettingsManager:getDefaultSettings()
- SettingsManager:getSettingsDebugPath()

주의:
- 알 수 없는 key는 무시한다
]]

local Constants = require("constants")

local SettingsManager = {}
SettingsManager.__index = SettingsManager

local KNOWN_DISPLAY_MODE_MAP = {
  [Constants.DISPLAY_MODE_WINDOWED] = true,
  [Constants.DISPLAY_MODE_FULLSCREEN] = true
}
local KNOWN_LANGUAGE_MAP = {
  ko = true,
  en = true
}
local KNOWN_SERVER_ENV_MAP = {
  [Constants.SERVER_ENV_LOCAL] = true,
  [Constants.SERVER_ENV_CLOUD] = true
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getUtfModule()
  if love and love.utf8 then
    return love.utf8
  end
  local isLoaded, moduleValue = pcall(require, "utf8")
  if isLoaded and type(moduleValue) == "table" then
    return moduleValue
  end
  return nil
end

local UTF_MODULE = getUtfModule()

local function truncateUtf8(value, maxChars)
  if type(value) ~= "string" then
    return ""
  end
  local safeMax = tonumber(maxChars) or 0
  if safeMax <= 0 then
    return ""
  end

  if UTF_MODULE and type(UTF_MODULE.offset) == "function" then
    local isOk, cutIndex = pcall(UTF_MODULE.offset, value, safeMax + 1)
    if isOk and type(cutIndex) == "number" then
      return string.sub(value, 1, cutIndex - 1)
    end
  end

  if #value <= safeMax then
    return value
  end
  return string.sub(value, 1, safeMax)
end

local function sanitizeNickname(value)
  local text = tostring(value or "")
  text = text:gsub("[\r\n]", " ")
  text = trim(text)
  text = truncateUtf8(text, Constants.NICKNAME_MAX_LENGTH)
  if text == "" then
    return "Player"
  end
  return text
end

local function sanitizeDisplayMode(value)
  if KNOWN_DISPLAY_MODE_MAP[value] then
    return value
  end
  return Constants.DISPLAY_MODE_WINDOWED
end

local function sanitizeLanguage(value)
  local normalized = tostring(value or ""):lower()
  if KNOWN_LANGUAGE_MAP[normalized] then
    return normalized
  end
  return "ko"
end

local function cloneSettings(settings)
  return {
    nickname = settings.nickname,
    displayMode = settings.displayMode,
    language = settings.language,
    serverEnv = settings.serverEnv
  }
end

local function sanitizeServerEnv(value)
  local normalized = tostring(value or ""):lower()
  if KNOWN_SERVER_ENV_MAP[normalized] then
    return normalized
  end
  return Constants.SERVER_ENV_DEFAULT
end

function SettingsManager.new()
  local instance = {}
  return setmetatable(instance, SettingsManager)
end

function SettingsManager:getDefaultSettings()
  return {
    nickname = "Player",
    displayMode = Constants.DISPLAY_MODE_WINDOWED,
    language = "ko",
    serverEnv = Constants.SERVER_ENV_DEFAULT
  }
end

function SettingsManager:getSettingsDebugPath()
  return string.format("%s/%s", love.filesystem.getSaveDirectory(), Constants.SETTINGS_FILENAME)
end

function SettingsManager:loadSettings()
  local settings = self:getDefaultSettings()
  local info = love.filesystem.getInfo(Constants.SETTINGS_FILENAME)
  if not info then
    return settings, nil
  end

  local isReadOk, contentOrError = pcall(love.filesystem.read, Constants.SETTINGS_FILENAME)
  if not isReadOk then
    return settings, tostring(contentOrError)
  end

  local content = tostring(contentOrError or "")
  for line in content:gmatch("[^\r\n]+") do
    local trimmedLine = trim(line)
    if trimmedLine ~= "" and trimmedLine:sub(1, 1) ~= "#" then
      local key, value = trimmedLine:match("^([^=]+)=(.*)$")
      if key then
        key = trim(key)
        value = trim(value)
        if key == "nickname" then
          settings.nickname = sanitizeNickname(value)
        elseif key == "display_mode" then
          settings.displayMode = sanitizeDisplayMode(value)
        elseif key == "language" then
          settings.language = sanitizeLanguage(value)
        elseif key == "server_env" or key == "serverEnv" then
          settings.serverEnv = sanitizeServerEnv(value)
        end
      end
    end
  end

  return settings, nil
end

function SettingsManager:saveSettings(settings)
  local normalized = {
    nickname = sanitizeNickname(settings.nickname),
    displayMode = sanitizeDisplayMode(settings.displayMode),
    language = sanitizeLanguage(settings.language),
    serverEnv = sanitizeServerEnv(settings.serverEnv)
  }

  local isFullscreen = normalized.displayMode == Constants.DISPLAY_MODE_FULLSCREEN
  local lineList = {
    "# ProjectR settings.ini (UTF-8)",
    "nickname=" .. normalized.nickname,
    "display_mode=" .. normalized.displayMode,
    "language=" .. normalized.language,
    "server_env=" .. normalized.serverEnv,
    "window_width=" .. tostring(Constants.WINDOWED_W),
    "window_height=" .. tostring(Constants.WINDOWED_H),
    "fullscreen=" .. (isFullscreen and "true" or "false"),
    "fullscreen_mode=" .. (isFullscreen and "desktop" or "windowed")
  }

  local body = table.concat(lineList, "\n") .. "\n"
  local isWriteOk, writeError = pcall(love.filesystem.write, Constants.SETTINGS_FILENAME, body)
  if not isWriteOk then
    return false, tostring(writeError)
  end

  return true, nil
end

function SettingsManager:applyDisplayMode(displayMode)
  local normalizedMode = sanitizeDisplayMode(displayMode)

  if normalizedMode == Constants.DISPLAY_MODE_FULLSCREEN then
    local displayIndex = 1
    if love.window.getDisplayIndex then
      local currentIndex = love.window.getDisplayIndex()
      if type(currentIndex) == "number" and currentIndex >= 1 then
        displayIndex = currentIndex
      end
    end

    local desktopW, desktopH = love.window.getDesktopDimensions(displayIndex)
    local isOk, errorText = love.window.setMode(desktopW, desktopH, {
      fullscreen = true,
      fullscreentype = "desktop",
      display = displayIndex,
      resizable = true,
      minwidth = 960,
      minheight = 540
    })

    if isOk then
      return Constants.DISPLAY_MODE_FULLSCREEN, nil
    end

    normalizedMode = Constants.DISPLAY_MODE_WINDOWED
    print("[SettingsManager] fullscreen 적용 실패, 창모드로 폴백: " .. tostring(errorText))
  end

  local isWindowedOk, windowedErrorText = love.window.setMode(Constants.WINDOWED_W, Constants.WINDOWED_H, {
    fullscreen = false,
    resizable = true,
    minwidth = 960,
    minheight = 540
  })
  if isWindowedOk then
    return Constants.DISPLAY_MODE_WINDOWED, nil
  end

  return Constants.DISPLAY_MODE_WINDOWED, tostring(windowedErrorText)
end

function SettingsManager:normalizeSettings(settings)
  local defaultSettings = self:getDefaultSettings()
  local normalized = {
    nickname = settings and settings.nickname or defaultSettings.nickname,
    displayMode = settings and settings.displayMode or defaultSettings.displayMode,
    language = settings and settings.language or defaultSettings.language,
    serverEnv = settings and settings.serverEnv or defaultSettings.serverEnv
  }
  normalized.nickname = sanitizeNickname(normalized.nickname)
  normalized.displayMode = sanitizeDisplayMode(normalized.displayMode)
  normalized.language = sanitizeLanguage(normalized.language)
  normalized.serverEnv = sanitizeServerEnv(normalized.serverEnv)
  return cloneSettings(normalized)
end

return SettingsManager
