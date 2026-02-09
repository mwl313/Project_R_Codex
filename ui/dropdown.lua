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
- Dropdown:mousepressed(mouseX, mouseY, button)
- Dropdown:draw(mouseX, mouseY)

주의:
- 입력 좌표는 world 좌표여야 한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local Dropdown = {}
Dropdown.__index = Dropdown

local function isPointInside(x, y, w, h, pointX, pointY)
  return pointX >= x and pointX <= x + w and pointY >= y and pointY <= y + h
end

function Dropdown.new(params)
  local instance = {
    x = params.x or 0,
    y = params.y or 0,
    w = params.w or 260,
    h = params.h or 44,
    optionList = params.optionList or {},
    selectedValue = params.selectedValue,
    isEnabled = params.isEnabled ~= false,
    isExpanded = false,
    onChanged = params.onChanged
  }
  setmetatable(instance, Dropdown)
  return instance
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

function Dropdown:getOptionIndexAt(mouseX, mouseY)
  if not self.isExpanded then
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
    self.isExpanded = not self.isExpanded
    return true
  end

  local optionIndex = self:getOptionIndexAt(mouseX, mouseY)
  if optionIndex then
    local option = self.optionList[optionIndex]
    self.selectedValue = option.value
    self.isExpanded = false
    if self.onChanged then
      self.onChanged(option.value)
    end
    return true
  end

  if self.isExpanded then
    self.isExpanded = false
  end
  return false
end

function Dropdown:draw(mouseX, mouseY)
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

  if not self.isExpanded then
    return
  end

  for index, option in ipairs(self.optionList) do
    local optionY = self.y + self.h * index
    local optionColor = Constants.COLOR_BUTTON
    if option.value == self.selectedValue then
      optionColor = Constants.COLOR_BUTTON_SELECTED
    elseif isPointInside(self.x, optionY, self.w, self.h, mouseX, mouseY) then
      optionColor = Constants.COLOR_BUTTON_HOVER
    end

    love.graphics.setColor(optionColor)
    love.graphics.rectangle("fill", self.x, optionY, self.w, self.h, 8, 8)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", self.x, optionY, self.w, self.h, 8, 8)

    local optionTextY = optionY + (self.h - font:getHeight()) * 0.5
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf(option.label, self.x + 14, optionTextY, self.w - 28, "left")
  end
end

return Dropdown
