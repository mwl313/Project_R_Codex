--[[
파일명: transition_manager.lua
모듈명: TransitionManager

역할:
- 씬 전환 애니메이션 상태를 관리한다.
- FORWARD/BACK 방향 스크린 와이프(screen wipe) 연출을 제공한다.
- 전환 시작 시 from/to 씬을 캔버스로 스냅샷한 뒤, 전환 중에는 캔버스만 렌더한다.

외부에서 사용 가능한 함수:
- TransitionManager.new()
- TransitionManager:start(fromScene, toScene, direction, opts)
- TransitionManager:update(dt)
- TransitionManager:draw()
- TransitionManager:isActive()

주의:
- 전환 좌표는 world 좌표 기준으로 동작한다.
]]

local Constants = require("constants")
local Config = require("config")

local TransitionManager = {}
TransitionManager.__index = TransitionManager

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

local function applyCanvasFilter(canvas)
  if canvas and canvas.setFilter then
    canvas:setFilter("nearest", "nearest")
  end
end

local function createCanvasOrNil(width, height)
  if not love.graphics or not love.graphics.newCanvas then
    return nil
  end
  local isOk, canvasOrError = pcall(love.graphics.newCanvas, width, height)
  if not isOk then
    return nil
  end
  applyCanvasFilter(canvasOrError)
  return canvasOrError
end

local function setCanvasSafe(canvas)
  if canvas then
    love.graphics.setCanvas(canvas)
  else
    love.graphics.setCanvas()
  end
end

local function drawSceneToCanvas(scene, canvas)
  if not scene or not canvas then
    return false
  end

  local previousCanvas = love.graphics.getCanvas()
  love.graphics.push("all")
  setCanvasSafe(canvas)
  local bg = Constants.COLOR_BG
  love.graphics.clear(bg[1], bg[2], bg[3], bg[4] or 1)
  love.graphics.origin()
  if scene.draw then
    scene:draw()
  end
  setCanvasSafe(previousCanvas)
  love.graphics.pop()
  return true
end

function TransitionManager.new()
  local instance = {
    _active = false,
    _done = false,
    _direction = Config.TRANSITION_FORWARD,
    _elapsedSec = 0,
    _durationSec = Config.TRANSITION_WIPE_DURATION_SEC,
    _bandWidthRatio = Config.TRANSITION_WIPE_BAND_WIDTH_RATIO,
    _edgeSoftnessPx = Config.TRANSITION_WIPE_EDGE_SOFTNESS_PX,
    _bandWidthPx = 1,
    _fromScene = nil,
    _toScene = nil,
    _fromCanvas = nil,
    _toCanvas = nil,
    _toQuad = nil
  }
  return setmetatable(instance, TransitionManager)
end

function TransitionManager:ensureResources()
  local worldW = Constants.BASE_WORLD_W
  local worldH = Constants.BASE_WORLD_H

  if not self._fromCanvas then
    self._fromCanvas = createCanvasOrNil(worldW, worldH)
  end
  if not self._toCanvas then
    self._toCanvas = createCanvasOrNil(worldW, worldH)
  end
  if self._fromCanvas and self._toCanvas and not self._toQuad then
    self._toQuad = love.graphics.newQuad(0, 0, 0, worldH, worldW, worldH)
  end

  return self._fromCanvas ~= nil and self._toCanvas ~= nil and self._toQuad ~= nil
end

function TransitionManager:start(fromScene, toScene, direction, opts)
  self:clear()

  if not Config.TRANSITION_WIPE_ENABLED then
    return false
  end

  if not fromScene or not toScene then
    return false
  end

  if not self:ensureResources() then
    return false
  end

  local isFromCaptured = drawSceneToCanvas(fromScene, self._fromCanvas)
  local isToCaptured = drawSceneToCanvas(toScene, self._toCanvas)
  if not isFromCaptured or not isToCaptured then
    self:clear()
    return false
  end

  local options = opts or {}
  self._active = true
  self._done = false
  self._fromScene = fromScene
  self._toScene = toScene
  self._direction = direction or Config.TRANSITION_FORWARD
  self._elapsedSec = 0
  self._durationSec = options.durationSec or Config.TRANSITION_WIPE_DURATION_SEC
  self._bandWidthRatio = options.bandWidthRatio or Config.TRANSITION_WIPE_BAND_WIDTH_RATIO
  self._edgeSoftnessPx = options.edgeSoftnessPx or Config.TRANSITION_WIPE_EDGE_SOFTNESS_PX
  if options.featherPx ~= nil then
    self._edgeSoftnessPx = options.featherPx
  end

  local worldW = Constants.BASE_WORLD_W
  local ratio = tonumber(self._bandWidthRatio) or Config.TRANSITION_WIPE_BAND_WIDTH_RATIO
  if ratio < 0.05 then
    ratio = 0.05
  elseif ratio > 1 then
    ratio = 1
  end
  self._bandWidthRatio = ratio
  self._bandWidthPx = math.max(1, math.floor(worldW * ratio + 0.5))
  return true
end

function TransitionManager:clear()
  self._active = false
  self._done = false
  self._elapsedSec = 0
  self._fromScene = nil
  self._toScene = nil
end

function TransitionManager:update(dt)
  if not self._active then
    return
  end

  local durationSec = self._durationSec
  if type(durationSec) ~= "number" or durationSec <= 0 then
    durationSec = 0.0001
  end

  self._elapsedSec = self._elapsedSec + dt
  if self._elapsedSec >= durationSec then
    self._elapsedSec = durationSec
    self._done = true
  end
end

function TransitionManager:isActive()
  return self._active
end

function TransitionManager:isDone()
  return self._active and self._done
end

function TransitionManager:getProgress()
  local durationSec = self._durationSec
  if type(durationSec) ~= "number" or durationSec <= 0 then
    return 1
  end
  return clamp01(self._elapsedSec / durationSec)
end

function TransitionManager:getScenes()
  return self._fromScene, self._toScene
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

local function resolveBandBounds(direction, eased, worldW, bandWidthPx)
  local travelDistance = worldW + bandWidthPx
  if direction == Config.TRANSITION_FORWARD then
    local bandLeft = worldW - (travelDistance * eased)
    return bandLeft, bandLeft + bandWidthPx
  end
  local bandLeft = -bandWidthPx + (travelDistance * eased)
  return bandLeft, bandLeft + bandWidthPx
end

local function drawEdgeSoftness(bandLeft, bandRight, worldW, worldH, softnessPx)
  if softnessPx <= 0 then
    return
  end

  for i = 0, softnessPx - 1 do
    local alpha = (1 - (i / softnessPx)) * 0.12
    local leftX = math.floor(bandLeft) - i - 1
    local rightX = math.floor(bandRight) + i
    if leftX >= 0 and leftX < worldW then
      love.graphics.setColor(0, 0, 0, alpha)
      love.graphics.rectangle("fill", leftX, 0, 1, worldH)
    end
    if rightX >= 0 and rightX < worldW then
      love.graphics.setColor(0, 0, 0, alpha)
      love.graphics.rectangle("fill", rightX, 0, 1, worldH)
    end
  end
end

function TransitionManager:draw()
  if not self._active then
    return
  end
  if not self._fromCanvas or not self._toCanvas or not self._toQuad then
    return
  end

  local progress = self:getProgress()
  local eased = easeOutCubic(progress)
  local worldW = Constants.BASE_WORLD_W
  local worldH = Constants.BASE_WORLD_H
  local bandWidthPx = self._bandWidthPx
  local bandLeft, bandRight = resolveBandBounds(self._direction, eased, worldW, bandWidthPx)

  love.graphics.push("all")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self._fromCanvas, 0, 0)

  if self._direction == Config.TRANSITION_FORWARD then
    local revealStart = clamp(bandRight, 0, worldW)
    local revealW = worldW - revealStart
    if revealW > 0 then
      self._toQuad:setViewport(revealStart, 0, revealW, worldH, worldW, worldH)
      love.graphics.draw(self._toCanvas, self._toQuad, revealStart, 0)
    end
  else
    local revealEnd = clamp(bandLeft, 0, worldW)
    if revealEnd > 0 then
      self._toQuad:setViewport(0, 0, revealEnd, worldH, worldW, worldH)
      love.graphics.draw(self._toCanvas, self._toQuad, 0, 0)
    end
  end

  local visibleLeft = clamp(bandLeft, 0, worldW)
  local visibleRight = clamp(bandRight, 0, worldW)
  local visibleBandW = visibleRight - visibleLeft
  if visibleBandW > 0 then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", visibleLeft, 0, visibleBandW, worldH)
  end

  local softnessPx = math.max(0, math.floor(self._edgeSoftnessPx or 0))
  if softnessPx > 0 and visibleBandW > 0 then
    drawEdgeSoftness(visibleLeft, visibleRight, worldW, worldH, softnessPx)
  end

  love.graphics.pop()
end

return TransitionManager
