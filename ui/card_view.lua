--[[
파일명: card_view.lua
모듈명: CardView

역할:
- 카드 UI 렌더링/히트테스트를 공통 제공한다.
- 현재는 primitive(사각형/선/텍스트) 기반이며, 추후 이미지 카드로 교체할 때 이 모듈만 교체하면 된다.

외부에서 사용 가능한 함수:
- CardView.drawCard(card)
- CardView.hitTest(card, mouseX, mouseY)
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local CardView = {}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

function CardView.hitTest(card, mouseX, mouseY)
  local scale = card.scale or 1.0
  local halfW = (card.w * scale) * 0.5
  local halfH = (card.h * scale) * 0.5
  return mouseX >= card.x - halfW
    and mouseX <= card.x + halfW
    and mouseY >= card.y - halfH
    and mouseY <= card.y + halfH
end

function CardView.drawCard(card)
  local scale = card.scale or 1.0
  local flipScaleX = math.max(0.06, math.abs(card.flipScaleX or 1.0))
  local alpha = clamp(card.alpha or 1.0, 0, 1)
  local isHovered = card.isHovered == true
  local isSelected = card.isSelected == true
  local isFaceUp = card.isFaceUp == true
  local borderThickness = card.borderThickness or Constants.CARD_BORDER_THICKNESS
  local glowAlpha = card.glowAlpha or Constants.CARD_GLOW_ALPHA

  love.graphics.push("all")
  love.graphics.translate(card.x, card.y)
  love.graphics.scale(scale * flipScaleX, scale)

  if isHovered or isSelected then
    local glowStrength = isSelected and 1.0 or 0.72
    love.graphics.setColor(0.96, 0.90, 0.46, glowAlpha * glowStrength * alpha)
    love.graphics.rectangle("fill", -card.w * 0.5 - 8, -card.h * 0.5 - 8, card.w + 16, card.h + 16, 14, 14)
  end

  if isFaceUp then
    love.graphics.setColor(0.88, 0.89, 0.92, alpha)
  else
    love.graphics.setColor(0.18, 0.24, 0.36, alpha)
  end
  love.graphics.rectangle("fill", -card.w * 0.5, -card.h * 0.5, card.w, card.h, 12, 12)

  if isFaceUp then
    love.graphics.setColor(0.22, 0.28, 0.40, alpha)
    love.graphics.setLineWidth(1.5)
    for lineIndex = -2, 2 do
      love.graphics.line(
        -card.w * 0.42,
        lineIndex * 26,
        card.w * 0.42,
        lineIndex * 26
      )
    end
  else
    love.graphics.setColor(0.30, 0.39, 0.57, alpha)
    love.graphics.setLineWidth(1.5)
    for lineIndex = -3, 3 do
      local y = lineIndex * 20
      love.graphics.line(-card.w * 0.45, y, card.w * 0.45, y + 16)
      love.graphics.line(-card.w * 0.45, y + 16, card.w * 0.45, y)
    end
  end

  local borderColor = Constants.COLOR_PANEL_BORDER
  if isSelected then
    borderColor = { 0.96, 0.82, 0.33, 1.0 }
  elseif isHovered then
    borderColor = { 0.84, 0.90, 1.0, 1.0 }
  end
  love.graphics.setColor(borderColor[1], borderColor[2], borderColor[3], alpha)
  love.graphics.setLineWidth(borderThickness)
  love.graphics.rectangle("line", -card.w * 0.5, -card.h * 0.5, card.w, card.h, 12, 12)

  if flipScaleX >= 0.22 then
    local font = FontManager.getFont("small")
    love.graphics.setFont(font)
    love.graphics.setColor(0.12, 0.16, 0.22, alpha)
    local label = isFaceUp and tostring(card.label or "") or tostring(card.backLabel or "")
    love.graphics.printf(label, -card.w * 0.5 + 8, -font:getHeight() * 0.5, card.w - 16, "center")
  end

  love.graphics.pop()
end

return CardView
