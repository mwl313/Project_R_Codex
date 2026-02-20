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
local UIDraw = require("ui.ui_draw")

local TextInput = {}
TextInput.__index = TextInput

local CARET_BLINK_PERIOD_SEC = 0.5
local TEXT_PADDING_X = 10
local TEXT_DRAW_Y_OFFSET = 11
local MULTILINE_PADDING_Y = 6

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

local function buildDisplayText(textValue, caretPos, compositionText)
  local leftText, rightText = Utf8Utils.splitAt(textValue, caretPos)
  local compose = compositionText or ""
  return leftText .. compose .. rightText, leftText .. compose
end

local function getWrappedLines(textValue, font, maxWidth)
  if textValue == "" then
    return {
      {
        text = "",
        startPos = 0,
        endPos = 0
      }
    }
  end

  local _, lineList = font:getWrap(textValue, maxWidth)
  if type(lineList) ~= "table" or #lineList == 0 then
    lineList = { textValue }
  end

  local lines = {}
  local cursorPos = 0
  for _, lineText in ipairs(lineList) do
    local lineLen = Utf8Utils.length(lineText)
    lines[#lines + 1] = {
      text = lineText,
      startPos = cursorPos,
      endPos = cursorPos + lineLen
    }
    cursorPos = cursorPos + lineLen
  end

  if #lines == 0 then
    lines[1] = {
      text = "",
      startPos = 0,
      endPos = 0
    }
  end
  return lines
end

local function findLineByCaret(lines, caretPos)
  local safeCaret = math.max(0, caretPos)
  for index, line in ipairs(lines) do
    if safeCaret <= line.endPos then
      local column = safeCaret - line.startPos
      if column < 0 then
        column = 0
      end
      return index, column
    end
  end

  local lastIndex = #lines
  local lastLine = lines[lastIndex]
  return lastIndex, Utf8Utils.length(lastLine.text)
end

local function resolveStartLineIndexByCaret(lineCount, maxVisibleLines, caretLineIndex, isFocused)
  if lineCount <= maxVisibleLines then
    return 1
  end

  if not isFocused then
    return math.max(1, lineCount - maxVisibleLines + 1)
  end

  local minStart = 1
  local maxStart = lineCount - maxVisibleLines + 1
  local preferred = caretLineIndex - maxVisibleLines + 1
  return clamp(preferred, minStart, maxStart)
end

local function getColumnPixelX(lineText, column, font)
  local leftText, _ = Utf8Utils.splitAt(lineText, column)
  return font:getWidth(leftText)
end

local function resolveColumnByPixelX(lineText, targetPixelX, font)
  local lineLen = Utf8Utils.length(lineText)
  if lineLen <= 0 then
    return 0
  end

  local prevWidth = 0
  for column = 0, lineLen do
    local width = getColumnPixelX(lineText, column, font)
    if width >= targetPixelX then
      if column == 0 then
        return 0
      end
      if math.abs(width - targetPixelX) < math.abs(prevWidth - targetPixelX) then
        return column
      end
      return column - 1
    end
    prevWidth = width
  end
  return lineLen
end

function TextInput.new(params)
  local initialText = params.text or ""
  local instance = {
    x = params.x or 0,
    y = params.y or 0,
    w = params.w or 300,
    h = params.h or 40,
    placeholder = params.placeholder or "",
    text = initialText,
    compositionText = "",
    maxChars = params.maxChars or nil,
    wrapText = params.wrapText == true,
    isFocused = false,
    isEnabled = params.isEnabled ~= false,
    onEnter = params.onEnter,
    caretPos = Utf8Utils.length(initialText),
    _caretPreferredPixelX = nil
  }
  return setmetatable(instance, TextInput)
end

function TextInput:setFocus(isFocused)
  self.isFocused = isFocused and true or false
  if not self.isFocused then
    self.compositionText = ""
    self._caretPreferredPixelX = nil
  end
end

function TextInput:setCaretPos(charIndex)
  local totalLength = Utf8Utils.length(self.text)
  local safeIndex = tonumber(charIndex) or totalLength
  safeIndex = math.floor(safeIndex)
  self.caretPos = clamp(safeIndex, 0, totalLength)
end

function TextInput:setText(text)
  local value = type(text) == "string" and text or ""
  if type(self.maxChars) == "number" and self.maxChars > 0 then
    value = Utf8Utils.truncateToLength(value, self.maxChars)
  end
  self.text = value
  self:setCaretPos(Utf8Utils.length(self.text))
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

  local leftText, rightText = Utf8Utils.splitAt(self.text, self.caretPos)
  local nextText = leftText .. insertValue .. rightText
  local nextCaretPos = Utf8Utils.length(leftText .. insertValue)
  if type(self.maxChars) == "number" and self.maxChars > 0 then
    nextText = Utf8Utils.truncateToLength(nextText, self.maxChars)
  end

  self.text = nextText
  self:setCaretPos(nextCaretPos)
  self._caretPreferredPixelX = nil
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
      self.compositionText = ""

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

  if key == "left" then
    self.compositionText = ""
    self:setCaretPos(self.caretPos - 1)
    self._caretPreferredPixelX = nil
    return true
  end
  if key == "right" then
    self.compositionText = ""
    self:setCaretPos(self.caretPos + 1)
    self._caretPreferredPixelX = nil
    return true
  end
  if key == "home" then
    self.compositionText = ""
    self:setCaretPos(0)
    self._caretPreferredPixelX = nil
    return true
  end
  if key == "end" then
    self.compositionText = ""
    self:setCaretPos(Utf8Utils.length(self.text))
    self._caretPreferredPixelX = nil
    return true
  end

  if key == "up" or key == "down" then
    self.compositionText = ""
    local font = FontManager.getFont("ui")
    local maxWidth = math.max(16, self.w - TEXT_PADDING_X * 2)
    local lines = getWrappedLines(self.text, font, maxWidth)
    local lineIndex, column = findLineByCaret(lines, self.caretPos)
    local currentLine = lines[lineIndex]

    if not self._caretPreferredPixelX then
      self._caretPreferredPixelX = getColumnPixelX(currentLine.text, column, font)
    end

    local targetLineIndex = key == "up" and (lineIndex - 1) or (lineIndex + 1)
    targetLineIndex = clamp(targetLineIndex, 1, #lines)
    local targetLine = lines[targetLineIndex]
    local targetColumn = resolveColumnByPixelX(targetLine.text, self._caretPreferredPixelX, font)
    self:setCaretPos(targetLine.startPos + targetColumn)
    return true
  end

  if key == "backspace" then
    if self.text == "" or self.caretPos <= 0 then
      return true
    end
    local leftText, rightText = Utf8Utils.splitAt(self.text, self.caretPos)
    leftText = Utf8Utils.removeLast(leftText)
    self.text = leftText .. rightText
    self:setCaretPos(Utf8Utils.length(leftText))
    self._caretPreferredPixelX = nil
    return true
  end

  if key == "delete" then
    local leftText, rightText = Utf8Utils.splitAt(self.text, self.caretPos)
    if rightText == "" then
      return true
    end
    local _, remain = Utf8Utils.splitAt(rightText, 1)
    self.text = leftText .. remain
    self:setCaretPos(Utf8Utils.length(leftText))
    self._caretPreferredPixelX = nil
    return true
  end

  if key == "return" or key == "kpenter" then
    self.compositionText = ""
    self._caretPreferredPixelX = nil
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
  if isInside then
    self:setCaretPos(Utf8Utils.length(self.text))
  end
  return isInside
end

function TextInput:draw()
  UIDraw.drawTextBox(
    self,
    self.isFocused,
    Constants.COLOR_INPUT_BG,
    Constants.COLOR_PANEL_BORDER,
    Constants.COLOR_TEXT_SUB,
    nil
  )

  local viewText, caretBaseText = buildDisplayText(self.text, self.caretPos, self.compositionText)
  local font = FontManager.getFont("ui")
  love.graphics.setFont(font)

  local drawWrapped = self.wrapText == true
  local maxWidth = math.max(16, self.w - TEXT_PADDING_X * 2)
  local lineHeight = font:getHeight()
  local wrappedLinesForDraw = nil
  local maxVisibleLines = nil
  local drawStartLineIndex = 1

  if viewText == "" then
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(self.placeholder, self.x + TEXT_PADDING_X, self.y + TEXT_DRAW_Y_OFFSET)
  else
    love.graphics.setColor(Constants.COLOR_TEXT)
    if drawWrapped then
      wrappedLinesForDraw = getWrappedLines(viewText, font, maxWidth)
      maxVisibleLines = math.max(1, math.floor((self.h - MULTILINE_PADDING_Y * 2) / lineHeight))
      local caretDisplayPos = Utf8Utils.length(caretBaseText)
      local caretLineIndex = 1
      if self.isFocused then
        caretLineIndex = findLineByCaret(wrappedLinesForDraw, caretDisplayPos)
      else
        caretLineIndex = #wrappedLinesForDraw
      end
      drawStartLineIndex = resolveStartLineIndexByCaret(#wrappedLinesForDraw, maxVisibleLines, caretLineIndex, self.isFocused)
      local endLineIndex = math.min(#wrappedLinesForDraw, drawStartLineIndex + maxVisibleLines - 1)
      local drawY = self.y + MULTILINE_PADDING_Y
      for index = drawStartLineIndex, endLineIndex do
        love.graphics.print(wrappedLinesForDraw[index].text, self.x + TEXT_PADDING_X, drawY)
        drawY = drawY + lineHeight
      end
    else
      love.graphics.print(viewText, self.x + TEXT_PADDING_X, self.y + TEXT_DRAW_Y_OFFSET)
    end
  end

  if self.isEnabled and self.isFocused then
    local blinkIndex = math.floor(nowSec() / CARET_BLINK_PERIOD_SEC)
    if blinkIndex % 2 == 0 then
      local caretX = self.x + TEXT_PADDING_X + font:getWidth(caretBaseText)
      local caretY1 = self.y + 8
      local caretY2 = self.y + self.h - 8

      if drawWrapped then
        local lines = wrappedLinesForDraw or getWrappedLines(viewText, font, maxWidth)
        local caretDisplayPos = Utf8Utils.length(caretBaseText)
        local caretLineIndex, caretColumn = findLineByCaret(lines, caretDisplayPos)
        local visibleMaxLines = maxVisibleLines or math.max(1, math.floor((self.h - MULTILINE_PADDING_Y * 2) / lineHeight))
        local startLineIndex = resolveStartLineIndexByCaret(#lines, visibleMaxLines, caretLineIndex, true)
        local visibleLineIndex = clamp(caretLineIndex - startLineIndex + 1, 1, visibleMaxLines)
        local lineTop = self.y + MULTILINE_PADDING_Y + (visibleLineIndex - 1) * lineHeight
        local leftPart, _ = Utf8Utils.splitAt(lines[caretLineIndex].text, caretColumn)
        caretX = self.x + TEXT_PADDING_X + font:getWidth(leftPart)
        caretY1 = lineTop + 1
        caretY2 = lineTop + lineHeight - 1
      end

      local minCaretX = self.x + TEXT_PADDING_X
      local maxCaretX = self.x + self.w - TEXT_PADDING_X
      caretX = clamp(caretX, minCaretX, maxCaretX)

      love.graphics.setColor(Constants.COLOR_TEXT)
      love.graphics.line(caretX, caretY1, caretX, caretY2)
    end
  end
end

return TextInput
