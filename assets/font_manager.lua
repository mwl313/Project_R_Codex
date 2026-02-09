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

local FontManager = {
  _fontMap = {},
  _warningMessage = nil,
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
  local errorMessage = string.format(
    "폰트 로딩 실패(%s): %s. 기본 폰트로 폴백합니다.",
    tostring(fontPath),
    tostring(fontOrError)
  )
  return fallbackFont, errorMessage
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
    FontManager._warningMessage = firstError
    print("[FontManager] " .. firstError)
  else
    FontManager._warningMessage = nil
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
  return FontManager._warningMessage
end

return FontManager
