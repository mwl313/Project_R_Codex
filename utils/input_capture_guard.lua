--[[
파일명: input_capture_guard.lua
모듈명: InputCaptureGuard

역할:
- 드래그 입력 중 relative mouse mode/cursor visibility를 안전하게 관리한다.
- 포커스 손실, 씬 전환, 종료 시에도 복구가 누락되지 않도록 단일 복구 경로를 제공한다.

외부에서 사용 가능한 함수:
- InputCaptureGuard.captureRelativeMouse()
- InputCaptureGuard.release(screenX, screenY)
- InputCaptureGuard.isActive()
- InputCaptureGuard.onMouseMoved(screenDx, screenDy)
- InputCaptureGuard.consumeRelativeDelta()

주의:
- release()는 여러 번 호출해도 안전(idempotent)해야 한다.
]]

local InputCaptureGuard = {}
local relativeAccumScreenDX = 0
local relativeAccumScreenDY = 0
local restoreScreenX = nil
local restoreScreenY = nil

local function safeCall(fn, ...)
  if type(fn) ~= "function" then
    return false, nil
  end
  return pcall(fn, ...)
end

function InputCaptureGuard.captureRelativeMouse()
  if not love or not love.mouse then
    return false
  end

  local mouse = love.mouse
  local isRelativeEnabled = false

  if type(mouse.getPosition) == "function" then
    local isOk, x, y = safeCall(mouse.getPosition)
    if isOk then
      restoreScreenX = x
      restoreScreenY = y
    end
  end

  if type(mouse.setRelativeMode) == "function" then
    safeCall(mouse.setRelativeMode, true)
  end
  if type(mouse.getRelativeMode) == "function" then
    local isOk, enabled = safeCall(mouse.getRelativeMode)
    isRelativeEnabled = isOk and enabled == true
  end

  if isRelativeEnabled and type(mouse.setVisible) == "function" then
    safeCall(mouse.setVisible, false)
    relativeAccumScreenDX = 0
    relativeAccumScreenDY = 0
  end

  return isRelativeEnabled
end

function InputCaptureGuard.release(screenX, screenY)
  if not love or not love.mouse then
    return
  end

  local mouse = love.mouse
  if type(mouse.getRelativeMode) == "function" then
    local isOk, enabled = safeCall(mouse.getRelativeMode)
    if isOk and enabled and type(mouse.setRelativeMode) == "function" then
      safeCall(mouse.setRelativeMode, false)
    end
  end

  if type(mouse.setPosition) == "function" then
    if type(screenX) == "number" and type(screenY) == "number" then
      safeCall(mouse.setPosition, screenX, screenY)
    elseif restoreScreenX ~= nil and restoreScreenY ~= nil then
      safeCall(mouse.setPosition, restoreScreenX, restoreScreenY)
    end
  end

  if type(mouse.setVisible) == "function" then
    safeCall(mouse.setVisible, true)
  end
  relativeAccumScreenDX = 0
  relativeAccumScreenDY = 0
  restoreScreenX = nil
  restoreScreenY = nil
end

function InputCaptureGuard.isActive()
  if not love or not love.mouse then
    return false
  end
  if type(love.mouse.getRelativeMode) ~= "function" then
    return false
  end
  local isOk, enabled = safeCall(love.mouse.getRelativeMode)
  return isOk and enabled == true
end

function InputCaptureGuard.consumeRelativeDelta()
  if not InputCaptureGuard.isActive() then
    return 0, 0, false
  end
  local dx = relativeAccumScreenDX
  local dy = relativeAccumScreenDY
  relativeAccumScreenDX = 0
  relativeAccumScreenDY = 0
  return dx, dy, true
end

function InputCaptureGuard.onMouseMoved(screenDx, screenDy)
  if not InputCaptureGuard.isActive() then
    return false
  end
  relativeAccumScreenDX = relativeAccumScreenDX + (screenDx or 0)
  relativeAccumScreenDY = relativeAccumScreenDY + (screenDy or 0)
  return true
end

return InputCaptureGuard
