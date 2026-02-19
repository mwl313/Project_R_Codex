--[[
파일명: coin_toss_view.lua
모듈명: CoinTossView

역할:
- 코인 토스 연출(플립 + 결과 공개)을 담당하는 재사용 UI 뷰.
- 씬은 결과(isFirst)와 문구만 넘기고 update/draw만 호출한다.

외부에서 사용 가능한 함수:
- CoinTossView.new(params)
- CoinTossView:update(dt)
- CoinTossView:draw()
- CoinTossView:isComplete()

주의:
- 현재는 primitive(circle/rect/text) 렌더링만 사용한다.
- 향후 이미지/애니메이션 애셋으로 교체할 때 이 모듈만 교체하면 된다.
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")

local CoinTossView = {}
CoinTossView.__index = CoinTossView

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function easeOutCubic(progress)
  local t = clamp(progress, 0, 1)
  return 1 - ((1 - t) ^ 3)
end

function CoinTossView.new(params)
  local options = params or {}
  local isFirst = options.isFirst == true
  local totalSec = options.totalSec or Constants.COIN_TOSS_TOTAL_SEC
  local flipSec = options.flipSec or Constants.COIN_TOSS_FLIP_SEC
  flipSec = math.min(math.max(0.1, flipSec), math.max(0.1, totalSec))
  local halfTurns = options.halfTurns
  if type(halfTurns) ~= "number" then
    halfTurns = isFirst and 10 or 9
  end
  halfTurns = math.max(2, math.floor(halfTurns))
  if isFirst and (halfTurns % 2 == 1) then
    halfTurns = halfTurns + 1
  elseif (not isFirst) and (halfTurns % 2 == 0) then
    halfTurns = halfTurns + 1
  end

  local instance = {
    _isFirst = isFirst,
    _elapsedSec = 0,
    _totalSec = math.max(0.1, totalSec),
    _flipSec = flipSec,
    _pulseAmplitude = options.pulseAmplitude or Constants.COIN_TOSS_PULSE_AMPLITUDE,
    _centerX = options.centerX or Constants.BASE_WORLD_W * 0.5,
    _centerY = options.centerY or Constants.BASE_WORLD_H * 0.5 - 48,
    _coinRadius = options.coinRadius or 108,
    _halfTurns = halfTurns,
    _frontFaceText = options.frontFaceText or "선공",
    _backFaceText = options.backFaceText or "후공",
    _resultFaceText = isFirst and (options.frontFaceText or "선공") or (options.backFaceText or "후공"),
    _titleText = options.titleText or "선공",
    _subtitleText = options.subtitleText or "당신이 선공입니다."
  }
  return setmetatable(instance, CoinTossView)
end

function CoinTossView:update(dt)
  if self._elapsedSec >= self._totalSec then
    return
  end
  self._elapsedSec = clamp(self._elapsedSec + dt, 0, self._totalSec)
end

function CoinTossView:isComplete()
  return self._elapsedSec >= self._totalSec
end

function CoinTossView:getRevealProgress()
  if self._elapsedSec <= self._flipSec then
    return 0
  end
  local remain = math.max(0.0001, self._totalSec - self._flipSec)
  return clamp((self._elapsedSec - self._flipSec) / remain, 0, 1)
end

function CoinTossView:getFaceTextByAngle(angle)
  if math.cos(angle) >= 0 then
    return self._frontFaceText
  end
  return self._backFaceText
end

function CoinTossView:drawCoinFlip()
  local flipProgress = clamp(self._elapsedSec / self._flipSec, 0, 1)
  local easedProgress = easeOutCubic(flipProgress)
  local angle = easedProgress * math.pi * self._halfTurns
  local cosine = math.cos(angle)
  local sineAbs = math.abs(math.sin(angle))
  local scaleX = 0.16 + math.abs(cosine) * 0.84
  local flicker = 0.58 + 0.42 * sineAbs
  local isFrontFace = cosine >= 0
  local faceText = isFrontFace and self._frontFaceText or self._backFaceText

  local baseFill = isFrontFace and { 0.93, 0.80, 0.28 } or { 0.72, 0.79, 0.88 }
  local edgeColor = isFrontFace and { 0.98, 0.91, 0.48 } or { 0.90, 0.93, 0.98 }

  love.graphics.push("all")
  love.graphics.translate(self._centerX, self._centerY)
  love.graphics.scale(scaleX, 1.0)

  love.graphics.setColor(baseFill[1] * flicker, baseFill[2] * flicker, baseFill[3] * flicker, 1.0)
  love.graphics.circle("fill", 0, 0, self._coinRadius)
  love.graphics.setColor(edgeColor)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", 0, 0, self._coinRadius)

  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.circle("fill", -self._coinRadius * 0.22, -self._coinRadius * 0.26, self._coinRadius * 0.38)

  if scaleX > 0.23 then
    local coinTextFont = FontManager.getFont("ui")
    love.graphics.setFont(coinTextFont)
    love.graphics.setColor(0.10, 0.12, 0.20, 0.95)
    love.graphics.printf(faceText, -self._coinRadius, -coinTextFont:getHeight() * 0.5, self._coinRadius * 2, "center")
  end
  love.graphics.pop()

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("Coin Toss...", 0, self._centerY + self._coinRadius + 34, Constants.BASE_WORLD_W, "center")
end

function CoinTossView:drawIdle()
  local fillColor = self._isFirst and { 0.24, 0.60, 0.95 } or { 0.95, 0.58, 0.26 }
  local edgeColor = self._isFirst and { 0.56, 0.80, 1.0 } or { 1.0, 0.76, 0.55 }

  love.graphics.push("all")
  love.graphics.setColor(fillColor)
  love.graphics.circle("fill", self._centerX, self._centerY, self._coinRadius)
  love.graphics.setColor(edgeColor)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", self._centerX, self._centerY, self._coinRadius)

  local coinTextFont = FontManager.getFont("ui")
  love.graphics.setFont(coinTextFont)
  love.graphics.setColor(0.10, 0.12, 0.20, 0.95)
  love.graphics.printf(
    self._resultFaceText,
    self._centerX - self._coinRadius,
    self._centerY - coinTextFont:getHeight() * 0.5,
    self._coinRadius * 2,
    "center"
  )
  love.graphics.pop()

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("잠시 후 코인 토스...", 0, self._centerY + self._coinRadius + 34, Constants.BASE_WORLD_W, "center")
end

function CoinTossView:drawReveal()
  local revealElapsed = self._elapsedSec - self._flipSec
  local pulseScale = 1 + self._pulseAmplitude * math.sin(revealElapsed * 8.0)
  local radius = self._coinRadius * pulseScale
  local fillColor = self._isFirst and { 0.22, 0.58, 0.95 } or { 0.95, 0.56, 0.24 }
  local edgeColor = self._isFirst and { 0.56, 0.80, 1.0 } or { 1.0, 0.76, 0.55 }

  love.graphics.push("all")
  love.graphics.setColor(fillColor)
  love.graphics.circle("fill", self._centerX, self._centerY, radius)
  love.graphics.setColor(edgeColor)
  love.graphics.setLineWidth(5)
  love.graphics.circle("line", self._centerX, self._centerY, radius)

  local coinTextFont = FontManager.getFont("ui")
  love.graphics.setFont(coinTextFont)
  love.graphics.setColor(0.10, 0.12, 0.20, 0.95)
  love.graphics.printf(
    self._resultFaceText,
    self._centerX - radius,
    self._centerY - coinTextFont:getHeight() * 0.5,
    radius * 2,
    "center"
  )
  love.graphics.pop()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(self._titleText, 0, self._centerY + self._coinRadius + 30, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(self._subtitleText, 0, self._centerY + self._coinRadius + 76, Constants.BASE_WORLD_W, "center")
end

function CoinTossView:draw()
  if self._elapsedSec < self._flipSec then
    self:drawCoinFlip()
    return
  end
  self:drawReveal()
end

return CoinTossView
