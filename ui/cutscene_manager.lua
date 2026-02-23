--[[
파일명: cutscene_manager.lua
모듈명: CutsceneManager

역할:
- 카드 사용 직후 재생되는 스킬 컷신 오버레이를 관리한다.
- 서버 pause 상태와 로컬 스킵(개별 클라)을 분리해, 동기화/공정성을 유지한다.

외부에서 사용 가능한 함수:
- CutsceneManager.new()
- CutsceneManager:start(params)
- CutsceneManager:update(dt)
- CutsceneManager:draw(mouseX, mouseY)
- CutsceneManager:isActive()
- CutsceneManager:skipLocal()
- CutsceneManager:setBlockedByServerPaused(paused)
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local I18n = require("i18n.i18n")
local CutsceneDefs = require("data.cutscene_defs")

local CutsceneManager = {}
CutsceneManager.__index = CutsceneManager

local function t(key, vars)
  return I18n.t(key, vars)
end

local function cutsceneLog(tag, detail)
  if Constants.CUTSCENE_DEBUG_LOG ~= true then
    return
  end
  print(string.format("[CUTSCENE][%s] %s", tostring(tag), tostring(detail or "")))
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

local function lerp(fromValue, toValue, ratio)
  return fromValue + (toValue - fromValue) * ratio
end

local function easeOutCubic(ratio)
  local tValue = clamp(ratio, 0, 1)
  local inverse = 1 - tValue
  return 1 - inverse * inverse * inverse
end

local function easeInOutQuad(ratio)
  local tValue = clamp(ratio, 0, 1)
  if tValue < 0.5 then
    return 2 * tValue * tValue
  end
  return 1 - ((-2 * tValue + 2) ^ 2) * 0.5
end

local function copyColor(color, fallbackColor)
  local source = color or fallbackColor
  return {
    source[1] or 1,
    source[2] or 1,
    source[3] or 1,
    source[4] or 1
  }
end

local function resolveTotalVisualSec(cutsceneDef)
  return (cutsceneDef.cardFocusSec or 0)
    + (cutsceneDef.bandEnterSec or 0)
    + (cutsceneDef.characterEnterSec or 0)
    + (cutsceneDef.characterShakeSec or 0)
    + (cutsceneDef.characterExitSec or 0)
    + (cutsceneDef.bandExitSec or 0)
end

function CutsceneManager.new()
  local instance = {
    _active = false,
    _serverBlocked = false,
    _localSkipped = false,
    _visualDone = false,
    _elapsedSec = 0,
    _current = nil,
    _skipButton = Button.new({
      x = Constants.BASE_WORLD_W - Constants.CUTSCENE_SKIP_BUTTON_W - 22,
      y = 18,
      w = Constants.CUTSCENE_SKIP_BUTTON_W,
      h = Constants.CUTSCENE_SKIP_BUTTON_H,
      label = t("match.cutscene.skip"),
      onClick = function() end
    })
  }
  return setmetatable(instance, CutsceneManager)
end

function CutsceneManager:reset()
  self._active = false
  self._serverBlocked = false
  self._localSkipped = false
  self._visualDone = false
  self._elapsedSec = 0
  self._current = nil
end

function CutsceneManager:isActive()
  return self._active == true
end

function CutsceneManager:isInputBlocked()
  return self:isActive()
end

function CutsceneManager:isVisualVisible()
  if not self:isActive() then
    return false
  end
  if self._localSkipped then
    return false
  end
  return true
end

function CutsceneManager:isWaitingForServer()
  if not self:isActive() then
    return false
  end
  if not self._serverBlocked then
    return false
  end
  if self._localSkipped then
    return true
  end
  return self._visualDone
end

function CutsceneManager:setBlockedByServerPaused(paused)
  self._serverBlocked = paused == true
  if self._serverBlocked then
    cutsceneLog("SERVER_BLOCK", "on")
    if self._active ~= true and self._current then
      self._active = true
    end
    return
  end
  cutsceneLog("SERVER_BLOCK", "off")
  if self._visualDone or self._localSkipped then
    cutsceneLog("END", "reset after server resume")
    self:reset()
  end
end

function CutsceneManager:start(params)
  local normalizedParams = params or {}
  local cardId = tostring(normalizedParams.cardId or "")
  local cutsceneId = normalizedParams.cutsceneId and tostring(normalizedParams.cutsceneId) or ("cutscene_" .. tostring(love.timer.getTime()))
  if self._current and self._current.cutsceneId == cutsceneId and self._active then
    self._serverBlocked = true
    return false
  end

  local cutsceneDef = CutsceneDefs.get(cardId)
  self._current = {
    cutsceneId = cutsceneId,
    cardId = cardId,
    skillName = tostring(normalizedParams.skillName or cardId),
    ownerPlayerIndex = normalizedParams.ownerPlayerIndex == 1 and 1 or 2,
    isLocalUser = normalizedParams.isLocalUser == true,
    durationMs = tonumber(normalizedParams.cutsceneDurationMs) or cutsceneDef.durationMs or Constants.CUTSCENE_DEFAULT_DURATION_MS,
    def = cutsceneDef,
    directionSign = normalizedParams.isLocalUser == true and 1 or -1,
    totalVisualSec = resolveTotalVisualSec(cutsceneDef)
  }
  self._active = true
  self._serverBlocked = true
  self._localSkipped = false
  self._visualDone = false
  self._elapsedSec = 0
  cutsceneLog("START", string.format("id=%s card=%s owner=%s", tostring(cutsceneId), tostring(cardId), tostring(self._current.ownerPlayerIndex)))
  return true
end

function CutsceneManager:skipLocal()
  if not self:isActive() then
    return false
  end
  if self._localSkipped then
    return true
  end
  self._localSkipped = true
  self._visualDone = true
  cutsceneLog("SKIP_LOCAL", tostring(self._current and self._current.cutsceneId or ""))
  if not self._serverBlocked then
    cutsceneLog("END", "reset after local skip")
    self:reset()
  end
  return true
end

function CutsceneManager:update(dt)
  if not self:isActive() then
    return
  end
  if self._localSkipped or self._visualDone then
    if (not self._serverBlocked) then
      cutsceneLog("END", "reset after visual done")
      self:reset()
    end
    return
  end
  self._elapsedSec = self._elapsedSec + dt
  if self._current and self._elapsedSec >= self._current.totalVisualSec then
    self._visualDone = true
    cutsceneLog("VISUAL_DONE", tostring(self._current.cutsceneId))
    if not self._serverBlocked then
      cutsceneLog("END", "reset after visual done/no server block")
      self:reset()
    end
  end
end

function CutsceneManager:keypressed(key)
  if not self:isActive() then
    return false
  end
  if key == "space" then
    self:skipLocal()
    return true
  end
  return true
end

function CutsceneManager:mousepressed(mouseX, mouseY, button)
  if not self:isActive() then
    return false
  end
  if button ~= 1 then
    return true
  end

  if (not self._localSkipped) and self._skipButton:isHovered(mouseX, mouseY) then
    self:skipLocal()
    return true
  end
  return true
end

function CutsceneManager:mousereleased(_mouseX, _mouseY, _button)
  if not self:isActive() then
    return false
  end
  return true
end

function CutsceneManager:_drawDimLayer()
  if not self._current then
    return
  end
  local cutsceneDef = self._current.def
  local alpha = cutsceneDef.dimAlpha or Constants.CUTSCENE_DIM_ALPHA
  if self._localSkipped then
    alpha = alpha * 0.35
  end
  love.graphics.setColor(0, 0, 0, alpha)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
end

function CutsceneManager:_drawWaitingLabel()
  local panelW = 360
  local panelH = 48
  local panelX = (Constants.BASE_WORLD_W - panelW) * 0.5
  local panelY = Constants.BASE_WORLD_H - panelH - 30
  love.graphics.setColor(0.06, 0.08, 0.12, 0.86)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.cutscene.waiting_opponent"), panelX + 10, panelY + 14, panelW - 20, "center")
end

function CutsceneManager:_drawCardFocus(centerX, centerY)
  if not self._current then
    return
  end
  local cutsceneDef = self._current.def
  local focusSec = math.max(0.01, cutsceneDef.cardFocusSec or Constants.CUTSCENE_CARD_FOCUS_SEC)
  local progress = clamp(self._elapsedSec / focusSec, 0, 1)
  if progress >= 1 then
    return
  end

  local baseCardW = Constants.CARD_W
  local baseCardH = Constants.CARD_H
  local scale = 1 + 0.38 * easeOutCubic(progress)
  local alpha = 1 - easeInOutQuad(progress)
  local drawX = centerX
  local drawY = centerY
  local drawCardW = baseCardW * scale
  local drawCardH = baseCardH * scale
  local isOpponentCard = self._current.isLocalUser ~= true

  if isOpponentCard then
    local startX = centerX + self._current.directionSign * 280
    local startY = 116
    local moveRatio = easeOutCubic(progress)
    drawX = lerp(startX, centerX, moveRatio)
    drawY = lerp(startY, centerY, moveRatio)
    local flipRatio = math.abs(math.cos(progress * math.pi * 2.6))
    drawCardW = drawCardW * (0.26 + 0.74 * flipRatio)
  end

  local left = drawX - drawCardW * 0.5
  local top = drawY - drawCardH * 0.5
  if isOpponentCard then
    love.graphics.setColor(0.18, 0.22, 0.32, alpha)
    love.graphics.rectangle("fill", left, top, drawCardW, drawCardH, 12, 12)
    love.graphics.setColor(0.56, 0.70, 0.93, alpha)
    love.graphics.rectangle("line", left, top, drawCardW, drawCardH, 12, 12)
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(0.78, 0.84, 0.96, alpha)
    love.graphics.printf("CARD", left, top + drawCardH * 0.44, drawCardW, "center")
    return
  end

  love.graphics.setColor(0.17, 0.32, 0.25, alpha)
  love.graphics.rectangle("fill", left, top, drawCardW, drawCardH, 12, 12)
  love.graphics.setColor(0.60, 0.88, 0.72, alpha)
  love.graphics.rectangle("line", left, top, drawCardW, drawCardH, 12, 12)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(0.93, 0.96, 0.98, alpha)
  love.graphics.printf(self._current.skillName, left + 8, top + drawCardH * 0.42, drawCardW - 16, "center")
end

function CutsceneManager:_drawBandAndCharacter(centerX, centerY)
  if not self._current then
    return
  end
  local cutsceneDef = self._current.def
  local focusSec = cutsceneDef.cardFocusSec or Constants.CUTSCENE_CARD_FOCUS_SEC
  local stageElapsed = self._elapsedSec - focusSec
  if stageElapsed <= 0 then
    return
  end

  local bandEnterSec = math.max(0.01, cutsceneDef.bandEnterSec or Constants.CUTSCENE_BAND_ENTER_SEC)
  local characterEnterSec = math.max(0.01, cutsceneDef.characterEnterSec or Constants.CUTSCENE_CHARACTER_ENTER_SEC)
  local characterShakeSec = math.max(0.01, cutsceneDef.characterShakeSec or Constants.CUTSCENE_CHARACTER_SHAKE_SEC)
  local characterExitSec = math.max(0.01, cutsceneDef.characterExitSec or Constants.CUTSCENE_CHARACTER_EXIT_SEC)
  local bandExitSec = math.max(0.01, cutsceneDef.bandExitSec or Constants.CUTSCENE_BAND_EXIT_SEC)
  local characterStartOffsetSec = bandEnterSec * 0.25

  local bandW = cutsceneDef.bandWidth or Constants.CUTSCENE_BAND_WIDTH
  local bandH = cutsceneDef.bandHeight or Constants.CUTSCENE_BAND_HEIGHT
  local bandTiltPx = (cutsceneDef.bandTiltPx or Constants.CUTSCENE_BAND_TILT_PX) * self._current.directionSign
  local bandShakePx = cutsceneDef.bandShakePx or Constants.CUTSCENE_BAND_SHAKE_PX
  local rearHeightScale = cutsceneDef.bandRearHeightScale or Constants.CUTSCENE_BAND_REAR_HEIGHT_SCALE
  local frontHeightScale = cutsceneDef.bandFrontHeightScale or Constants.CUTSCENE_BAND_FRONT_HEIGHT_SCALE

  local bandCenterX = centerX
  local bandCenterY = centerY - 10
  local bandStartX = self._current.directionSign > 0 and (-bandW * 0.7) or (Constants.BASE_WORLD_W + bandW * 0.7)
  local bandAlpha = 1
  local bandWidthScale = 1

  local bandEnterRatio = clamp(stageElapsed / bandEnterSec, 0, 1)
  bandCenterX = lerp(bandStartX, bandCenterX, easeOutCubic(bandEnterRatio))
  if bandEnterRatio < 1 then
    local shakeRatio = math.sin(stageElapsed * 22.0) * (1 - bandEnterRatio)
    bandCenterY = bandCenterY + shakeRatio * bandShakePx
  end

  local bandExitStartSec = bandEnterSec + characterEnterSec + characterShakeSec + characterExitSec
  if stageElapsed >= bandExitStartSec then
    local bandExitRatio = clamp((stageElapsed - bandExitStartSec) / bandExitSec, 0, 1)
    bandAlpha = 1 - bandExitRatio
    bandWidthScale = 1 - 0.35 * easeOutCubic(bandExitRatio)
  end

  local halfBandW = bandW * 0.5 * bandWidthScale
  local rearHalfH = (bandH * 0.5) * rearHeightScale
  local frontHalfH = (bandH * 0.5) * frontHeightScale
  local rearX = bandCenterX - halfBandW
  local frontX = bandCenterX + halfBandW
  local leftTopX
  local rightTopX
  local rightBottomX
  local leftBottomX
  local topYLeft
  local topYRight
  local bottomYRight
  local bottomYLeft

  if self._current.directionSign > 0 then
    leftTopX = rearX + bandTiltPx
    rightTopX = frontX + bandTiltPx
    rightBottomX = frontX - bandTiltPx
    leftBottomX = rearX - bandTiltPx
    topYLeft = bandCenterY - rearHalfH
    topYRight = bandCenterY - frontHalfH
    bottomYRight = bandCenterY + frontHalfH
    bottomYLeft = bandCenterY + rearHalfH
  else
    leftTopX = rearX - bandTiltPx
    rightTopX = frontX - bandTiltPx
    rightBottomX = frontX + bandTiltPx
    leftBottomX = rearX + bandTiltPx
    topYLeft = bandCenterY - frontHalfH
    topYRight = bandCenterY - rearHalfH
    bottomYRight = bandCenterY + rearHalfH
    bottomYLeft = bandCenterY + frontHalfH
  end

  local bandColor = copyColor(cutsceneDef.bandColor, { 0.17, 0.30, 0.52, 0.90 })
  local borderColor = copyColor(cutsceneDef.bandBorderColor, { 0.55, 0.74, 0.96, 0.92 })
  bandColor[4] = (bandColor[4] or 1) * bandAlpha
  borderColor[4] = (borderColor[4] or 1) * bandAlpha

  love.graphics.setColor(bandColor)
  love.graphics.polygon("fill", leftTopX, topYLeft, rightTopX, topYRight, rightBottomX, bottomYRight, leftBottomX, bottomYLeft)
  love.graphics.setColor(borderColor)
  love.graphics.setLineWidth(2)
  love.graphics.polygon("line", leftTopX, topYLeft, rightTopX, topYRight, rightBottomX, bottomYRight, leftBottomX, bottomYLeft)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT[1], Constants.COLOR_TEXT[2], Constants.COLOR_TEXT[3], bandAlpha)
  love.graphics.printf(self._current.skillName, bandCenterX - halfBandW + 18, bandCenterY - 16, halfBandW * 2 - 36, "center")

  local characterElapsed = stageElapsed - characterStartOffsetSec
  if characterElapsed < 0 then
    return
  end

  local charW = cutsceneDef.characterWidth or Constants.CUTSCENE_CHARACTER_W
  local charH = cutsceneDef.characterHeight or Constants.CUTSCENE_CHARACTER_H
  local charStartX = self._current.directionSign > 0 and (-charW) or (Constants.BASE_WORLD_W + charW)
  local charAnchorX = centerX + self._current.directionSign * (bandW * 0.26)
  local charY = centerY + 4
  local charX = charAnchorX
  local charAlpha = 1

  if characterElapsed <= characterEnterSec then
    local enterRatio = clamp(characterElapsed / characterEnterSec, 0, 1)
    charX = lerp(charStartX, charAnchorX, easeOutCubic(enterRatio))
  elseif characterElapsed <= characterEnterSec + characterShakeSec then
    local shakeElapsed = characterElapsed - characterEnterSec
    charX = charAnchorX + math.sin(shakeElapsed * 34.0) * 7
  elseif characterElapsed <= characterEnterSec + characterShakeSec + characterExitSec then
    local exitElapsed = characterElapsed - characterEnterSec - characterShakeSec
    local exitRatio = clamp(exitElapsed / characterExitSec, 0, 1)
    local charEndX = self._current.directionSign > 0 and (-charW * 1.1) or (Constants.BASE_WORLD_W + charW * 1.1)
    charX = lerp(charAnchorX, charEndX, easeInOutQuad(exitRatio))
    charAlpha = 1 - exitRatio
  else
    return
  end

  local charColor = copyColor(cutsceneDef.characterPlaceholderColor, { 1.0, 0.92, 0.18, 0.42 })
  local charBorderColor = copyColor(cutsceneDef.characterPlaceholderBorder, { 1.0, 0.97, 0.62, 0.90 })
  charColor[4] = (charColor[4] or 1) * charAlpha
  charBorderColor[4] = (charBorderColor[4] or 1) * charAlpha

  local charLeft = charX - charW * 0.5
  local charTop = charY - charH * 0.5
  love.graphics.setColor(charColor)
  love.graphics.rectangle("fill", charLeft, charTop, charW, charH, 12, 12)
  love.graphics.setColor(charBorderColor)
  love.graphics.rectangle("line", charLeft, charTop, charW, charH, 12, 12)
end

function CutsceneManager:draw(mouseX, mouseY)
  if not self:isActive() then
    return
  end

  self:_drawDimLayer()
  local centerX = Constants.BASE_WORLD_W * 0.5
  local centerY = Constants.BASE_WORLD_H * 0.5

  if self:isVisualVisible() then
    self:_drawCardFocus(centerX, centerY)
    self:_drawBandAndCharacter(centerX, centerY)
  end

  if self:isWaitingForServer() then
    self:_drawWaitingLabel()
  end

  if (not self._localSkipped) then
    self._skipButton.label = t("match.cutscene.skip")
    self._skipButton:draw(mouseX, mouseY)
  end
end

return CutsceneManager
