--[[
파일명: ui_draw.lua
모듈명: UIDraw

역할:
- 버튼/패널/텍스트박스 렌더링 경로를 중앙화한다.
- UI_USE_NINESLICE 플래그 기준으로 스킨/레거시 렌더를 안전하게 스위칭한다.

외부에서 사용 가능한 함수:
- UIDraw.setSkin(skinInstance)
- UIDraw.getSkin()
- UIDraw.isNineSliceEnabled()
- UIDraw.drawButton(rect, label, state, enabled, hovered, pressed, opts)
- UIDraw.drawPanel(rect, fillColor, borderColor, sliceOpts)
- UIDraw.drawTextBox(rect, isFocused, fillColor, focusedBorderColor, unfocusedBorderColor, sliceOpts)
]]

local Constants = require("constants")
local Config = require("config")
local UISkin = require("ui.ui_skin")

local UIDraw = {}

local currentSkin = nil

local function ensureSkinLoaded()
  if currentSkin then
    return currentSkin
  end
  currentSkin = UISkin.load()
  return currentSkin
end

function UIDraw.setSkin(skinInstance)
  currentSkin = skinInstance
end

function UIDraw.getSkin()
  return currentSkin
end

function UIDraw.isNineSliceEnabled()
  if Config.UI_USE_NINESLICE ~= true then
    return false
  end
  local skin = ensureSkinLoaded()
  return skin ~= nil and skin.isLoaded == true
end

local function drawLegacyButton(rect, fillColor, borderColor)
  love.graphics.setColor(fillColor)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(borderColor)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
end

local function drawLegacyPanel(rect, fillColor, borderColor)
  love.graphics.setColor(fillColor)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 8, 8)
  love.graphics.setColor(borderColor)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 8, 8)
end

local function drawLegacyTextBox(rect, fillColor, borderColor)
  love.graphics.setColor(fillColor)
  love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6, 6)
  love.graphics.setColor(borderColor)
  love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6, 6)
end

local function resolveButtonState(state, enabled, hovered, pressed)
  if enabled == false then
    return "disabled"
  end
  if pressed then
    return "pressed"
  end
  if hovered then
    return "hover"
  end
  if state == "pressed" or state == "hover" or state == "disabled" then
    return state
  end
  return "idle"
end

function UIDraw.drawButton(rect, _label, state, enabled, hovered, pressed, fillColor, borderColor, sliceOpts)
  local drawFillColor = fillColor or Constants.COLOR_BUTTON
  local drawBorderColor = borderColor or Constants.COLOR_PANEL_BORDER
  local useNineSlice = UIDraw.isNineSliceEnabled()
  local resolvedState = resolveButtonState(state, enabled, hovered, pressed)

  if useNineSlice then
    local skin = ensureSkinLoaded()
    local slice = skin and skin.button and skin.button[resolvedState] or nil
    if slice then
      slice:draw(rect.x, rect.y, rect.w, rect.h, sliceOpts)
      return true
    end
  end

  drawLegacyButton(rect, drawFillColor, drawBorderColor)
  return false
end

function UIDraw.drawPanel(rect, fillColor, borderColor, sliceOpts)
  local drawFillColor = fillColor or Constants.COLOR_PANEL
  local drawBorderColor = borderColor or Constants.COLOR_PANEL_BORDER

  if UIDraw.isNineSliceEnabled() then
    local skin = ensureSkinLoaded()
    if skin and skin.panel then
      skin.panel:draw(rect.x, rect.y, rect.w, rect.h, sliceOpts)
      return true
    end
  end

  drawLegacyPanel(rect, drawFillColor, drawBorderColor)
  return false
end

function UIDraw.drawTextBox(rect, isFocused, fillColor, focusedBorderColor, unfocusedBorderColor, sliceOpts)
  local drawFillColor = fillColor or Constants.COLOR_INPUT_BG
  local drawFocusedBorderColor = focusedBorderColor or Constants.COLOR_PANEL_BORDER
  local drawUnfocusedBorderColor = unfocusedBorderColor or Constants.COLOR_TEXT_SUB
  local borderColor = isFocused and drawFocusedBorderColor or drawUnfocusedBorderColor

  if UIDraw.isNineSliceEnabled() then
    local skin = ensureSkinLoaded()
    if skin and skin.textbox then
      skin.textbox:draw(rect.x, rect.y, rect.w, rect.h, sliceOpts)
      return true
    end
  end

  drawLegacyTextBox(rect, drawFillColor, borderColor)
  return false
end

return UIDraw
