--[[
파일명: i18n.lua
모듈명: I18n

역할:
- 프로젝트 공용 다국어 문자열 조회/보간을 담당한다.
- 언어 fallback(현재 언어 -> 기본 언어 -> missing 표기)을 제공한다.

외부에서 사용 가능한 함수:
- I18n.setLanguage(lang)
- I18n.getLanguage()
- I18n.t(key, vars)

주의:
- key는 "namespace.sub_key" 형태를 권장한다.
]]

local I18n = {}

local DEFAULT_LANGUAGE = "ko"
local currentLanguage = DEFAULT_LANGUAGE
local localeMap = {
  ko = require("i18n.locales.ko"),
  en = require("i18n.locales.en")
}
local missingKeySet = {}

local function getValueFromLocale(localeTable, key)
  if type(localeTable) ~= "table" or type(key) ~= "string" then
    return nil
  end

  local currentValue = localeTable
  for segment in key:gmatch("[^%.]+") do
    if type(currentValue) ~= "table" then
      return nil
    end
    currentValue = currentValue[segment]
    if currentValue == nil then
      return nil
    end
  end
  return currentValue
end

local function interpolateText(text, vars)
  if type(text) ~= "string" then
    return tostring(text)
  end
  if type(vars) ~= "table" then
    return text
  end

  return (text:gsub("{(.-)}", function(varKey)
    local value = vars[varKey]
    if value == nil then
      return "{" .. tostring(varKey) .. "}"
    end
    return tostring(value)
  end))
end

function I18n.setLanguage(lang)
  if type(lang) == "string" and localeMap[lang] then
    currentLanguage = lang
    return currentLanguage
  end
  currentLanguage = DEFAULT_LANGUAGE
  return currentLanguage
end

function I18n.getLanguage()
  return currentLanguage
end

function I18n.t(key, vars)
  local keyText = tostring(key or "")
  local currentLocale = localeMap[currentLanguage]
  local defaultLocale = localeMap[DEFAULT_LANGUAGE]

  local text = getValueFromLocale(currentLocale, keyText)
  if text == nil then
    text = getValueFromLocale(defaultLocale, keyText)
  end

  if text == nil then
    missingKeySet[keyText] = true
    return "[[missing:" .. keyText .. "]]"
  end

  return interpolateText(text, vars)
end

function I18n.getMissingKeys()
  local keyList = {}
  for key in pairs(missingKeySet) do
    keyList[#keyList + 1] = key
  end
  table.sort(keyList)
  return keyList
end

function I18n.debugDumpMissing()
  local keyList = I18n.getMissingKeys()
  print("[I18N] missing key count: " .. tostring(#keyList))
  for _, key in ipairs(keyList) do
    print("[I18N] missing: " .. key)
  end
end

_G.I18N_DEBUG_DUMP_MISSING = function()
  I18n.debugDumpMissing()
end

return I18n
