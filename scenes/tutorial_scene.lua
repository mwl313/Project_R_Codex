--[[
파일명: tutorial_scene.lua
모듈명: TutorialScene

역할:
- 5단계 튜토리얼 씬
- 알 배치 → 조준/발사 → 충전 → 초능력 발동 → 완료

외부에서 사용 가능한 함수:
- TutorialScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local ChargeGauge = require("ui.charge_gauge")

local TutorialScene = {}
TutorialScene.__index = TutorialScene

local function t(key, vars)
  return I18n.t(key, vars)
end

-- Constants for tutorial layout
local PLACEMENT_SLOTS = {
  { x = 140, y = 280 },
  { x = 140, y = 340 },
  { x = 140, y = 400 },
  { x = 200, y = 310 },
  { x = 200, y = 370 },
  { x = 260, y = 280 },
  { x = 260, y = 400 }
}

local TARGET_STONE = { x = 640, y = 360, radius = 28 }

local STEP_LABELS = {
  [1] = "Step 1",
  [2] = "Step 2",
  [3] = "Step 3",
  [4] = "Step 4",
  [5] = "Step 5"
}

local STEP_DESCRIPTIONS = {
  [1] = "빈 칸을 클릭해 알을 배치하세요 (7개)",
  [2] = "플레이 스톤에서 드래그하여 목표물을 맞히세요",
  [3] = "충전 게이지가 차오르는 것을 지켜보세요",
  [4] = "초능력 버튼을 클릭해 발동하세요!",
  [5] = "튜토리얼이 완료되었습니다!"
}

local TUTORIAL_STEPS = {
  "placement",
  "shot",
  "charge",
  "ability",
  "complete"
}

local function lerp(fromValue, toValue, alpha)
  return fromValue + (toValue - fromValue) * alpha
end

local function easeInOutBack(tValue)
  local clamped = math.max(0, math.min(1, tValue))
  local c1 = 1.70158
  local c2 = c1 * 1.525
  if clamped < 0.5 then
    local value = 2 * clamped
    return (math.pow(value, 2) * ((c2 + 1) * value - c2)) * 0.5
  else
    local value = 2 * clamped - 2
    return (math.pow(value, 2) * ((c2 + 1) * value + c2) + 2) * 0.5
  end
end

function TutorialScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _lastLanguage = app:getLanguage(),

    -- Tutorial state
    _tutorialState = "placement",
    _currentStepIndex = 1,

    -- Placement state
    _placedEggs = {},

    -- Shot state
    _playStoneX = 140,
    _playStoneY = 500,
    _isDragging = false,
    _dragStartX = 0,
    _dragStartY = 0,
    _dragCurrentX = 0,
    _dragCurrentY = 0,
    _hasHitTarget = false,

    -- Charge state
    _chargePercent = 0,
    _chargeTimer = 0,
    _chargeElapsed = 0,
    _chargePulseTimer = 0,

    -- Ability state
    _abilityButton = nil,
    _abilityEffectTimer = 0,
    _isPlayingAbilityEffect = false,
    _abilityEffectDuration = 2.0,

    -- Complete state
    _lobbyButton = nil
  }
  setmetatable(instance, TutorialScene)
  instance:rebuildLocalizedUi()
  return instance
end

function TutorialScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)

  self._abilityButton = Button.new({
    x = (Constants.BASE_WORLD_W - 200) * 0.5,
    y = 460,
    w = 200,
    h = 50,
    label = "⚡ 발동",
    onClick = function()
      if self._tutorialState == "ability" and not self._isPlayingAbilityEffect then
        self._isPlayingAbilityEffect = true
        self._abilityEffectTimer = 0
      end
    end
  })

  self._lobbyButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 460,
    label = "로비로 돌아가기",
    onClick = function()
      self._app:goScene("lobby", nil, Config.TRANSITION_BACK)
    end
  })
end

function TutorialScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()

  -- Reset all state
  self._tutorialState = "placement"
  self._currentStepIndex = 1
  self._placedEggs = {}
  self._playStoneX = 140
  self._playStoneY = 500
  self._isDragging = false
  self._dragStartX = 0
  self._dragStartY = 0
  self._dragCurrentX = 0
  self._dragCurrentY = 0
  self._hasHitTarget = false
  self._chargePercent = 0
  self._chargeTimer = 0
  self._chargeElapsed = 0
  self._chargePulseTimer = 0
  self._abilityEffectTimer = 0
  self._isPlayingAbilityEffect = false
end

function TutorialScene:advanceToStep(nextStepIndex)
  self._currentStepIndex = nextStepIndex
  self._tutorialState = TUTORIAL_STEPS[nextStepIndex]

  if nextStepIndex == 2 then
    -- shot step: reset shot state
    self._isDragging = false
    self._dragStartX = 0
    self._dragStartY = 0
    self._dragCurrentX = 0
    self._dragCurrentY = 0
    self._hasHitTarget = false
    self._playStoneX = 140
    self._playStoneY = 500

  elseif nextStepIndex == 3 then
    -- charge step: reset charge state
    self._chargePercent = 0
    self._chargeTimer = 0
    self._chargeElapsed = 0
    self._chargePulseTimer = 0

  elseif nextStepIndex == 4 then
    -- ability step: reset ability state
    self._abilityEffectTimer = 0
    self._isPlayingAbilityEffect = false

  elseif nextStepIndex == 5 then
    -- complete step: nothing to reset
  end
end

function TutorialScene:update(dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end

  if self._tutorialState == "charge" then
    -- Auto-charge from 0% to 100%
    self._chargeElapsed = self._chargeElapsed + dt
    local chargeDuration = 3.0 -- 3 seconds to fully charge
    self._chargePercent = math.min(1, self._chargeElapsed / chargeDuration)
    self._chargeTimer = self._chargeTimer + dt

    if self._chargePercent >= 1.0 then
      self._chargePulseTimer = self._chargePulseTimer + dt
      -- Auto advance to step 4 when charge is full
      self:advanceToStep(4)
    end

  elseif self._tutorialState == "ability" then
    if self._isPlayingAbilityEffect then
      self._abilityEffectTimer = self._abilityEffectTimer + dt
      if self._abilityEffectTimer >= self._abilityEffectDuration then
        self._isPlayingAbilityEffect = false
        self:advanceToStep(5)
      end
    end
  end
end
function TutorialScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  self._backButton:draw(mouseX, mouseY)

  -- Draw left panel with step description
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 20, 100, 180, 60, 6, 6)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 20, 100, 180, 60, 6, 6)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(STEP_LABELS[self._currentStepIndex], 20, 108, 180, "center")
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(STEP_DESCRIPTIONS[self._currentStepIndex], 20, 130, 180, "center")

  if self._tutorialState == "placement" then
    self:drawPlacement()
  elseif self._tutorialState == "shot" then
    self:drawShot()
  elseif self._tutorialState == "charge" then
    self:drawCharge()
  elseif self._tutorialState == "ability" then
    self:drawAbility()
  elseif self._tutorialState == "complete" then
    self:drawComplete()
  end
end

function TutorialScene:drawPlacement()
  -- Draw board
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 100, 220, 280, 260, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 100, 220, 280, 260, 8, 8)

  -- Draw placement slots (dashed guide circles)
  love.graphics.setColor(0.35, 0.50, 0.80, 0.40)
  for _, slot in ipairs(PLACEMENT_SLOTS) do
    love.graphics.circle("line", slot.x, slot.y, 22)
  end

  -- Draw placed eggs
  for _, egg in ipairs(self._placedEggs) do
    love.graphics.setColor(Constants.COLOR_STONE_HOST)
    love.graphics.circle("fill", egg.x, egg.y, 24)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.circle("line", egg.x, egg.y, 24)
  end

  -- Place count text
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("배치: " .. tostring(#self._placedEggs) .. " / " .. tostring(#PLACEMENT_SLOTS), 100, 488, 280, "center")

  -- Auto-advance when all placed
  if #self._placedEggs >= #PLACEMENT_SLOTS then
    self:advanceToStep(2)
  end
end

function TutorialScene:drawShot()
  -- Draw board
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 400, 200, 500, 360, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 400, 200, 500, 360, 8, 8)

  -- Draw target stone
  love.graphics.setColor(0.95, 0.55, 0.25, 1.0)
  love.graphics.circle("fill", TARGET_STONE.x, TARGET_STONE.y, TARGET_STONE.radius)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.circle("line", TARGET_STONE.x, TARGET_STONE.y, TARGET_STONE.radius)

  -- Draw play stone
  love.graphics.setColor(Constants.COLOR_STONE_HOST)
  love.graphics.circle("fill", self._playStoneX, self._playStoneY, 24)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.circle("line", self._playStoneX, self._playStoneY, 24)

  -- Draw drag trajectory line if dragging
  if self._isDragging then
    love.graphics.setColor(1.0, 1.0, 1.0, 0.50)
    love.graphics.setLineWidth(2)
    love.graphics.line(self._dragStartX, self._dragStartY, self._dragCurrentX, self._dragCurrentY)
    love.graphics.setLineWidth(1)
  end

  -- Hit feedback
  if self._hasHitTarget then
    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(0.25, 0.80, 0.35, 1.0)
    love.graphics.printf("HIT!", 0, 300, Constants.BASE_WORLD_W, "center")
  end

  -- Instruct text below
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("알에서 드래그하여 발사하세요", 400, 570, 500, "center")
end
function TutorialScene:drawCharge()
  -- Draw charge gauge widget
  local chargeGauge = ChargeGauge.new({
    x = (Constants.BASE_WORLD_W - Constants.CHARGE_GAUGE_W) * 0.5,
    y = 380,
    characterId = "1",
    chargePercent = self._chargePercent,
    language = self._app:getLanguage()
  })
  chargeGauge:setCharge(self._chargePercent)
  chargeGauge:update(0)
  chargeGauge:draw(mouseX or -1, mouseY or -1)

  -- Percent text below gauge
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  local pctText = string.format("충전 중... %.0f%%", self._chargePercent * 100)
  love.graphics.printf(pctText, 0, 450, Constants.BASE_WORLD_W, "center")
end

function TutorialScene:drawAbility()
  -- Draw a simple effect animation area
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("⚡ 초능력 발동 ⚡", 0, 280, Constants.BASE_WORLD_W, "center")

  -- Draw ability button
  self._abilityButton:draw(mouseX, mouseY)

  -- Draw effect animation if playing
  if self._isPlayingAbilityEffect then
    local progress = self._abilityEffectTimer / self._abilityEffectDuration
    local alpha = 1.0 - progress
    local radius = 40 + progress * 120
    love.graphics.setColor(0.30, 0.70, 1.00, alpha * 0.6)
    love.graphics.circle("fill", Constants.BASE_WORLD_W * 0.5, 360, radius)
    love.graphics.setColor(1.0, 0.92, 0.30, alpha)
    love.graphics.circle("line", Constants.BASE_WORLD_W * 0.5, 360, radius)
  end
end

function TutorialScene:drawComplete()
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(0.25, 0.80, 0.35, 1.0)
  love.graphics.printf(t("single.result.title_win") or "완료!", 0, 300, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("축하합니다! 튜토리얼을 모두 마쳤습니다.", 0, 360, Constants.BASE_WORLD_W, "center")

  self._lobbyButton:draw(mouseX, mouseY)
end
function TutorialScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end

  if self._tutorialState == "placement" then
    -- Check if clicking near an empty slot
    for _, slot in ipairs(PLACEMENT_SLOTS) do
      local dx = mouseX - slot.x
      local dy = mouseY - slot.y
      if dx * dx + dy * dy <= 30 * 30 then
        -- Check if this slot already has an egg
        local alreadyPlaced = false
        for _, egg in ipairs(self._placedEggs) do
          if math.abs(egg.x - slot.x) < 5 and math.abs(egg.y - slot.y) < 5 then
            alreadyPlaced = true
            break
          end
        end
        if not alreadyPlaced then
          table.insert(self._placedEggs, { x = slot.x, y = slot.y })
        end
        return
      end
    end

  elseif self._tutorialState == "shot" then
    -- Check if clicking on play stone (start drag)
    local dx = mouseX - self._playStoneX
    local dy = mouseY - self._playStoneY
    if dx * dx + dy * dy <= 30 * 30 then
      self._isDragging = true
      self._dragStartX = self._playStoneX
      self._dragStartY = self._playStoneY
      self._dragCurrentX = mouseX
      self._dragCurrentY = mouseY
    end

  elseif self._tutorialState == "ability" then
    if self._abilityButton:isHovered(mouseX, mouseY) then
      self._abilityButton:onClick()
    end

  elseif self._tutorialState == "complete" then
    if self._lobbyButton:isHovered(mouseX, mouseY) then
      self._lobbyButton:onClick()
    end
  end
end

function TutorialScene:mousereleased(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._tutorialState == "shot" and self._isDragging then
    self._isDragging = false

    -- Check if drag trajectory hits target (simple distance check)
    local dx = TARGET_STONE.x - self._dragStartX
    local dy = TARGET_STONE.y - self._dragStartY
    local dirLen = math.sqrt(dx * dx + dy * dy)
    if dirLen > 0.001 then
      local nx = dx / dirLen
      local ny = dy / dirLen
      -- Project drag line onto direction to target
      local dragDx = self._dragCurrentX - self._dragStartX
      local dragDy = self._dragCurrentY - self._dragStartY
      local dot = dragDx * nx + dragDy * ny
      local dragLen = math.sqrt(dragDx * dragDx + dragDy * dragDy)

      -- Hit if dot > 0 (drag toward target) and dragLen > 40
      if dot > 10 and dragLen > 40 then
        self._hasHitTarget = true
        self:advanceToStep(3)
      end
    end

    self._dragStartX = 0
    self._dragStartY = 0
    self._dragCurrentX = 0
    self._dragCurrentY = 0
  end
end

function TutorialScene:mousemoved(mouseX, mouseY, dx, dy)
  if self._tutorialState == "shot" and self._isDragging then
    self._dragCurrentX = mouseX
    self._dragCurrentY = mouseY
  end
end

function TutorialScene:keypressed(key)
  if key == "escape" then
    self._app:goScene("lobby", nil, Config.TRANSITION_BACK)
  end
end

return TutorialScene
