--[[
파일명: button.lua
모듈명: Button

역할:
- 간단한 사각 버튼 UI 제공
- hover/disabled 상태 렌더링 및 hit-test 처리

외부에서 사용 가능한 함수:
- Button.new(params)
- Button:isHovered(mouseX, mouseY)
- Button:draw(mouseX, mouseY)
- Button:onClick()

주의:
- 입력 좌표는 world 좌표여야 한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local Button = {}
Button.__index = Button

function Button.new(params)
  local instance = {
    x = params.x or 0,
    y = params.y or 0,
    w = params.w or Constants.BUTTON_W,
    h = params.h or Constants.BUTTON_H,
    label = params.label or "Button",
    onClick = params.onClick or function() end,
    isEnabled = params.isEnabled ~= false,
    color = params.color or Constants.COLOR_BUTTON
  }
  return setmetatable(instance, Button)
end

function Button:isHovered(mouseX, mouseY)
  return mouseX >= self.x and mouseX <= self.x + self.w and mouseY >= self.y and mouseY <= self.y + self.h
end

function Button:draw(mouseX, mouseY)
  local drawColor = self.color
  if not self.isEnabled then
    drawColor = Constants.COLOR_BUTTON_DISABLED
  elseif self:isHovered(mouseX, mouseY) then
    drawColor = Constants.COLOR_BUTTON_HOVER
  end

  love.graphics.setColor(drawColor)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 8, 8)

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.printf(self.label, self.x, self.y + self.h * 0.32, self.w, "center")
end

return Button
