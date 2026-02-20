--[[
파일명: overlay_transition.lua
모듈명: OverlayTransition

역할:
- 오버레이 패널의 등장/퇴장(하단 슬라이드) 및 배경 딤 알파를 동기화한다.
- 로비 닉네임/환경설정처럼 재사용 가능한 공용 전환 로직을 제공한다.

외부에서 사용 가능한 함수:
- OverlayTransition.new(options)
- OverlayTransition:open()
- OverlayTransition:close()
- OverlayTransition:update(dt)
- OverlayTransition:getPanelY()
- OverlayTransition:getDimAlpha()
- OverlayTransition:isInteractive()
- OverlayTransition:isClosed()
]]

local Constants = require("constants")

local OverlayTransition = {}
OverlayTransition.__index = OverlayTransition

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

function OverlayTransition.new(options)
  local config = options or {}
  local targetY = config.targetY or 0
  local panelH = config.panelH or 0
  local worldH = config.worldH or Constants.BASE_WORLD_H
  local offscreenMargin = config.offscreenMargin or 24
  local offscreenY = worldH + panelH + offscreenMargin

  local instance = {
    _targetY = targetY,
    _offscreenY = offscreenY,
    _panelY = offscreenY,
    _dimAlpha = 0,
    _maxDimAlpha = config.maxDimAlpha or (Constants.COLOR_OVERLAY_DIM[4] or 0.56),
    _enterDurationSec = config.enterDurationSec or 0.26,
    _exitDurationSec = config.exitDurationSec or 0.22,
    _elapsedSec = 0,
    _state = "closed"
  }
  return setmetatable(instance, OverlayTransition)
end

function OverlayTransition:open()
  self._state = "entering"
  self._elapsedSec = 0
  self._panelY = self._offscreenY
  self._dimAlpha = 0
end

function OverlayTransition:close()
  if self._state == "closed" or self._state == "exiting" then
    return
  end
  self._state = "exiting"
  self._elapsedSec = 0
end

function OverlayTransition:update(dt)
  if self._state == "closed" or self._state == "visible" then
    return
  end

  local durationSec = self._enterDurationSec
  if self._state == "exiting" then
    durationSec = self._exitDurationSec
  end
  if durationSec <= 0 then
    durationSec = 0.0001
  end

  self._elapsedSec = self._elapsedSec + dt
  local progress = clamp01(self._elapsedSec / durationSec)

  if self._state == "entering" then
    local eased = easeOutCubic(progress)
    self._panelY = self._offscreenY + (self._targetY - self._offscreenY) * eased
    self._dimAlpha = self._maxDimAlpha * eased
    if progress >= 1 then
      self._state = "visible"
      self._panelY = self._targetY
      self._dimAlpha = self._maxDimAlpha
    end
    return
  end

  local eased = easeInCubic(progress)
  self._panelY = self._targetY + (self._offscreenY - self._targetY) * eased
  self._dimAlpha = self._maxDimAlpha * (1 - eased)
  if progress >= 1 then
    self._state = "closed"
    self._panelY = self._offscreenY
    self._dimAlpha = 0
  end
end

function OverlayTransition:getPanelY()
  return self._panelY
end

function OverlayTransition:getDimAlpha()
  return self._dimAlpha
end

function OverlayTransition:isInteractive()
  return self._state == "visible"
end

function OverlayTransition:isClosed()
  return self._state == "closed"
end

return OverlayTransition
