--[[
파일명: drop_zone.lua
모듈명: DropZone

역할:
- 카드 드래그 중 사용할 중앙 Drop Zone(히트테스트/플래시 렌더)을 제공한다.
- 현재는 primitive 도형 기반이며, 추후 에셋 교체를 위한 분리 모듈이다.

외부에서 사용 가능한 함수:
- DropZone.new(params)
- DropZone:setCenter(x, y)
- DropZone:setVisible(isVisible)
- DropZone:update(dt)
- DropZone:isPointInside(worldX, worldY)
- DropZone:draw()
]]

local Constants = require("constants")

local DropZone = {}
DropZone.__index = DropZone

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(fromValue, toValue, t)
  return fromValue + (toValue - fromValue) * t
end

function DropZone.new(params)
  local instance = {
    _centerX = params.centerX or Constants.BASE_WORLD_W * 0.5,
    _centerY = params.centerY or Constants.BASE_WORLD_H * 0.5,
    _size = params.size or Constants.CARD_DROP_ZONE_SIZE,
    _flashPeriodSec = params.flashPeriodSec or Constants.CARD_DROP_ZONE_FLASH_PERIOD_SEC,
    _alphaMin = params.alphaMin or Constants.CARD_DROP_ZONE_ALPHA_MIN,
    _alphaMax = params.alphaMax or Constants.CARD_DROP_ZONE_ALPHA_MAX,
    _elapsedSec = 0,
    _isVisible = false
  }
  return setmetatable(instance, DropZone)
end

function DropZone:setCenter(centerX, centerY)
  self._centerX = centerX
  self._centerY = centerY
end

function DropZone:setVisible(isVisible)
  self._isVisible = isVisible == true
end

function DropZone:update(dt)
  self._elapsedSec = self._elapsedSec + math.max(0, dt or 0)
end

function DropZone:isPointInside(worldX, worldY)
  local halfSize = self._size * 0.5
  return worldX >= self._centerX - halfSize
    and worldX <= self._centerX + halfSize
    and worldY >= self._centerY - halfSize
    and worldY <= self._centerY + halfSize
end

function DropZone:draw()
  if not self._isVisible then
    return
  end

  local periodSec = math.max(0.001, self._flashPeriodSec)
  local cycle = (self._elapsedSec % periodSec) / periodSec
  local wave = (math.sin(cycle * math.pi * 2) + 1) * 0.5
  local alpha = lerp(self._alphaMin, self._alphaMax, wave)
  alpha = clamp(alpha, 0, 1)

  local size = self._size
  local x = self._centerX - size * 0.5
  local y = self._centerY - size * 0.5

  love.graphics.setColor(0.92, 0.82, 0.34, alpha)
  love.graphics.rectangle("fill", x, y, size, size, 10, 10)

  love.graphics.setColor(0.98, 0.90, 0.52, math.min(1, alpha + 0.35))
  love.graphics.setLineWidth(2.4)
  love.graphics.rectangle("line", x, y, size, size, 10, 10)
  love.graphics.setLineWidth(1)
end

return DropZone
