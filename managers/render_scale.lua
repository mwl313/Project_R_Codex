--[[
파일명: render_scale.lua
모듈명: RenderScale

역할:
- 월드 좌표(1280x720) 기반 렌더 스케일 처리
- screen -> world 좌표 변환 제공

외부에서 사용 가능한 함수:
- RenderScale.new(worldW, worldH)
- RenderScale:update(screenW, screenH)
- RenderScale:beginDraw()
- RenderScale:endDraw()
- RenderScale:toWorld(screenX, screenY)

주의:
- UI hit-test는 반드시 toWorld 결과를 사용한다
]]

local RenderScale = {}
RenderScale.__index = RenderScale

function RenderScale.new(worldW, worldH)
  local instance = {
    _worldW = worldW,
    _worldH = worldH,
    _scale = 1,
    _offsetX = 0,
    _offsetY = 0
  }
  setmetatable(instance, RenderScale)
  instance:update(love.graphics.getDimensions())
  return instance
end

function RenderScale:update(screenW, screenH)
  local scaleX = screenW / self._worldW
  local scaleY = screenH / self._worldH
  self._scale = math.min(scaleX, scaleY)
  self._offsetX = (screenW - self._worldW * self._scale) * 0.5
  self._offsetY = (screenH - self._worldH * self._scale) * 0.5
end

function RenderScale:beginDraw()
  love.graphics.push()
  love.graphics.translate(self._offsetX, self._offsetY)
  love.graphics.scale(self._scale, self._scale)
end

function RenderScale:endDraw()
  love.graphics.pop()
end

function RenderScale:toWorld(screenX, screenY)
  local worldX = (screenX - self._offsetX) / self._scale
  local worldY = (screenY - self._offsetY) / self._scale
  return worldX, worldY
end

return RenderScale
