--[[
파일명: text_input.lua
모듈명: TextInput

역할:
- 텍스트 입력 박스 UI 제공
- IME 조합 문자열(textedited) 표시 및 UTF-8 안전 삭제 처리

외부에서 사용 가능한 함수:
- TextInput.new(params)
- TextInput:setFocus(isFocused)
- TextInput:setText(text)
- TextInput:getText()
- TextInput:insertText(text)
- TextInput:textinput(text)
- TextInput:textedited(text, start, length)
- TextInput:keypressed(key)
- TextInput:mousepressed(x, y, button)
- TextInput:draw()

주의:
- 백스페이스는 Utf8Utils.removeLast 경로로만 처리한다
]]

local Constants = require("constants")
local Utf8Utils = require("utils.utf8_utils")
local FontManager = require("assets.font_manager")

local TextInput = {}
TextInput.__index = TextInput

local CARET_BLINK_PERIOD_SEC = 0.5
local TEXT_PADDING_X = 10
local TEXT_DRAW_Y_OFFSET = 11

local function nowSec()
  if love and love.timer and love.timer.getTime then
    local isOk, value = pcall(love.timer.getTime)
    if isOk and type(value) == "number" then
      return value
    end
  end
  return os.clock()
end

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

function TextInput.new(params)
  local instance = {
    x = params.x or 0,
    y = params.y or 0,
    w = params.w or 300,
    h = params.h or 40,
    placeholder = params.placeholder or "",
    text = params.text or "",
    compositionText = "",
    isFocused = false,
    isEnabled = params.isEnabled ~= false,
    onEnter = params.onEnter
  }
  return setmetatable(instance, TextInput)
end

function TextInput:setFocus(isFocused)
  self.isFocused = isFocused and true or false
  if not self.isFocused then
    self.compositionText = ""
  end
end

function TextInput:setText(text)
  self.text = text or ""
end

function TextInput:getText()
  return self.text
end

function TextInput:insertText(text)
  if not self.isEnabled or not self.isFocused then
    return false
  end

  local insertValue = type(text) == "string" and text or ""
  if insertValue == "" then
    return false
  end

  self.text = self.text .. insertValue
  return true
end

function TextInput:textinput(text)
  self:insertText(text)
end

function TextInput:textedited(text, _start, _length)
  if not self.isEnabled or not self.isFocused then
    return
  end
  self.compositionText = text or ""
end

function TextInput:keypressed(key)
  if not self.isEnabled or not self.isFocused then
    return false
  end

  if key == "v" then
    local hasKeyboard = love and love.keyboard and love.keyboard.isDown
    local isCtrlDown = hasKeyboard and love.keyboard.isDown("lctrl", "rctrl")
    local isCmdDown = hasKeyboard and love.keyboard.isDown("lgui", "rgui")
    if isCtrlDown or isCmdDown then
      if self.compositionText ~= "" then
        self.compositionText = ""
      end

      local clip = ""
      if love and love.system and love.system.getClipboardText then
        local isOk, clipboardValue = pcall(love.system.getClipboardText)
        if isOk and type(clipboardValue) == "string" then
          clip = clipboardValue
        end
      end

      clip = clip:gsub("\r\n", ""):gsub("\r", ""):gsub("\n", "")
      if clip == "" then
        return true
      end

      self:insertText(clip)
      return true
    end
  end

  if key == "backspace" then
    if self.text == "" then
      return true
    end
    self.text = Utf8Utils.removeLast(self.text)
    return true
  end

  if key == "return" or key == "kpenter" then
    self.compositionText = ""
    if self.onEnter then
      self.onEnter(self.text)
    end
    return true
  end

  return false
end

function TextInput:mousepressed(mouseX, mouseY, button)
  if button ~= 1 or not self.isEnabled then
    return false
  end

  local isInside = mouseX >= self.x and mouseX <= self.x + self.w and mouseY >= self.y and mouseY <= self.y + self.h
  self:setFocus(isInside)
  return isInside
end

function TextInput:draw()
  love.graphics.setColor(Constants.COLOR_INPUT_BG)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 6, 6)

  love.graphics.setColor(self.isFocused and Constants.COLOR_PANEL_BORDER or Constants.COLOR_TEXT_SUB)
  love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 6, 6)

  local viewText = self.text
  if self.compositionText ~= "" then
    viewText = viewText .. self.compositionText
  end

  local font = FontManager.getFont("ui")
  love.graphics.setFont(font)
  if viewText == "" then
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(self.placeholder, self.x + TEXT_PADDING_X, self.y + TEXT_DRAW_Y_OFFSET)
  else
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(viewText, self.x + TEXT_PADDING_X, self.y + TEXT_DRAW_Y_OFFSET)
  end

  if self.isEnabled and self.isFocused then
    local blinkIndex = math.floor(nowSec() / CARET_BLINK_PERIOD_SEC)
    if blinkIndex % 2 == 0 then
      local caretBaseText = viewText
      local caretX = self.x + TEXT_PADDING_X + font:getWidth(caretBaseText)
      local minCaretX = self.x + TEXT_PADDING_X
      local maxCaretX = self.x + self.w - TEXT_PADDING_X
      caretX = clamp(caretX, minCaretX, maxCaretX)

      love.graphics.setColor(Constants.COLOR_TEXT)
      love.graphics.line(caretX, self.y + 8, caretX, self.y + self.h - 8)
    end
  end
end

return TextInput
