--[[
파일명: single_discard_overlay.lua
모듈명: SingleDiscardOverlay

역할:
- 싱글 보상 단계에서 덱 초과(> 15) 시 강제 카드 버리기 모달을 표시한다.
- 취소는 허용하지 않으며, 유효한 1장 버리기 후에만 종료된다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local UIDraw = require("ui.ui_draw")
local OverlayTransition = require("ui.overlay_transition")

local SingleDiscardOverlay = {}
SingleDiscardOverlay.__index = SingleDiscardOverlay

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

local function buildCardCountMap(deckCards)
  local countMap = {}
  for _, cardId in ipairs(deckCards or {}) do
    local key = tostring(cardId or "")
    countMap[key] = (countMap[key] or 0) + 1
  end
  return countMap
end

function SingleDiscardOverlay.new(params)
  local option = params or {}
  local deckCards = {}
  for _, cardId in ipairs(option.deckCards or {}) do
    deckCards[#deckCards + 1] = tostring(cardId or "")
  end

  local panelW = Constants.BASE_WORLD_W * Constants.OVERLAY_PANEL_RATIO
  local panelH = Constants.BASE_WORLD_H * Constants.OVERLAY_PANEL_RATIO
  local panelX = (Constants.BASE_WORLD_W - panelW) * 0.5
  local panelY = (Constants.BASE_WORLD_H - panelH) * 0.5

  local instance = {
    _titleText = tostring(option.titleText or t("single.discard_overlay.title")),
    _messageText = tostring(option.messageText or t("single.discard_overlay.message", {
      maxSize = tostring(option.maxDeckSize or 15)
    })),
    _deckCards = deckCards,
    _cardCountMap = buildCardCountMap(deckCards),
    _resolveCardName = option.resolveCardName or function(cardId)
      return tostring(cardId or "")
    end,
    _onDiscard = option.onDiscard or function()
      return false
    end,
    _panelX = panelX,
    _panelY = panelY,
    _panelW = panelW,
    _panelH = panelH,
    _listX = panelX + 48,
    _listY = panelY + 152,
    _listW = panelW - 96,
    _listH = panelH - 252,
    _rowH = 30,
    _scrollRow = 0,
    _selectedIndex = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _isCompleted = false,
    _transition = OverlayTransition.new({
      targetY = panelY,
      panelH = panelH,
      worldH = Constants.BASE_WORLD_H,
      maxDimAlpha = Constants.COLOR_OVERLAY_DIM[4] or 0.56,
      enterDurationSec = Constants.OVERLAY_ENTER_SEC,
      exitDurationSec = Constants.OVERLAY_EXIT_SEC
    }),
    _confirmButton = nil
  }
  setmetatable(instance, SingleDiscardOverlay)
  instance._confirmButton = Button.new({
    x = panelX + panelW - 188,
    y = panelY + panelH - 66,
    w = 140,
    h = 40,
    label = t("single.discard_overlay.button.confirm"),
    onClick = function()
      instance:confirmDiscard()
    end
  })
  instance._transition:open()
  return instance
end

function SingleDiscardOverlay:isCompleted()
  return self._isCompleted
end

function SingleDiscardOverlay:isInteractive()
  return self._transition:isInteractive()
end

function SingleDiscardOverlay:update(dt)
  self._transition:update(dt)
end

function SingleDiscardOverlay:getVisibleRowCount()
  return math.max(1, math.floor(self._listH / self._rowH))
end

function SingleDiscardOverlay:getMaxScrollRow()
  local maxScroll = #self._deckCards - self:getVisibleRowCount()
  if maxScroll < 0 then
    return 0
  end
  return maxScroll
end

function SingleDiscardOverlay:scrollBy(deltaRow)
  self._scrollRow = clamp(self._scrollRow + deltaRow, 0, self:getMaxScrollRow())
end

function SingleDiscardOverlay:getRowRectByVisualIndex(visualIndex)
  local y = self._listY + (visualIndex - 1) * self._rowH
  return self._listX, y, self._listW, self._rowH - 2
end

function SingleDiscardOverlay:getDeckIndexByVisualIndex(visualIndex)
  return self._scrollRow + visualIndex
end

function SingleDiscardOverlay:confirmDiscard()
  if not self._selectedIndex then
    self._statusText = t("single.discard_overlay.status.select_required")
    self._statusColor = Constants.COLOR_DANGER
    return false
  end

  local isDiscarded, reasonText = self._onDiscard(self._selectedIndex)
  if not isDiscarded then
    self._statusText = tostring(reasonText or t("single.discard_overlay.status.discard_failed"))
    self._statusColor = Constants.COLOR_DANGER
    return false
  end

  self._isCompleted = true
  return true
end

function SingleDiscardOverlay:draw(mouseX, mouseY)
  local dimColor = Constants.COLOR_OVERLAY_DIM
  love.graphics.setColor(dimColor[1], dimColor[2], dimColor[3], self._transition:getDimAlpha())
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)

  local panelOffsetY = self._transition:getPanelY() - self._panelY
  local adjustedMouseY = mouseY - panelOffsetY

  love.graphics.push()
  love.graphics.translate(0, panelOffsetY)

  UIDraw.drawPanel({
    x = self._panelX,
    y = self._panelY,
    w = self._panelW,
    h = self._panelH
  }, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(self._titleText, self._panelX, self._panelY + 28, self._panelW, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(self._messageText, self._panelX + 36, self._panelY + 82, self._panelW - 72, "center")

  love.graphics.setColor(0.10, 0.12, 0.18, 0.86)
  love.graphics.rectangle("fill", self._listX, self._listY, self._listW, self._listH, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._listX, self._listY, self._listW, self._listH, 8, 8)

  love.graphics.setScissor(self._listX, self._listY, self._listW, self._listH)
  local visibleCount = self:getVisibleRowCount()
  for visualIndex = 1, visibleCount do
    local deckIndex = self:getDeckIndexByVisualIndex(visualIndex)
    local cardId = self._deckCards[deckIndex]
    if cardId then
      local x, y, w, h = self:getRowRectByVisualIndex(visualIndex)
      local isHovered = mouseX >= x and mouseX <= x + w and adjustedMouseY >= y and adjustedMouseY <= y + h
      local isSelected = self._selectedIndex == deckIndex
      local alpha = isSelected and 0.34 or (isHovered and 0.20 or 0.10)
      love.graphics.setColor(0.23, 0.36, 0.58, alpha)
      love.graphics.rectangle("fill", x + 4, y, w - 8, h, 6, 6)

      local inDeckCount = self._cardCountMap[cardId] or 1
      love.graphics.setFont(FontManager.getFont("small"))
      love.graphics.setColor(Constants.COLOR_TEXT)
      love.graphics.printf(
        string.format("%02d. %s  x%d", deckIndex, self._resolveCardName(cardId), inDeckCount),
        x + 14,
        y + 5,
        w - 28,
        "left"
      )
    end
  end
  love.graphics.setScissor()

  self._confirmButton.isEnabled = self._selectedIndex ~= nil
  self._confirmButton:draw(mouseX, adjustedMouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, self._panelX + 16, self._panelY + self._panelH - 110, self._panelW - 32, "center")

  love.graphics.pop()
end

function SingleDiscardOverlay:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return true
  end
  if not self._transition:isInteractive() then
    return true
  end

  local panelOffsetY = self._transition:getPanelY() - self._panelY
  local adjustedMouseY = mouseY - panelOffsetY

  local visibleCount = self:getVisibleRowCount()
  for visualIndex = 1, visibleCount do
    local deckIndex = self:getDeckIndexByVisualIndex(visualIndex)
    local cardId = self._deckCards[deckIndex]
    if cardId then
      local x, y, w, h = self:getRowRectByVisualIndex(visualIndex)
      if mouseX >= x and mouseX <= x + w and adjustedMouseY >= y and adjustedMouseY <= y + h then
        self._selectedIndex = deckIndex
        self._statusText = t("single.discard_overlay.status.selected", {
          card = self._resolveCardName(cardId)
        })
        self._statusColor = Constants.COLOR_TEXT_SUB
        return true
      end
    end
  end

  if self._confirmButton:isHovered(mouseX, adjustedMouseY) then
    self._confirmButton:onClick()
    return true
  end

  return true
end

function SingleDiscardOverlay:wheelmoved(_x, y)
  if not self._transition:isInteractive() then
    return true
  end
  if y > 0 then
    self:scrollBy(-1)
  elseif y < 0 then
    self:scrollBy(1)
  end
  return true
end

function SingleDiscardOverlay:keypressed(key)
  if key == "escape" then
    return true
  end
  if not self._transition:isInteractive() then
    return true
  end
  if key == "up" then
    self:scrollBy(-1)
    return true
  end
  if key == "down" then
    self:scrollBy(1)
    return true
  end
  if key == "return" or key == "kpenter" then
    self:confirmDiscard()
    return true
  end
  return false
end

return SingleDiscardOverlay
