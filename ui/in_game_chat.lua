--[[
파일명: in_game_chat.lua
모듈명: InGameChat

역할:
- MatchScene 전용 인게임 채팅 UI(접힘/펼침 + 메시지 히스토리 + 입력)를 제공한다.
- 채팅 패널 오픈/클로즈 애니메이션과 unread 표시를 관리한다.

외부에서 사용 가능한 함수:
- InGameChat.new(app, opts)
- InGameChat:update(dt)
- InGameChat:draw(mouseX, mouseY)
- InGameChat:mousepressed(mouseX, mouseY, button)
- InGameChat:mousereleased(mouseX, mouseY, button)
- InGameChat:mousemoved(mouseX, mouseY, dx, dy)
- InGameChat:keypressed(key)
- InGameChat:wheelmoved(mouseX, mouseY, dx, dy)
- InGameChat:textinput(text)
- InGameChat:textedited(text, start, length)
- InGameChat:onServerEnvelope(envelope)
- InGameChat:isInputBlocking()

주의:
- 전송 프로토콜은 App:sendChat(text) 경로를 그대로 사용한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local TextInput = require("ui.text_input")
local UIDraw = require("ui.ui_draw")

local InGameChat = {}
InGameChat.__index = InGameChat
local CHAT_SCROLLBAR_W = 10
local CHAT_SCROLLBAR_GAP = 6
local CHAT_SCROLLBAR_MIN_THUMB_H = 22
local CHAT_SCROLL_SMOOTH_RATE = 14
local CHAT_SCROLL_DRAG_SMOOTH_RATE = 24
local CHAT_NEW_MESSAGE_ANIM_SEC = 0.20
local CHAT_CLOSE_BUTTON_SIZE = 20

local function t(key, vars)
  return I18n.t(key, vars)
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

local function lerp(fromValue, toValue, tValue)
  return fromValue + (toValue - fromValue) * tValue
end

local function easeOutCubic(tValue)
  local x = clamp(tValue, 0, 1)
  local oneMinus = 1 - x
  return 1 - (oneMinus * oneMinus * oneMinus)
end

local function pointInRect(x, y, rect)
  if not rect then
    return false
  end
  return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function setRect(rect, x, y, w, h)
  rect.x = x
  rect.y = y
  rect.w = w
  rect.h = h
end

function InGameChat.new(app, opts)
  opts = opts or {}

  local instance = {
    _app = app,
    _isOpen = false,
    _openProgress = 0,
    _openDurationSec = opts.openDurationSec or Constants.INGAME_CHAT_OPEN_SEC,
    _unreadCount = 0,
    _messageCap = opts.messageCap or Constants.INGAME_CHAT_MAX_MESSAGES,
    _messageList = {},
    _wrappedLineList = {},
    _wrapDirty = true,
    _lastWrapWidth = 0,
    _scrollOffsetLines = 0,
    _scrollOffsetTargetLines = 0,
    _isScrollbarDragging = false,
    _scrollbarDragOffsetY = 0,
    _newMessageAnimSec = CHAT_NEW_MESSAGE_ANIM_SEC,
    _lastLanguage = app and app.getLanguage and app:getLanguage() or "ko",
    _marginRight = opts.marginRight or Constants.INGAME_CHAT_MARGIN_RIGHT,
    _marginBottom = opts.marginBottom or Constants.INGAME_CHAT_MARGIN_BOTTOM,
    _barW = opts.barW or Constants.INGAME_CHAT_BAR_W,
    _barH = opts.barH or Constants.INGAME_CHAT_BAR_H,
    _panelW = opts.panelW or Constants.INGAME_CHAT_PANEL_W,
    _panelH = opts.panelH or Constants.INGAME_CHAT_PANEL_H,
    _panelGap = opts.panelGap or 8,
    _layout = {
      bar = {},
      panel = {},
      closeButton = {},
      history = {},
      scrollTrack = {},
      scrollThumb = {},
      input = {},
      send = {}
    }
  }
  setmetatable(instance, InGameChat)

  instance._textInput = TextInput.new({
    x = 0,
    y = 0,
    w = 240,
    h = 38,
    placeholder = "",
    maxChars = Constants.CHAT_MAX_LENGTH,
    wrapText = true,
    onEnter = function()
      instance:sendCurrentText()
    end
  })

  instance._sendButton = Button.new({
    x = 0,
    y = 0,
    w = 84,
    h = 38,
    label = "",
    onClick = function()
      instance:sendCurrentText()
    end
  })

  instance:refreshLocalizedUi()
  return instance
end

function InGameChat:refreshLocalizedUi()
  self._lastLanguage = self._app and self._app.getLanguage and self._app:getLanguage() or self._lastLanguage
  self._textInput.placeholder = ""
  self._sendButton.label = t("common.button.send")
end

function InGameChat:reset()
  self._isOpen = false
  self._openProgress = 0
  self._unreadCount = 0
  self._messageList = {}
  self._wrappedLineList = {}
  self._wrapDirty = true
  self._lastWrapWidth = 0
  self._scrollOffsetLines = 0
  self._scrollOffsetTargetLines = 0
  self._isScrollbarDragging = false
  self._scrollbarDragOffsetY = 0
  self._newMessageAnimSec = CHAT_NEW_MESSAGE_ANIM_SEC
  self._textInput:setText("")
  self._textInput.compositionText = ""
  self._textInput:setFocus(false)
end

function InGameChat:isInputBlocking()
  return self._isOpen
end

function InGameChat:open()
  self._isOpen = true
  self._unreadCount = 0
  self._scrollOffsetLines = 0
  self._scrollOffsetTargetLines = 0
  self._textInput.compositionText = ""
  self._textInput:setFocus(true)
end

function InGameChat:close()
  self._isOpen = false
  self._isScrollbarDragging = false
  self._textInput.compositionText = ""
  self._textInput:setFocus(false)
end

function InGameChat:closeImmediate()
  self:close()
  self._openProgress = 0
end

function InGameChat:getVisibleLineCount()
  local historyRect = self._layout.history
  local font = FontManager.getFont("small")
  local lineH = font:getHeight() + 2
  return math.max(1, math.floor((historyRect.h - 4) / lineH))
end

function InGameChat:getMaxScrollOffset()
  return math.max(0, #self._wrappedLineList - self:getVisibleLineCount())
end

function InGameChat:rebuildWrappedLinesIfNeeded()
  local historyRect = self._layout.history
  local wrapWidth = math.max(20, historyRect.w - 4)
  if (not self._wrapDirty) and self._lastWrapWidth == wrapWidth then
    return
  end

  local font = FontManager.getFont("small")
  local wrapped = {}
  for _, message in ipairs(self._messageList) do
    local _, lineList = font:getWrap(message, wrapWidth)
    if type(lineList) == "table" and #lineList > 0 then
      for _, line in ipairs(lineList) do
        wrapped[#wrapped + 1] = line
      end
    else
      wrapped[#wrapped + 1] = message
    end
  end
  self._wrappedLineList = wrapped
  self._lastWrapWidth = wrapWidth
  self._wrapDirty = false

  local maxScrollOffset = self:getMaxScrollOffset()
  self._scrollOffsetTargetLines = clamp(self._scrollOffsetTargetLines, 0, maxScrollOffset)
  self._scrollOffsetLines = clamp(self._scrollOffsetLines, 0, maxScrollOffset)
end

function InGameChat:updateScrollbarThumbRect()
  local track = self._layout.scrollTrack
  local thumb = self._layout.scrollThumb
  local maxScrollOffset = self:getMaxScrollOffset()
  local visibleCount = self:getVisibleLineCount()
  local totalCount = #self._wrappedLineList

  if track.h <= 1 then
    setRect(thumb, track.x, track.y, track.w, track.h)
    return
  end

  if maxScrollOffset <= 0 or totalCount <= 0 then
    setRect(thumb, track.x, track.y, track.w, track.h)
    return
  end

  local thumbH = math.max(CHAT_SCROLLBAR_MIN_THUMB_H, track.h * (visibleCount / totalCount))
  thumbH = math.min(track.h, thumbH)
  local maxTravel = track.h - thumbH
  local ratio = maxScrollOffset > 0 and (self._scrollOffsetLines / maxScrollOffset) or 0
  local thumbY = track.y + ratio * maxTravel
  setRect(thumb, track.x, thumbY, track.w, thumbH)
end

function InGameChat:setScrollFromThumbCenter(mouseY)
  local track = self._layout.scrollTrack
  local thumb = self._layout.scrollThumb
  local maxScrollOffset = self:getMaxScrollOffset()
  if maxScrollOffset <= 0 then
    self._scrollOffsetLines = 0
    self._scrollOffsetTargetLines = 0
    self:updateScrollbarThumbRect()
    return
  end

  local targetThumbY = mouseY - self._scrollbarDragOffsetY
  local minY = track.y
  local maxY = track.y + (track.h - thumb.h)
  targetThumbY = clamp(targetThumbY, minY, maxY)
  local ratio = (maxY > minY) and ((targetThumbY - minY) / (maxY - minY)) or 0
  self._scrollOffsetTargetLines = clamp(ratio * maxScrollOffset, 0, maxScrollOffset)
  self:updateScrollbarThumbRect()
end

function InGameChat:appendMessage(line)
  local text = tostring(line or "")
  if text == "" then
    return
  end
  self._messageList[#self._messageList + 1] = text
  while #self._messageList > self._messageCap do
    table.remove(self._messageList, 1)
  end
  local wasNearBottom = self._scrollOffsetTargetLines <= 0.5
  self._wrapDirty = true
  if wasNearBottom then
    self._scrollOffsetTargetLines = 0
  end
  self._newMessageAnimSec = 0
end

function InGameChat:sendCurrentText()
  local compositionText = self._textInput.compositionText or ""
  if compositionText ~= "" then
    self._textInput:setText(self._textInput:getText() .. compositionText)
    self._textInput.compositionText = ""
  end

  local text = self._textInput:getText()
  if text == "" then
    return false
  end
  if self._app and self._app.sendChat then
    self._app:sendChat(text)
  end
  self._textInput:setText("")
  self._textInput.compositionText = ""
  return true
end

function InGameChat:updateLayout()
  local barX = Constants.BASE_WORLD_W - self._marginRight - self._barW
  local barY = Constants.BASE_WORLD_H - self._marginBottom - self._barH
  setRect(self._layout.bar, barX, barY, self._barW, self._barH)

  local openPanelY = barY + self._barH - self._panelH
  local closedPanelY = Constants.BASE_WORLD_H + 4
  local easedProgress = easeOutCubic(self._openProgress)
  local panelY = lerp(closedPanelY, openPanelY, easedProgress)
  local panelX = Constants.BASE_WORLD_W - self._marginRight - self._panelW
  setRect(self._layout.panel, panelX, panelY, self._panelW, self._panelH)
  setRect(
    self._layout.closeButton,
    panelX + self._panelW - 12 - CHAT_CLOSE_BUTTON_SIZE,
    panelY + 6,
    CHAT_CLOSE_BUTTON_SIZE,
    CHAT_CLOSE_BUTTON_SIZE
  )

  local panelPadding = 12
  local headerH = 24
  local inputH = FontManager.getFont("ui"):getHeight() + 12
  local inputGapTop = 10
  local sendW = self._sendButton.w
  local sendGap = 8
  local inputY = panelY + self._panelH - panelPadding - inputH
  setRect(self._layout.input, panelX + panelPadding, inputY, self._panelW - panelPadding * 2 - sendW - sendGap, inputH)
  setRect(self._layout.send, self._layout.input.x + self._layout.input.w + sendGap, inputY, sendW, inputH)

  local historyY = panelY + panelPadding + headerH
  local historyBottomY = inputY - inputGapTop
  local trackX = panelX + self._panelW - panelPadding - CHAT_SCROLLBAR_W
  local trackH = math.max(0, historyBottomY - historyY)
  setRect(self._layout.scrollTrack, trackX, historyY, CHAT_SCROLLBAR_W, trackH)
  setRect(
    self._layout.history,
    panelX + panelPadding,
    historyY,
    math.max(0, self._panelW - panelPadding * 2 - CHAT_SCROLLBAR_W - CHAT_SCROLLBAR_GAP),
    trackH
  )

  self._textInput.x = self._layout.input.x
  self._textInput.y = self._layout.input.y
  self._textInput.w = self._layout.input.w
  self._textInput.h = self._layout.input.h
  self._sendButton.x = self._layout.send.x
  self._sendButton.y = self._layout.send.y
  self._sendButton.h = self._layout.send.h
end

function InGameChat:update(dt)
  if self._app and self._app.getLanguage and self._lastLanguage ~= self._app:getLanguage() then
    self:refreshLocalizedUi()
  end

  local target = self._isOpen and 1 or 0
  if self._openProgress ~= target then
    local duration = math.max(0.001, self._openDurationSec)
    local delta = dt / duration
    if target > self._openProgress then
      self._openProgress = math.min(target, self._openProgress + delta)
    else
      self._openProgress = math.max(target, self._openProgress - delta)
    end
  end
  self:updateLayout()
  self:rebuildWrappedLinesIfNeeded()
  if self._newMessageAnimSec < CHAT_NEW_MESSAGE_ANIM_SEC then
    self._newMessageAnimSec = math.min(CHAT_NEW_MESSAGE_ANIM_SEC, self._newMessageAnimSec + dt)
  end

  local maxScrollOffset = self:getMaxScrollOffset()
  self._scrollOffsetTargetLines = clamp(self._scrollOffsetTargetLines, 0, maxScrollOffset)
  self._scrollOffsetLines = clamp(self._scrollOffsetLines, 0, maxScrollOffset)
  local smoothRate = self._isScrollbarDragging and CHAT_SCROLL_DRAG_SMOOTH_RATE or CHAT_SCROLL_SMOOTH_RATE
  local lerpAlpha = math.min(1, dt * smoothRate)
  self._scrollOffsetLines = self._scrollOffsetLines + (self._scrollOffsetTargetLines - self._scrollOffsetLines) * lerpAlpha
  if math.abs(self._scrollOffsetTargetLines - self._scrollOffsetLines) < 0.001 then
    self._scrollOffsetLines = self._scrollOffsetTargetLines
  end

  self:updateScrollbarThumbRect()
  self._sendButton.isEnabled = self._textInput:getText() ~= ""
end

function InGameChat:drawHistory()
  local historyRect = self._layout.history
  if historyRect.h <= 2 then
    return
  end

  local font = FontManager.getFont("small")
  local lineH = font:getHeight() + 2
  self:rebuildWrappedLinesIfNeeded()

  local totalLineCount = #self._wrappedLineList
  local visibleCount = self:getVisibleLineCount()
  local maxScrollOffset = math.max(0, totalLineCount - visibleCount)
  self._scrollOffsetLines = clamp(self._scrollOffsetLines, 0, maxScrollOffset)
  local offsetIntegral = math.floor(self._scrollOffsetLines)
  local offsetFraction = self._scrollOffsetLines - offsetIntegral
  local endIndex = totalLineCount - offsetIntegral
  if endIndex <= 0 then
    return
  end
  local startIndex = math.max(1, endIndex - visibleCount + 1)
  local drawCount = math.max(0, endIndex - startIndex + 1)

  love.graphics.setFont(font)
  local progress = clamp(self._newMessageAnimSec / CHAT_NEW_MESSAGE_ANIM_SEC, 0, 1)
  local riseOffset = (1 - progress) * lineH
  love.graphics.setColor(1, 1, 1, 0.70 + 0.30 * progress)

  local drawY = historyRect.y + historyRect.h - (drawCount * lineH) + (offsetFraction * lineH) + riseOffset
  for index = startIndex, endIndex do
    love.graphics.print(self._wrappedLineList[index], historyRect.x + 2, drawY)
    drawY = drawY + lineH
  end
end

function InGameChat:drawScrollbar()
  local track = self._layout.scrollTrack
  local thumb = self._layout.scrollThumb
  if track.h <= 2 then
    return
  end

  love.graphics.setColor(0.08, 0.10, 0.14, 0.85)
  love.graphics.rectangle("fill", track.x, track.y, track.w, track.h, 4, 4)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", track.x, track.y, track.w, track.h, 4, 4)

  local hasScrollable = self:getMaxScrollOffset() > 0
  local thumbColor = hasScrollable and { 0.65, 0.73, 0.92, 0.95 } or { 0.40, 0.46, 0.58, 0.80 }
  love.graphics.setColor(thumbColor)
  love.graphics.rectangle("fill", thumb.x, thumb.y, thumb.w, thumb.h, 4, 4)
end

function InGameChat:draw(mouseX, mouseY)
  self:updateLayout()
  local barRect = self._layout.bar
  local panelRect = self._layout.panel
  local closeRect = self._layout.closeButton

  UIDraw.drawPanel(barRect, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.chat.toggle_label"), barRect.x, barRect.y + (barRect.h - FontManager.getFont("ui"):getHeight()) * 0.5, barRect.w, "center")

  if (not self._isOpen) and self._unreadCount > 0 then
    love.graphics.setColor(0.90, 0.20, 0.20, 1.0)
    love.graphics.circle("fill", barRect.x + barRect.w - 12, barRect.y + 10, 5)
  end

  if self._openProgress <= 0.001 then
    return
  end

  UIDraw.drawPanel(panelRect, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("match.chat.panel_title"), panelRect.x + 12, panelRect.y + 9, panelRect.w - 24, "left")

  local isCloseHovered = pointInRect(mouseX, mouseY, closeRect)
  love.graphics.setColor(isCloseHovered and 0.82 or 0.72, 0.20, 0.20, 1.0)
  love.graphics.rectangle("fill", closeRect.x, closeRect.y, closeRect.w, closeRect.h, 4, 4)
  love.graphics.setColor(1.0, 0.92, 0.92, 1.0)
  love.graphics.setLineWidth(2)
  love.graphics.line(closeRect.x + 6, closeRect.y + 6, closeRect.x + closeRect.w - 6, closeRect.y + closeRect.h - 6)
  love.graphics.line(closeRect.x + closeRect.w - 6, closeRect.y + 6, closeRect.x + 6, closeRect.y + closeRect.h - 6)
  love.graphics.setLineWidth(1)

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.line(panelRect.x + 12, panelRect.y + 30, panelRect.x + panelRect.w - 12, panelRect.y + 30)

  self:drawHistory()
  self:drawScrollbar()

  self._textInput:draw()
  self._sendButton:draw(mouseX, mouseY)
end

function InGameChat:mousepressed(mouseX, mouseY, button)
  self:updateLayout()
  self._sendButton.isEnabled = self._textInput:getText() ~= ""

  if self._isOpen then
    if button ~= 1 then
      return true
    end

    if pointInRect(mouseX, mouseY, self._layout.closeButton) then
      self:close()
      return true
    end

    if pointInRect(mouseX, mouseY, self._layout.scrollThumb) then
      self._isScrollbarDragging = true
      self._scrollbarDragOffsetY = mouseY - self._layout.scrollThumb.y
      self._textInput:setFocus(false)
      return true
    end
    if pointInRect(mouseX, mouseY, self._layout.scrollTrack) then
      self._isScrollbarDragging = true
      self._scrollbarDragOffsetY = self._layout.scrollThumb.h * 0.5
      self:setScrollFromThumbCenter(mouseY)
      self._textInput:setFocus(false)
      return true
    end

    if self._sendButton.isEnabled and self._sendButton:isHovered(mouseX, mouseY) then
      self._sendButton:onClick()
      return true
    end

    if self._textInput:mousepressed(mouseX, mouseY, button) then
      return true
    end

    if pointInRect(mouseX, mouseY, self._layout.panel) then
      self._textInput:setFocus(false)
      return true
    end

    self:close()
    return true
  end

  if button == 1 and pointInRect(mouseX, mouseY, self._layout.bar) then
    self:open()
    return true
  end

  return false
end

function InGameChat:wheelmoved(mouseX, mouseY, _dx, dy)
  if not self._isOpen then
    return false
  end

  self:updateLayout()
  self:rebuildWrappedLinesIfNeeded()

  if not pointInRect(mouseX, mouseY, self._layout.panel) then
    return true
  end

  local visibleCount = self:getVisibleLineCount()
  local maxScrollOffset = math.max(0, #self._wrappedLineList - visibleCount)
  if maxScrollOffset <= 0 then
    return true
  end

  local scrollStep = math.max(1, Constants.INGAME_CHAT_SCROLL_LINES_PER_TICK or 3)
  if dy > 0 then
    self._scrollOffsetTargetLines = clamp(self._scrollOffsetTargetLines + scrollStep, 0, maxScrollOffset)
  elseif dy < 0 then
    self._scrollOffsetTargetLines = clamp(self._scrollOffsetTargetLines - scrollStep, 0, maxScrollOffset)
  end
  self:updateScrollbarThumbRect()
  return true
end

function InGameChat:mousemoved(mouseX, mouseY, _dx, _dy)
  if (not self._isOpen) or (not self._isScrollbarDragging) then
    return false
  end
  self:setScrollFromThumbCenter(mouseY)
  return true
end

function InGameChat:mousereleased(_mouseX, _mouseY, button)
  if button ~= 1 then
    return false
  end
  if not self._isOpen then
    return false
  end
  if self._isScrollbarDragging then
    self._isScrollbarDragging = false
    return true
  end
  return false
end

function InGameChat:keypressed(key)
  if (not self._isOpen) and (key == "return" or key == "kpenter") then
    self:open()
    return true
  end

  if not self._isOpen then
    return false
  end

  if key == "escape" then
    self:close()
    return true
  end

  if key == "return" or key == "kpenter" then
    if self._textInput.isFocused then
      self:sendCurrentText()
    else
      self._textInput:setFocus(true)
    end
    return true
  end

  if self._textInput:keypressed(key) then
    return true
  end

  return true
end

function InGameChat:textinput(text)
  if not self._isOpen then
    return false
  end
  if self._textInput.isFocused then
    self._textInput:textinput(text)
  end
  return true
end

function InGameChat:textedited(text, start, length)
  if not self._isOpen then
    return false
  end
  if self._textInput.isFocused then
    self._textInput:textedited(text, start, length)
  end
  return true
end

function InGameChat:onServerEnvelope(envelope)
  if type(envelope) ~= "table" then
    return
  end

  if envelope.type == "chat.message" then
    local payload = envelope.payload or {}
    self:appendMessage(t("match.chat.line", {
      nickname = tostring(payload.nickname or "?"),
      text = tostring(payload.text or "")
    }))
    if self._isOpen then
      self._unreadCount = 0
    else
      self._unreadCount = self._unreadCount + 1
    end
    return
  end

  if envelope.type == "chat.denied" then
    local payload = envelope.payload or {}
    self:appendMessage(t("match.chat.system_denied", {
      reason = tostring(payload.reason or t("common.unknown"))
    }))
    if self._isOpen then
      self._unreadCount = 0
    else
      self._unreadCount = self._unreadCount + 1
    end
  end
end

function InGameChat:onWsEnvelope(envelope)
  -- Legacy alias: use onServerEnvelope instead.
  self:onServerEnvelope(envelope)
end

function InGameChat:onFocusLost()
  self._textInput:setFocus(false)
end

return InGameChat
