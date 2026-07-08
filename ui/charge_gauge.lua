--[[
파일명: charge_gauge.lua
모듈명: ChargeGauge

역할:
- 초능력 충전 게이지 UI 위젯.
- 캐릭터 정보·원형 게이지·초능력 버튼을 통합 렌더링한다.
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Json = require("utils.json")

local ChargeGauge = {}
ChargeGauge.__index = ChargeGauge

local CHARACTERS_CACHE = nil

local function loadCharacters()
  if CHARACTERS_CACHE then
    return CHARACTERS_CACHE
  end
  if not love or not love.filesystem then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  local isReadOk, raw = pcall(love.filesystem.read, "shared/characters.json")
  if not isReadOk or type(raw) ~= "string" or raw == "" then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  local isDecoded, parsed = pcall(Json.decode, raw)
  if not isDecoded or type(parsed) ~= "table" then
    CHARACTERS_CACHE = {}
    return CHARACTERS_CACHE
  end
  CHARACTERS_CACHE = parsed
  return CHARACTERS_CACHE
end

local function getCharacterDef(characterId)
  local data = loadCharacters()
  local chars = type(data.characters) == "table" and data.characters or {}
  return chars[tostring(characterId or "")]
end

local function lerp(fromValue, toValue, alpha)
  return fromValue + (toValue - fromValue) * alpha
end

local function easeOutBack(alpha)
  local tValue = math.max(0, math.min(1, alpha))
  local c1 = 1.70158
  local c3 = c1 + 1
  local value = tValue - 1
  return 1 + c3 * value * value * value + c1 * value * value
end

function ChargeGauge.new(params)
  local options = type(params) == "table" and params or {}
  local instance = {
    _x = options.x or 0,
    _y = options.y or 0,
    _w = options.w or Constants.CHARGE_GAUGE_W,
    _h = options.h or Constants.CHARGE_GAUGE_H,
    _characterId = tostring(options.characterId or ""),
    _chargePercent = math.max(0, math.min(1, tonumber(options.chargePercent) or 0)),
    _displayPercent = math.max(0, math.min(1, tonumber(options.chargePercent) or 0)),
    _isFull = false,
    _pulseTimer = 0,
    _onAbilityClick = options.onAbilityClick or nil,
    _enabled = options.enabled ~= false,
    _language = tostring(options.language or "ko")
  }
  setmetatable(instance, ChargeGauge)
  return instance
end

function ChargeGauge:setCharge(percent)
  self._chargePercent = math.max(0, math.min(1, tonumber(percent) or 0))
  self._isFull = self._chargePercent >= Constants.CHARGE_MAX - 0.001
end

function ChargeGauge:setCharacterId(characterId)
  self._characterId = tostring(characterId or "")
end

function ChargeGauge:setEnabled(enabled)
  self._enabled = enabled ~= false
end

function ChargeGauge:update(dt)
  self._displayPercent = lerp(self._displayPercent, self._chargePercent, math.min(1, dt * 8))
  if self._isFull then
    self._pulseTimer = self._pulseTimer + dt
  else
    self._pulseTimer = 0
  end
end

function ChargeGauge:isHovered(mouseX, mouseY)
  if not self._enabled or not self._isFull then
    return false
  end
  return mouseX >= self._x and mouseX <= self._x + self._w
    and mouseY >= self._y and mouseY <= self._y + self._h
end

function ChargeGauge:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return false
  end
  if self:isHovered(mouseX, mouseY) and type(self._onAbilityClick) == "function" then
    self._onAbilityClick()
    return true
  end
  return false
end

function ChargeGauge:draw(mouseX, mouseY)
  local charDef = getCharacterDef(self._characterId)
  local ability = charDef and charDef.ability
  local charName = (self._language == "ko") and (charDef and charDef.nameKo or "???")
    or (charDef and charDef.nameEn or "???")
  local abilityName = (self._language == "ko") and (ability and ability.nameKo or "???")
    or (ability and ability.nameEn or "???")

  local x = self._x
  local y = self._y
  local w = self._w
  local h = self._h
  local radius = Constants.CHARGE_GAUGE_RADIUS

  -- 패널 배경
  local isHovered = self:isHovered(mouseX or -1, mouseY or -1)
  if self._isFull and isHovered then
    love.graphics.setColor(0.25, 0.45, 0.30, 0.95)
  elseif self._isFull then
    love.graphics.setColor(0.18, 0.35, 0.22, 0.92)
  else
    love.graphics.setColor(Constants.COLOR_PANEL)
  end
  love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", x, y, w, h, 8, 8)

  -- 펄스 효과 (100% 시)
  if self._isFull then
    local pulsePhase = (self._pulseTimer % Constants.CHARGE_GAUGE_PULSE_PERIOD_SEC) / Constants.CHARGE_GAUGE_PULSE_PERIOD_SEC
    local pulseAlpha = Constants.CHARGE_GAUGE_PULSE_ALPHA_MIN
      + (Constants.CHARGE_GAUGE_PULSE_ALPHA_MAX - Constants.CHARGE_GAUGE_PULSE_ALPHA_MIN)
      * (math.sin(pulsePhase * math.pi * 2) * 0.5 + 0.5)
    love.graphics.setColor(1.0, 0.92, 0.30, pulseAlpha)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
  end

  -- 원형 충전 게이지
  local gaugeCenterX = x + radius + 12
  local gaugeCenterY = y + h * 0.5

  -- 배경 원
  love.graphics.setColor(0.10, 0.12, 0.18, 1.0)
  love.graphics.circle("fill", gaugeCenterX, gaugeCenterY, radius)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.circle("line", gaugeCenterX, gaugeCenterY, radius)

  -- 충전량 원호
  local displayPct = self._displayPercent
  if displayPct > 0.001 then
    local segments = math.max(4, math.floor(displayPct * 64))
    local startAngle = -math.pi * 0.5
    local endAngle = startAngle + displayPct * math.pi * 2

    if self._isFull then
      love.graphics.setColor(1.0, 0.90, 0.20, 1.0)
    elseif displayPct > 0.66 then
      love.graphics.setColor(0.25, 0.80, 0.35, 1.0)
    elseif displayPct > 0.33 then
      love.graphics.setColor(0.90, 0.75, 0.22, 1.0)
    else
      love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    end

    love.graphics.arc("fill", gaugeCenterX, gaugeCenterY, radius - 2, startAngle, endAngle, segments)
  end

  -- 퍼센트 텍스트
  love.graphics.setFont(FontManager.getFont("small"))
  local pctText = string.format("%.0f%%", self._displayPercent * 100)
  if self._isFull then
    love.graphics.setColor(1.0, 0.92, 0.30, 1.0)
  else
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  end
  local textW = FontManager.getFont("small"):getWidth(pctText)
  love.graphics.print(pctText, gaugeCenterX - textW * 0.5, gaugeCenterY - 10)

  -- 캐릭터명 + 초능력명
  local textStartX = gaugeCenterX + radius + 12
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.print(charName, textStartX, y + 8)

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.print(abilityName, textStartX, y + h - 22)

  -- 초능력 버튼 표시
  if self._isFull then
    local btnText = self._language == "ko" and "⚡ 발동" or "⚡ USE"
    if isHovered then
      love.graphics.setColor(1.0, 0.96, 0.40, 1.0)
    else
      love.graphics.setColor(1.0, 0.88, 0.20, 0.9)
    end
    local btnW = FontManager.getFont("small"):getWidth(btnText) + 16
    love.graphics.print(btnText, x + w - btnW - 8, y + h - 24)
  end
end

return ChargeGauge
