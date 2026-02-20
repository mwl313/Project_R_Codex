--[[
파일명: dropdown.lua
모듈명: Dropdown

역할:
- 단일 선택 드롭다운 UI 제공
- 접힘/펼침 상태에서 항목 선택 처리

외부에서 사용 가능한 함수:
- Dropdown.new(params)
- Dropdown:setSelectedValue(value)
- Dropdown:getSelectedValue()
- Dropdown:getSelectedLabel()
- Dropdown:isOpen()
- Dropdown:isVisible()
- Dropdown:collapse()
- Dropdown:mousepressed(mouseX, mouseY, button)
- Dropdown:draw(mouseX, mouseY, mode)
- Dropdown.drawExpandedLayer(dropdownList, mouseX, mouseY)
- Dropdown.handleExclusiveMousePressed(dropdownList, mouseX, mouseY, button)

주의:
- 입력 좌표는 world 좌표여야 한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local Dropdown = {}
Dropdown.__index = Dropdown
local nextExpandedOrder = 0
local EPSILON = 0.0001

local function getNowSec()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.clock()
end

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function easeOutCubic(value)
  local t = clamp01(value)
  local inv = 1 - t
  return 1 - inv * inv * inv
end

local function easeInCubic(value)
  local t = clamp01(value)
  return t * t * t
end

local function isPointInside(x, y, w, h, pointX, pointY)
  return pointX >= x and pointX <= x + w and pointY >= y and pointY <= y + h
end

local function bumpExpandedOrder(instance)
  nextExpandedOrder = nextExpandedOrder + 1
  instance._expandedOrder = nextExpandedOrder
end

function Dropdown.new(params)
  local openSec = (params and params.openAnimSec) or Constants.DROPDOWN_OPEN_SEC or 0.16
  local closeSec = (params and params.closeAnimSec) or Constants.DROPDOWN_CLOSE_SEC or 0.13
  local instance = {
    x = params.x or 0,
    y = params.y or 0,
    w = params.w or 260,
    h = params.h or 44,
    optionList = params.optionList or {},
    selectedValue = params.selectedValue,
    isEnabled = params.isEnabled ~= false,
    isExpanded = false,
    _expandedOrder = 0,
    _animProgress = 0,
    _animFrom = 0,
    _animTo = 0,
    _animStartSec = nil,
    _animDurationSec = 0,
    _openAnimSec = openSec,
    _closeAnimSec = closeSec,
    onChanged = params.onChanged
  }
  setmetatable(instance, Dropdown)
  return instance
end

function Dropdown:_updateAnimProgress()
  if not self._animStartSec then
    return self._animProgress or 0
  end

  local durationSec = self._animDurationSec
  if durationSec <= 0 then
    self._animProgress = self._animTo
    self._animStartSec = nil
    return self._animProgress
  end

  local elapsed = getNowSec() - self._animStartSec
  local t = clamp01(elapsed / durationSec)
  local eased = self._animTo > self._animFrom and easeOutCubic(t) or easeInCubic(t)
  self._animProgress = self._animFrom + (self._animTo - self._animFrom) * eased

  if t >= 1 then
    self._animProgress = self._animTo
    self._animStartSec = nil
  end
  return self._animProgress
end

function Dropdown:_setExpanded(expanded)
  local current = self:_updateAnimProgress()
  local target = expanded and 1 or 0
  self.isExpanded = expanded

  if math.abs(current - target) <= EPSILON then
    self._animProgress = target
    self._animFrom = target
    self._animTo = target
    self._animStartSec = nil
    self._animDurationSec = 0
    return
  end

  self._animFrom = current
  self._animTo = target
  self._animStartSec = getNowSec()
  self._animDurationSec = expanded and self._openAnimSec or self._closeAnimSec
end

function Dropdown:setSelectedValue(value)
  self.selectedValue = value
end

function Dropdown:getSelectedValue()
  return self.selectedValue
end

function Dropdown:getSelectedLabel()
  for _, option in ipairs(self.optionList) do
    if option.value == self.selectedValue then
      return option.label
    end
  end
  if #self.optionList > 0 then
    return self.optionList[1].label
  end
  return ""
end

function Dropdown:isOpen()
  return self.isExpanded
end

function Dropdown:isVisible()
  return self:_updateAnimProgress() > EPSILON
end

function Dropdown:getExpandedOrder()
  return self._expandedOrder or 0
end

function Dropdown:collapse()
  self:_setExpanded(false)
end

function Dropdown:getOptionIndexAt(mouseX, mouseY)
  if not self.isExpanded then
    return nil
  end
  if self:_updateAnimProgress() < 0.98 then
    return nil
  end
  for index = 1, #self.optionList do
    local optionY = self.y + self.h * index
    if isPointInside(self.x, optionY, self.w, self.h, mouseX, mouseY) then
      return index
    end
  end
  return nil
end

function Dropdown:mousepressed(mouseX, mouseY, button)
  if button ~= 1 or not self.isEnabled then
    return false
  end

  if isPointInside(self.x, self.y, self.w, self.h, mouseX, mouseY) then
    local willExpand = not self.isExpanded
    self:_setExpanded(willExpand)
    if willExpand then
      bumpExpandedOrder(self)
    end
    return true
  end

  local optionIndex = self:getOptionIndexAt(mouseX, mouseY)
  if optionIndex then
    local option = self.optionList[optionIndex]
    self.selectedValue = option.value
    self:_setExpanded(false)
    if self.onChanged then
      self.onChanged(option.value)
    end
    return true
  end

  if self.isExpanded then
    self:_setExpanded(false)
  end
  return false
end

local function drawTrigger(self, mouseX, mouseY)
  local font = FontManager.getFont("ui")
  love.graphics.setFont(font)

  local baseColor = Constants.COLOR_BUTTON
  if not self.isEnabled then
    baseColor = Constants.COLOR_BUTTON_DISABLED
  elseif isPointInside(self.x, self.y, self.w, self.h, mouseX, mouseY) then
    baseColor = Constants.COLOR_BUTTON_HOVER
  end

  love.graphics.setColor(baseColor)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 8, 8)

  local textY = self.y + (self.h - font:getHeight()) * 0.5
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(self:getSelectedLabel(), self.x + 14, textY, self.w - 42, "left")
  love.graphics.printf(self.isExpanded and "^" or "v", self.x + self.w - 28, textY, 16, "center")
end

local function drawExpandedList(self, mouseX, mouseY)
  local progress = self:_updateAnimProgress()
  if progress <= EPSILON then
    return
  end

  local font = FontManager.getFont("ui")
  love.graphics.setFont(font)
  local alpha = progress
  local triggerBottomY = self.y + self.h

  local optionCount = #self.optionList
  if optionCount > 0 then
    local listY = triggerBottomY
    local listH = self.h * optionCount * progress
    -- Expanded list background is fully opaque for readability.
    love.graphics.setColor(Constants.COLOR_PANEL[1], Constants.COLOR_PANEL[2], Constants.COLOR_PANEL[3], alpha)
    love.graphics.rectangle("fill", self.x, listY, self.w, listH, 8, 8)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], alpha)
    love.graphics.rectangle("line", self.x, listY, self.w, listH, 8, 8)
  end

  for index, option in ipairs(self.optionList) do
    local finalOptionY = self.y + self.h * index
    local optionY = triggerBottomY + (finalOptionY - triggerBottomY) * progress
    local optionColor = Constants.COLOR_BUTTON
    local isHovering = self.isExpanded and progress >= 0.98 and isPointInside(self.x, optionY, self.w, self.h, mouseX, mouseY)
    if option.value == self.selectedValue then
      optionColor = Constants.COLOR_BUTTON_SELECTED
    elseif isHovering then
      optionColor = Constants.COLOR_BUTTON_HOVER
    end

    love.graphics.setColor(optionColor[1], optionColor[2], optionColor[3], alpha)
    love.graphics.rectangle("fill", self.x, optionY, self.w, self.h)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], alpha)
    love.graphics.rectangle("line", self.x, optionY, self.w, self.h)

    local optionTextY = optionY + (self.h - font:getHeight()) * 0.5
    love.graphics.setColor(Constants.COLOR_TEXT[1], Constants.COLOR_TEXT[2], Constants.COLOR_TEXT[3], alpha)
    love.graphics.printf(option.label, self.x + 14, optionTextY, self.w - 28, "left")
  end
end

function Dropdown:draw(mouseX, mouseY, mode)
  if mode == "collapsed" then
    drawTrigger(self, mouseX, mouseY)
    return
  end
  if mode == "expanded" then
    drawExpandedList(self, mouseX, mouseY)
    return
  end

  drawTrigger(self, mouseX, mouseY)
  drawExpandedList(self, mouseX, mouseY)
end

function Dropdown.drawExpandedLayer(dropdownList, mouseX, mouseY)
  local expandedList = {}
  for _, dropdown in ipairs(dropdownList) do
    if dropdown:isVisible() then
      expandedList[#expandedList + 1] = dropdown
    end
  end

  table.sort(expandedList, function(a, b)
    return a:getExpandedOrder() < b:getExpandedOrder()
  end)

  for _, dropdown in ipairs(expandedList) do
    dropdown:draw(mouseX, mouseY, "expanded")
  end
end

function Dropdown.handleExclusiveMousePressed(dropdownList, mouseX, mouseY, button)
  local processList = {}
  for _, dropdown in ipairs(dropdownList) do
    processList[#processList + 1] = dropdown
  end

  table.sort(processList, function(a, b)
    return a:getExpandedOrder() > b:getExpandedOrder()
  end)

  for _, dropdown in ipairs(processList) do
    if dropdown:mousepressed(mouseX, mouseY, button) then
      for _, other in ipairs(dropdownList) do
        if other ~= dropdown then
          other:collapse()
        end
      end
      return dropdown
    end
  end

  for _, dropdown in ipairs(dropdownList) do
    dropdown:collapse()
  end
  return nil
end

return Dropdown
