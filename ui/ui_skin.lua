--[[
파일명: ui_skin.lua
모듈명: UISkin

역할:
- UI 스킨 경로/슬라이스 설정을 한 곳에서 관리한다.
- 이미지 로드 + nearest 필터 설정 + NineSlice 객체 생성을 담당한다.

외부에서 사용 가능한 함수:
- UISkin.load()
- UISkin.getDefinition()

확장 방법:
- 새 상태/컴포넌트를 추가할 때는 SKIN_DEFINITION만 수정한다.
- 예: textbox focus 상태를 추가하려면
  - SKIN_DEFINITION.textboxFocus = { path = "...", insets = { ... } }
  - 사용하는 draw helper에서 키만 참조하도록 연결하면 된다.
]]

local NineSlice = require("ui.nine_slice")

local UISkin = {}

local SKIN_DEFINITION = {
  panel = {
    path = "assets/ui/panel_128.png",
    insets = { l = 24, t = 24, r = 24, b = 24 }
  },
  textbox = {
    path = "assets/ui/textbox_64.png",
    insets = { l = 12, t = 12, r = 12, b = 12 }
  },
  button = {
    idle = {
      path = "assets/ui/btn_idle_64.png",
      insets = { l = 12, t = 12, r = 12, b = 12 }
    },
    hover = {
      path = "assets/ui/btn_hover_64.png",
      insets = { l = 12, t = 12, r = 12, b = 12 }
    },
    pressed = {
      path = "assets/ui/btn_pressed_64.png",
      insets = { l = 12, t = 12, r = 12, b = 12 }
    },
    disabled = {
      path = "assets/ui/btn_disabled_64.png",
      insets = { l = 12, t = 12, r = 12, b = 12 }
    }
  }
}

local cachedSkin = nil

local function loadImage(path)
  local ok, imageOrError = pcall(love.graphics.newImage, path)
  if not ok then
    print("[UISkin] image load failed: " .. tostring(path) .. " / " .. tostring(imageOrError))
    return nil
  end

  local image = imageOrError
  image:setFilter("nearest", "nearest")
  return image
end

local function loadSlice(definitionEntry)
  local image = loadImage(definitionEntry.path)
  if not image then
    return nil
  end
  return NineSlice.new(image, definitionEntry.insets)
end

function UISkin.getDefinition()
  return SKIN_DEFINITION
end

function UISkin.load()
  if cachedSkin then
    return cachedSkin
  end
  if not love or not love.graphics then
    return nil
  end

  local panelSlice = loadSlice(SKIN_DEFINITION.panel)
  local textboxSlice = loadSlice(SKIN_DEFINITION.textbox)
  local buttonIdleSlice = loadSlice(SKIN_DEFINITION.button.idle)
  local buttonHoverSlice = loadSlice(SKIN_DEFINITION.button.hover)
  local buttonPressedSlice = loadSlice(SKIN_DEFINITION.button.pressed)
  local buttonDisabledSlice = loadSlice(SKIN_DEFINITION.button.disabled)

  local isLoaded = panelSlice ~= nil
    and textboxSlice ~= nil
    and buttonIdleSlice ~= nil
    and buttonHoverSlice ~= nil
    and buttonPressedSlice ~= nil
    and buttonDisabledSlice ~= nil

  cachedSkin = {
    isLoaded = isLoaded,
    panel = panelSlice,
    textbox = textboxSlice,
    button = {
      idle = buttonIdleSlice,
      hover = buttonHoverSlice,
      pressed = buttonPressedSlice,
      disabled = buttonDisabledSlice
    }
  }

  if not isLoaded then
    print("[UISkin] fallback to legacy rectangle rendering (some skin assets missing).")
  end

  return cachedSkin
end

return UISkin

