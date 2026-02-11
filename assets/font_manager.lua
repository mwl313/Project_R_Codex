--[[
파일명: font_manager.lua
모듈명: FontManager

역할:
- 프로젝트 공용 폰트 로딩/관리
- 한글 폰트 프리셋(title/ui/small) 제공
- 폰트 누락 시 기본 폰트 폴백 및 경고 메시지 제공

외부에서 사용 가능한 함수:
- FontManager.loadFonts()
- FontManager.getFont(presetName)
- FontManager.getWarningMessage()

주의:
- 폰트 경로는 상대경로만 사용한다
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")

local FontManager = {
  _fontMap = {},
  _warningData = nil,
  _isLoaded = false
}

local function createFallbackFont(size)
  local isCreated, fontOrError = pcall(love.graphics.newFont, size)
  if isCreated and fontOrError then
    return fontOrError
  end
  return love.graphics.getFont()
end

local function loadPresetFont(fontPath, size)
  local isCreated, fontOrError = pcall(love.graphics.newFont, fontPath, size)
  if isCreated and fontOrError then
    return fontOrError, nil
  end

  local fallbackFont = createFallbackFont(size)
  return fallbackFont, tostring(fontOrError)
end

function FontManager.loadFonts()
  if FontManager._isLoaded then
    return
  end

  local fontPath = Constants.FONT_KR_REGULAR_PATH

  local titleFont, titleError = loadPresetFont(fontPath, Constants.FONT_SIZE_TITLE)
  local uiFont, uiError = loadPresetFont(fontPath, Constants.FONT_SIZE_UI)
  local smallFont, smallError = loadPresetFont(fontPath, Constants.FONT_SIZE_SMALL)

  FontManager._fontMap.title = titleFont
  FontManager._fontMap.ui = uiFont
  FontManager._fontMap.small = smallFont
  FontManager._fontMap.default = uiFont

  local firstError = titleError or uiError or smallError
  if firstError then
    FontManager._warningData = {
      path = tostring(fontPath),
      error = tostring(firstError)
    }
    print("[FontManager] " .. FontManager.getWarningMessage())
  else
    FontManager._warningData = nil
  end

  FontManager._isLoaded = true
end

function FontManager.getFont(presetName)
  if not FontManager._isLoaded then
    FontManager.loadFonts()
  end

  if FontManager._fontMap[presetName] then
    return FontManager._fontMap[presetName]
  end
  return FontManager._fontMap.default or love.graphics.getFont()
end

function FontManager.getWarningMessage()
  if not FontManager._warningData then
    return nil
  end
  return I18n.t("font.warning.load_failed", {
    path = FontManager._warningData.path,
    error = FontManager._warningData.error
  })
end

return FontManager
