--[[
파일명: card_widget.lua
모듈명: CardWidget

역할:
- 인게임 카드 핸드에서 단일 카드 렌더링/히트테스트를 담당한다.
- 현재는 primitive 도형 기반이며, 추후 카드 이미지 에셋으로 교체하기 위한 교체 지점이다.

외부에서 사용 가능한 함수:
- CardWidget.hitTest(card, mouseX, mouseY)
- CardWidget.draw(card)
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local CardWidget = {}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function getHalfSize(card)
  local scale = card.scale or 1.0
  local width = (card.w or Constants.CARD_W) * scale
  local height = (card.h or Constants.CARD_H) * scale
  return width * 0.5, height * 0.5
end

function CardWidget.hitTest(card, mouseX, mouseY)
  local halfW, halfH = getHalfSize(card)
  local x = card.x or 0
  local y = card.y or 0
  return mouseX >= x - halfW
    and mouseX <= x + halfW
    and mouseY >= y - halfH
    and mouseY <= y + halfH
end

function CardWidget.draw(card)
  local x = card.x or 0
  local y = card.y or 0
  local width = card.w or Constants.CARD_W
  local height = card.h or Constants.CARD_H
  local scale = card.scale or 1.0
  local alpha = clamp(card.alpha or 1.0, 0, 1)
  local isFaceUp = card.isFaceUp ~= false
  local isHovered = card.isHovered == true
  local isDragged = card.isDragged == true
  local isDisabled = card.isDisabled == true
  local isSelected = card.isSelected == true

  local baseFill
  if isFaceUp then
    baseFill = { 0.89, 0.90, 0.94, alpha }
  else
    baseFill = { 0.22, 0.28, 0.41, alpha }
  end
  if isDisabled then
    baseFill = { 0.36, 0.38, 0.42, alpha }
  end

  local borderColor = Constants.COLOR_PANEL_BORDER
  if isSelected then
    borderColor = { 0.94, 0.82, 0.36, alpha }
  elseif isHovered then
    borderColor = { 0.86, 0.94, 1.0, alpha }
  elseif isDisabled then
    borderColor = { 0.52, 0.52, 0.56, alpha }
  end

  love.graphics.push("all")
  love.graphics.translate(x, y)
  love.graphics.scale(scale, scale)

  if isHovered or isSelected or isDragged then
    local glowAlpha = Constants.CARD_HAND_GLOW_ALPHA * alpha
    if isSelected then
      glowAlpha = glowAlpha * 1.1
    end
    love.graphics.setColor(0.98, 0.90, 0.46, glowAlpha)
    love.graphics.rectangle("fill", -width * 0.5 - 8, -height * 0.5 - 8, width + 16, height + 16, 12, 12)
  end

  love.graphics.setColor(baseFill)
  love.graphics.rectangle("fill", -width * 0.5, -height * 0.5, width, height, 10, 10)

  if isFaceUp then
    love.graphics.setColor(0.20, 0.26, 0.38, alpha)
    love.graphics.setLineWidth(1.4)
    for lineIndex = -2, 2 do
      local lineY = lineIndex * 24
      love.graphics.line(-width * 0.40, lineY, width * 0.40, lineY)
    end
  else
    love.graphics.setColor(0.33, 0.42, 0.62, alpha)
    love.graphics.setLineWidth(1.2)
    for lineIndex = -3, 3 do
      local lineY = lineIndex * 18
      love.graphics.line(-width * 0.40, lineY, width * 0.40, lineY + 10)
      love.graphics.line(-width * 0.40, lineY + 10, width * 0.40, lineY)
    end
  end

  love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], alpha)
  love.graphics.setLineWidth(Constants.CARD_BORDER_THICKNESS)
  love.graphics.rectangle("line", -width * 0.5, -height * 0.5, width, height, 10, 10)

  local title = tostring(card.label or "")
  if title ~= "" then
    local font = FontManager.getFont("small")
    love.graphics.setFont(font)
    if isDisabled then
      love.graphics.setColor(0.24, 0.24, 0.26, alpha)
    else
      love.graphics.setColor(0.12, 0.16, 0.22, alpha)
    end
    love.graphics.printf(title, -width * 0.5 + 8, -font:getHeight() * 0.5, width - 16, "center")
  end

  love.graphics.pop()
end

return CardWidget
