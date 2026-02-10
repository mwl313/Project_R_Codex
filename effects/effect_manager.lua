--[[
파일명: effect_manager.lua
모듈명: EffectManager

역할:
- MatchScene에서 발생하는 임시 시각효과를 한 곳에서 관리한다.
- 현재 구현: 충격파(shockwave) 카드의 충돌 시 발생하는 원형 파동 이펙트.

사용 시나리오:
- 충격파 카드 사용 턴에서 "발사된 돌"이 벽/돌/장애물과 충돌할 때마다 파동 표시.
- 이펙트는 게임 규칙(판정)에 영향 주지 않고 렌더링만 담당.
]]

local EffectManager = {}
EffectManager.__index = EffectManager

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function EffectManager.new()
  local instance = {
    _effectList = {}
  }
  setmetatable(instance, EffectManager)
  return instance
end

function EffectManager:clear()
  self._effectList = {}
end

-- 충격파 카드 전용 시각효과:
-- 충격파 판정 반경(radius)과 동일한 최대 반경으로 확산하는 원형 파동을 생성한다.
function EffectManager:addShockwavePulse(canonicalX, canonicalY, radius)
  if not isFiniteNumber(canonicalX) or not isFiniteNumber(canonicalY) or not isFiniteNumber(radius) then
    return
  end
  local clampedRadius = math.max(0, radius)
  if clampedRadius <= 0 then
    return
  end
  self._effectList[#self._effectList + 1] = {
    kind = "shockwave",
    x = canonicalX,
    y = canonicalY,
    radius = clampedRadius,
    elapsed = 0,
    duration = 0.22
  }
end

function EffectManager:update(dt)
  local clampedDt = 0
  if isFiniteNumber(dt) then
    clampedDt = math.max(0, math.min(dt, 0.05))
  end

  for index = #self._effectList, 1, -1 do
    local effect = self._effectList[index]
    effect.elapsed = effect.elapsed + clampedDt
    if effect.elapsed >= effect.duration then
      table.remove(self._effectList, index)
    end
  end
end

function EffectManager:draw(boardX, boardY, canonicalToLocalFn)
  if type(canonicalToLocalFn) ~= "function" then
    return
  end

  for _, effect in ipairs(self._effectList) do
    if effect.kind == "shockwave" then
      local progress = math.min(1, effect.elapsed / effect.duration)
      local pulseRadius = math.max(1, effect.radius * progress)
      local alpha = (1 - progress) * 0.72
      local lineWidth = 2 + (1 - progress) * 2

      local localX, localY = canonicalToLocalFn(effect.x, effect.y)
      local worldX = boardX + localX
      local worldY = boardY + localY

      love.graphics.setLineWidth(lineWidth)
      love.graphics.setColor(0.22, 0.80, 1.00, alpha)
      love.graphics.circle("line", worldX, worldY, pulseRadius)
      love.graphics.setColor(0.22, 0.80, 1.00, alpha * 0.20)
      love.graphics.circle("fill", worldX, worldY, pulseRadius * 0.28)
      love.graphics.setLineWidth(1)
    end
  end
end

return EffectManager
