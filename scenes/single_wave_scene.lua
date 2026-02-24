--[[
파일명: single_wave_scene.lua
모듈명: SingleWaveScene

역할:
- 싱글 웨이브 무한모드 메인 씬.
- 런 시작 연출, 웨이브 전투, 업그레이드 오버레이, 일시정지 모달을 통합 관리한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local CardView = require("ui.card_view")
local CardAnimator = require("ui.card_animator")
local CardRegistry = require("single.card_registry")
local SingleProfileStore = require("single.single_profile_store")
local SingleWaveManager = require("single.single_wave_manager")
local SingleCombatCore = require("single.single_combat_core")
local UpgradeDraft = require("single.upgrade_draft")

local SingleWaveScene = {}
SingleWaveScene.__index = SingleWaveScene

local BOARD_X = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
local BOARD_Y = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5
local BOARD_CENTER_X = BOARD_X + Constants.BOARD_W * 0.5
local BOARD_CENTER_Y = BOARD_Y + Constants.BOARD_H * 0.5

local PANEL_LAYOUT = {
  wave = { order = 3, x = 40, y = 50, w = 240, h = 70 },
  score = { order = 2, x = 40, y = 140, w = 260, h = 230 },
  relic = { order = 1, x = 40, y = 400, w = 260, h = 260 }
}

local PANEL_ANIM = {
  wave = { delaySec = 0.24, durationSec = 0.45 },
  score = { delaySec = 0.12, durationSec = 0.50 },
  relic = { delaySec = 0.00, durationSec = 0.55 }
}

local DECK_ZONE_RECT = {
  x = 960,
  y = 250,
  w = 186,
  h = 228
}

local HAND_MAX_COUNT = 8
local INTRO_PANEL_TOTAL_SEC = 1.02
local INTRO_DECK_MOVE_SEC = 0.55
local UPGRADE_RESOLVE_SEC = 0.35

local function t(key, vars)
  return I18n.t(key, vars)
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

local function lerp(fromValue, toValue, alpha)
  return fromValue + (toValue - fromValue) * alpha
end

local function easeOutCubic(alpha)
  local tValue = clamp(alpha, 0, 1)
  local inv = 1 - tValue
  return 1 - inv * inv * inv
end

local function easeOutBack(alpha)
  local tValue = clamp(alpha, 0, 1)
  local c1 = 1.70158
  local c3 = c1 + 1
  local value = tValue - 1
  return 1 + c3 * value * value * value + c1 * value * value
end

local function pointInRect(x, y, rect)
  return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function getHandOpenBaseY()
  return Constants.BASE_WORLD_H
    + Constants.CARD_H * 0.5
    - Constants.CARD_HAND_PEEK_HEIGHT
    - Constants.CARD_HAND_OPEN_RISE_PX
end

local function getHandSlotPosition(index, count)
  local centerIndex = (count + 1) * 0.5
  local offset = index - centerIndex
  local x = Constants.BASE_WORLD_W * 0.5 + offset * Constants.CARD_HAND_OPEN_SPACING
  local y = getHandOpenBaseY() + math.abs(offset) * Constants.CARD_HAND_OPEN_ARC_PX
  return x, y
end

function SingleWaveScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _waveManager = nil,
    _core = nil,
    _lastLanguage = app:getLanguage(),
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,

    _isUpgradePending = false,
    _isUpgradeOverlayVisible = false,
    _isUpgradeHiddenByEsc = false,
    _upgradeOptionList = {},
    _upgradeButtonList = {},
    _selectedUpgradeIndex = nil,
    _confirmUpgradeButton = nil,
    _reopenUpgradeButton = nil,
    _upgradeResolveAnim = nil,

    _isPauseOverlayVisible = false,
    _pauseResumeButton = nil,
    _pauseLobbyButton = nil,
    _pauseResetButton = nil,
    _pauseSettingsButton = nil,

    _isSettingsOverlayVisible = false,
    _settingsModeWindowedButton = nil,
    _settingsModeFullscreenButton = nil,
    _settingsLanguageKoButton = nil,
    _settingsLanguageEnButton = nil,
    _settingsSaveButton = nil,
    _settingsCancelButton = nil,
    _settingsDisplayMode = Constants.DISPLAY_MODE_WINDOWED,
    _settingsLanguage = "ko",

    _isRunEnded = false,
    _runEndResult = nil,

    _relicScrollOffset = 0,
    _isRelicPanelDragging = false,
    _isRelicScrollbarDragging = false,
    _relicDragStartY = 0,
    _relicDragStartOffset = 0,

    _intro = {
      isActive = false,
      phase = "none",
      panelElapsedSec = 0,
      cardTimelineSec = 0,
      deckMoveElapsedSec = 0,
      introDeckTotalCount = 0,
      cardAnimator = nil
    }
  }
  setmetatable(instance, SingleWaveScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleWaveScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleWaveScene:loadProfileOrDefault()
  local profile, loadError = SingleProfileStore.load()
  self._profile = SingleProfileStore.ensureDefaults(profile)
  if loadError then
    self:setStatus(t("single.wave.status.profile_recovered"), Constants.COLOR_TEXT_SUB)
  end
end

function SingleWaveScene:buildIntroDealCardDisplayList()
  local dealCardIdList = self._waveManager:drawCardsToHand(5, HAND_MAX_COUNT)
  local displayList = {}
  for index, saveCardId in ipairs(dealCardIdList) do
    local cardDef = CardRegistry.getCard(saveCardId)
    displayList[#displayList + 1] = {
      id = "intro_" .. tostring(index),
      label = tostring((cardDef and cardDef.nameKo) or saveCardId)
    }
  end
  local totalCountBeforeDeal = self._waveManager:getDrawPileCount() + #dealCardIdList
  return displayList, totalCountBeforeDeal
end

function SingleWaveScene:startIntroSequence()
  local dealDisplayList, totalCountBeforeDeal = self:buildIntroDealCardDisplayList()
  local introCardAnimator = CardAnimator.new({
    boardX = BOARD_X,
    boardY = BOARD_Y,
    boardW = Constants.BOARD_W,
    boardH = Constants.BOARD_H,
    localHandY = getHandOpenBaseY()
  })
  introCardAnimator:beginSingleDeal(dealDisplayList, totalCountBeforeDeal)

  self._intro = {
    isActive = true,
    phase = "panels",
    panelElapsedSec = 0,
    cardTimelineSec = 0,
    deckMoveElapsedSec = 0,
    introDeckTotalCount = totalCountBeforeDeal,
    cardAnimator = introCardAnimator
  }
  self._core = nil
  self._isPauseOverlayVisible = false
  self._isSettingsOverlayVisible = false
  self._isUpgradePending = false
  self._isUpgradeOverlayVisible = false
  self._isUpgradeHiddenByEsc = false
  self._upgradeOptionList = {}
  self._upgradeButtonList = {}
  self._selectedUpgradeIndex = nil
  self._upgradeResolveAnim = nil
  self._isRunEnded = false
  self._runEndResult = nil
  self:setStatus(t("single.wave.status.intro_playing"), Constants.COLOR_TEXT_SUB)
end

function SingleWaveScene:startRun()
  self:loadProfileOrDefault()
  self._waveManager = SingleWaveManager.new(self._profile)
  self._relicScrollOffset = 0
  self:startIntroSequence()
end

function SingleWaveScene:startCurrentWaveCombat()
  local nodeType = self._waveManager:getCurrentNodeType()
  local nodeId = self._waveManager:getCurrentNodeId()
  local stageIndex = self._waveManager:getStageIndex()
  self._core = SingleCombatCore.new({
    app = self._app,
    profile = self._profile,
    runState = self._waveManager:getRuntimeState(),
    nodeType = nodeType,
    nodeId = nodeId,
    stageIndex = stageIndex,
    disableTurnTimer = true,
    suppressHud = true,
    initialHandCardIdList = self._waveManager:getHandCardIdList(),
    onCardConsumed = function(saveCardId)
      self._waveManager:addConsumedCard(saveCardId)
    end,
    onShotResolved = function(meta)
      self:onShotResolved(meta)
    end,
    onCombatEnd = function(result)
      self:onWaveCombatEnd(result)
    end
  })
  self:setStatus(t("single.wave.status.wave_start", {
    wave = tostring(self._waveManager:getWaveIndex())
  }), Constants.COLOR_TEXT_SUB)
end

function SingleWaveScene:onShotResolved(meta)
  if type(meta) ~= "table" then
    return
  end
  if tonumber(meta.ownerPlayerIndex) ~= 1 then
    return
  end
  local enemyOut = math.max(0, math.floor(tonumber(meta.enemyOut) or 0))
  self._waveManager:addEnemiesKilled(enemyOut)
  self._waveManager:updateCombo(enemyOut)
end

function SingleWaveScene:openUpgradeOverlay()
  self._isUpgradePending = true
  self._isUpgradeOverlayVisible = true
  self._isUpgradeHiddenByEsc = false
  self._selectedUpgradeIndex = nil
  self._upgradeOptionList = UpgradeDraft.build({
    rng = self._waveManager:getRng(),
    relicIdList = self._waveManager:getRelicIdList()
  })
  self:rebuildUpgradeButtons()
  self:setStatus(t("single.wave.upgrade.status.choose"), Constants.COLOR_TEXT_SUB)
end

function SingleWaveScene:onWaveCombatEnd(result)
  if self._core then
    self._waveManager:setHandCardIdList(self._core:getCurrentHandCardIdList())
  end
  self._core = nil

  if result == "win" then
    self:openUpgradeOverlay()
    return
  end

  self._isRunEnded = true
  self._runEndResult = (result == "draw") and "draw" or "lose"
  self:setStatus(t("single.wave.status.run_end"), Constants.COLOR_DANGER)
end

function SingleWaveScene:getPanelX(panelId)
  local layout = PANEL_LAYOUT[panelId]
  if not layout then
    return 0
  end
  if not self._intro.isActive then
    return layout.x
  end
  local animSpec = PANEL_ANIM[panelId] or { delaySec = 0, durationSec = 0.5 }
  local progress = clamp((self._intro.panelElapsedSec - animSpec.delaySec) / animSpec.durationSec, 0, 1)
  local eased = easeOutBack(progress)
  return lerp(-layout.w - 80, layout.x, eased)
end

function SingleWaveScene:getRelicListViewportRect()
  local panelX = self:getPanelX("relic")
  local panel = PANEL_LAYOUT.relic
  return {
    x = panelX + 14,
    y = panel.y + 56,
    w = panel.w - 32,
    h = panel.h - 72
  }
end

function SingleWaveScene:getRelicScrollMetrics()
  local viewport = self:getRelicListViewportRect()
  local relicList = self._waveManager and self._waveManager:getRelicBuffEntryList() or {}
  local lineHeight = 22
  local contentHeight = #relicList * lineHeight
  local maxOffset = math.max(0, contentHeight - viewport.h)
  local ratio = (contentHeight > 0) and clamp(viewport.h / contentHeight, 0, 1) or 1
  local handleHeight = math.max(26, viewport.h * ratio)
  local handleTravel = math.max(0, viewport.h - handleHeight)
  local offsetRatio = (maxOffset > 0) and (self._relicScrollOffset / maxOffset) or 0
  local handleY = viewport.y + handleTravel * offsetRatio
  return {
    viewport = viewport,
    contentHeight = contentHeight,
    maxOffset = maxOffset,
    lineHeight = lineHeight,
    handleRect = {
      x = viewport.x + viewport.w - 8,
      y = handleY,
      w = 8,
      h = handleHeight
    }
  }
end

function SingleWaveScene:scrollRelicList(delta)
  local metrics = self:getRelicScrollMetrics()
  self._relicScrollOffset = clamp(self._relicScrollOffset + delta, 0, metrics.maxOffset)
end

function SingleWaveScene:scrollRelicListToBottom()
  local metrics = self:getRelicScrollMetrics()
  self._relicScrollOffset = metrics.maxOffset
end

function SingleWaveScene:getDeckCenter()
  return DECK_ZONE_RECT.x + DECK_ZONE_RECT.w * 0.5, DECK_ZONE_RECT.y + DECK_ZONE_RECT.h * 0.5 + 20
end

function SingleWaveScene:completeUpgradeResolution()
  self._upgradeResolveAnim = nil
  self._isUpgradePending = false
  self._isUpgradeOverlayVisible = false
  self._isUpgradeHiddenByEsc = false
  self._selectedUpgradeIndex = nil
  self._upgradeOptionList = {}
  self._upgradeButtonList = {}
  self._waveManager:advanceWave()
  self:startCurrentWaveCombat()
end

function SingleWaveScene:updateUpgradeResolveAnimation(dt)
  local anim = self._upgradeResolveAnim
  if type(anim) ~= "table" then
    return
  end
  anim.elapsedSec = anim.elapsedSec + dt
  if anim.elapsedSec < anim.durationSec then
    return
  end
  self:completeUpgradeResolution()
end

function SingleWaveScene:applyUpgradeOption(option, sourceX, sourceY)
  if type(option) ~= "table" then
    return false, nil
  end

  if option.category == UpgradeDraft.CATEGORY_CARD then
    local cardId = option.payload and option.payload.cardId
    local isAdded, target = self._waveManager:addCardReward(cardId, HAND_MAX_COUNT)
    if not isAdded then
      self:setStatus(t("single.wave.upgrade.status.apply_failed"), Constants.COLOR_DANGER)
      return false, nil
    end
    local titleText = self:getUpgradeOptionTitle(option)
    local targetX, targetY
    if target == "hand" then
      local handCount = self._waveManager:getHandCount()
      targetX, targetY = getHandSlotPosition(handCount, handCount)
      self:setStatus(t("single.wave.upgrade.status.card_to_hand"), Constants.COLOR_TEXT_SUB)
    else
      targetX, targetY = self:getDeckCenter()
      self:setStatus(t("single.wave.upgrade.status.card_to_deck"), Constants.COLOR_TEXT_SUB)
    end
    return true, {
      kind = "card",
      label = titleText,
      sourceX = sourceX,
      sourceY = sourceY,
      targetX = targetX,
      targetY = targetY,
      toDeck = target == "deck",
      elapsedSec = 0,
      durationSec = UPGRADE_RESOLVE_SEC
    }
  end

  if option.category == UpgradeDraft.CATEGORY_RELIC then
    local relicId = option.payload and option.payload.relicId
    local isAdded = self._waveManager:addRelic(relicId)
    if isAdded then
      self:scrollRelicListToBottom()
      self:setStatus(t("single.wave.upgrade.status.relic_added"), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("single.wave.upgrade.status.relic_skip"), Constants.COLOR_TEXT_SUB)
    end
    local viewport = self:getRelicListViewportRect()
    local targetX = viewport.x + 52
    local targetY = viewport.y + viewport.h - 26
    return true, {
      kind = "relic",
      label = self:getUpgradeOptionTitle(option),
      sourceX = sourceX,
      sourceY = sourceY,
      targetX = targetX,
      targetY = targetY,
      elapsedSec = 0,
      durationSec = UPGRADE_RESOLVE_SEC
    }
  end

  if option.category == UpgradeDraft.CATEGORY_HAND_OP then
    local handOpId = option.payload and option.payload.handOpId
    local result = self._waveManager:applyHandOperation(handOpId, HAND_MAX_COUNT)
    if result.isApplied then
      self:setStatus(t("single.wave.upgrade.status.hand_op_applied"), Constants.COLOR_TEXT_SUB)
      local deckX, deckY = self:getDeckCenter()
      return true, {
        kind = "hand_op",
        label = self:getUpgradeOptionTitle(option),
        sourceX = sourceX,
        sourceY = sourceY,
        targetX = deckX,
        targetY = deckY,
        elapsedSec = 0,
        durationSec = UPGRADE_RESOLVE_SEC + 0.25
      }
    end
    self:setStatus(t("single.wave.upgrade.status.apply_failed"), Constants.COLOR_DANGER)
    return false, nil
  end

  return false, nil
end

function SingleWaveScene:confirmUpgradeSelection()
  if not self._isUpgradeOverlayVisible or not self._isUpgradePending or self._upgradeResolveAnim then
    return
  end
  if not self._selectedUpgradeIndex then
    self:setStatus(t("single.wave.upgrade.status.select_required"), Constants.COLOR_DANGER)
    return
  end

  local selectedButton = self._upgradeButtonList[self._selectedUpgradeIndex]
  local sourceX = selectedButton and (selectedButton.x + selectedButton.w * 0.5) or BOARD_CENTER_X
  local sourceY = selectedButton and (selectedButton.y + selectedButton.h * 0.5) or BOARD_CENTER_Y
  local option = self._upgradeOptionList[self._selectedUpgradeIndex]
  local isApplied, resolveAnim = self:applyUpgradeOption(option, sourceX, sourceY)
  if not isApplied then
    return
  end

  self._isUpgradeOverlayVisible = false
  self._isUpgradeHiddenByEsc = false
  self._selectedUpgradeIndex = nil
  self._upgradeResolveAnim = resolveAnim
  if not resolveAnim then
    self:completeUpgradeResolution()
  end
end

function SingleWaveScene:rebuildUpgradeButtons()
  self._upgradeButtonList = {}
  local count = math.max(1, #self._upgradeOptionList)
  local buttonWidth = 256
  local buttonHeight = 196
  local gap = 22
  local totalWidth = count * buttonWidth + (count - 1) * gap
  local startX = (Constants.BASE_WORLD_W - totalWidth) * 0.5
  local y = 224
  for index = 1, count do
    self._upgradeButtonList[index] = Button.new({
      x = startX + (index - 1) * (buttonWidth + gap),
      y = y,
      w = buttonWidth,
      h = buttonHeight,
      label = "",
      onClick = function()
        self._selectedUpgradeIndex = index
      end
    })
  end
end

function SingleWaveScene:getUpgradeOptionTitle(option)
  if type(option) ~= "table" then
    return "-"
  end
  if option.titleKey and option.titleKey ~= "" then
    local translated = t(option.titleKey)
    if type(translated) == "string" and not translated:find("^%[%[missing:") then
      return translated
    end
  end
  if option.category == UpgradeDraft.CATEGORY_RELIC and option.payload and option.payload.relicId then
    local key = "single.relic.name." .. tostring(option.payload.relicId)
    local translated = t(key)
    if type(translated) == "string" and not translated:find("^%[%[missing:") then
      return translated
    end
  end
  return tostring(option.titleText or option.optionId or "-")
end

function SingleWaveScene:getUpgradeOptionDesc(option)
  if type(option) ~= "table" then
    return ""
  end
  if option.descKey and option.descKey ~= "" then
    local translated = t(option.descKey)
    if type(translated) == "string" and not translated:find("^%[%[missing:") then
      return translated
    end
  end
  if option.category == UpgradeDraft.CATEGORY_RELIC and option.payload and option.payload.relicId then
    local key = "single.relic.desc." .. tostring(option.payload.relicId)
    local translated = t(key)
    if type(translated) == "string" and not translated:find("^%[%[missing:") then
      return translated
    end
  end
  return tostring(option.descText or "")
end

function SingleWaveScene:getUpgradeCategoryLabel(option)
  if not option then
    return ""
  end
  if option.category == UpgradeDraft.CATEGORY_CARD then
    return t("single.wave.upgrade.category.card")
  end
  if option.category == UpgradeDraft.CATEGORY_RELIC then
    return t("single.wave.upgrade.category.relic")
  end
  return t("single.wave.upgrade.category.hand_ops")
end

function SingleWaveScene:openSettingsOverlay()
  self._isSettingsOverlayVisible = true
  self._settingsDisplayMode = self._app:getDisplayMode()
  self._settingsLanguage = self._app:getLanguage()
end

function SingleWaveScene:closeSettingsOverlay()
  self._isSettingsOverlayVisible = false
end

function SingleWaveScene:applySettingsOverlay()
  local isSaved, warning = self._app:savePersistentSettings({
    displayMode = self._settingsDisplayMode,
    language = self._settingsLanguage
  })
  if not isSaved then
    self:setStatus(tostring(warning or ""), Constants.COLOR_DANGER)
    return
  end
  if warning then
    self:setStatus(tostring(warning), Constants.COLOR_TEXT_SUB)
  else
    self:setStatus(t("single.wave.pause.status.settings_saved"), Constants.COLOR_TEXT_SUB)
  end
  self:closeSettingsOverlay()
  self:rebuildLocalizedUi()
end

function SingleWaveScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._confirmUpgradeButton = Button.new({
    x = (Constants.BASE_WORLD_W - 280) * 0.5,
    y = 542,
    w = 280,
    h = 52,
    label = t("single.wave.upgrade.button.confirm"),
    onClick = function()
      self:confirmUpgradeSelection()
    end
  })

  self._reopenUpgradeButton = Button.new({
    x = (Constants.BASE_WORLD_W - 260) * 0.5,
    y = (Constants.BASE_WORLD_H - 48) * 0.5,
    w = 260,
    h = 48,
    label = t("single.wave.upgrade.button.reopen"),
    onClick = function()
      self._isUpgradeOverlayVisible = true
      self._isUpgradeHiddenByEsc = false
    end
  })

  self._pauseResumeButton = Button.new({
    x = (Constants.BASE_WORLD_W - 260) * 0.5,
    y = 252,
    w = 260,
    h = 46,
    label = t("single.wave.pause.button.resume"),
    onClick = function()
      self._isPauseOverlayVisible = false
    end
  })

  self._pauseLobbyButton = Button.new({
    x = (Constants.BASE_WORLD_W - 260) * 0.5,
    y = 304,
    w = 260,
    h = 46,
    label = t("single.wave.pause.button.lobby"),
    onClick = function()
      self._app:goScene("lobby", nil, Config.TRANSITION_BACK)
    end
  })

  self._pauseResetButton = Button.new({
    x = (Constants.BASE_WORLD_W - 260) * 0.5,
    y = 356,
    w = 260,
    h = 46,
    label = t("single.wave.pause.button.reset"),
    onClick = function()
      self:startRun()
    end
  })

  self._pauseSettingsButton = Button.new({
    x = (Constants.BASE_WORLD_W - 260) * 0.5,
    y = 408,
    w = 260,
    h = 46,
    label = t("single.wave.pause.button.settings"),
    onClick = function()
      self:openSettingsOverlay()
    end
  })

  local panelX = (Constants.BASE_WORLD_W - 560) * 0.5
  local panelY = 186
  self._settingsModeWindowedButton = Button.new({
    x = panelX + 40,
    y = panelY + 92,
    w = 230,
    h = 42,
    label = t("lobby.display_mode.option_windowed"),
    onClick = function()
      self._settingsDisplayMode = Constants.DISPLAY_MODE_WINDOWED
    end
  })

  self._settingsModeFullscreenButton = Button.new({
    x = panelX + 290,
    y = panelY + 92,
    w = 230,
    h = 42,
    label = t("lobby.display_mode.option_fullscreen"),
    onClick = function()
      self._settingsDisplayMode = Constants.DISPLAY_MODE_FULLSCREEN
    end
  })

  self._settingsLanguageKoButton = Button.new({
    x = panelX + 40,
    y = panelY + 156,
    w = 230,
    h = 42,
    label = t("lobby.language.option_ko"),
    onClick = function()
      self._settingsLanguage = "ko"
    end
  })

  self._settingsLanguageEnButton = Button.new({
    x = panelX + 290,
    y = panelY + 156,
    w = 230,
    h = 42,
    label = t("lobby.language.option_en"),
    onClick = function()
      self._settingsLanguage = "en"
    end
  })

  self._settingsSaveButton = Button.new({
    x = panelX + 96,
    y = panelY + 252,
    w = 160,
    h = 44,
    label = t("common.button.save"),
    onClick = function()
      self:applySettingsOverlay()
    end
  })

  self._settingsCancelButton = Button.new({
    x = panelX + 304,
    y = panelY + 252,
    w = 160,
    h = 44,
    label = t("common.button.cancel"),
    onClick = function()
      self:closeSettingsOverlay()
    end
  })

  self:rebuildUpgradeButtons()
end

function SingleWaveScene:enter(_params)
  self:rebuildLocalizedUi()
  self:startRun()
end

function SingleWaveScene:updateIntro(dt)
  self._intro.panelElapsedSec = self._intro.panelElapsedSec + dt
  if self._intro.phase == "panels" and self._intro.panelElapsedSec >= INTRO_PANEL_TOTAL_SEC then
    self._intro.phase = "card_timeline"
    return
  end

  if self._intro.phase == "card_timeline" then
    if self._intro.cardAnimator then
      self._intro.cardAnimator:update(dt)
    end
    self._intro.cardTimelineSec = self._intro.cardTimelineSec + dt
    if (not self._intro.cardAnimator) or (not self._intro.cardAnimator:isOverlayVisible()) then
      self._intro.phase = "deck_move"
      self._intro.deckMoveElapsedSec = 0
    end
    return
  end

  if self._intro.phase == "deck_move" then
    self._intro.deckMoveElapsedSec = self._intro.deckMoveElapsedSec + dt
  end
  if self._intro.phase == "deck_move" and self._intro.deckMoveElapsedSec >= INTRO_DECK_MOVE_SEC then
    self._intro.isActive = false
    self._intro.phase = "done"
    self:startCurrentWaveCombat()
  end
end

function SingleWaveScene:update(dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end

  if self._intro.isActive then
    self:updateIntro(dt)
    return
  end

  if self._upgradeResolveAnim then
    self:updateUpgradeResolveAnimation(dt)
    return
  end

  local mouseX, mouseY = self._app:getMouseWorldPosition()
  if self._core and (not self._isPauseOverlayVisible) and (not self._isUpgradeOverlayVisible) and (not self._isUpgradePending) and (not self._isSettingsOverlayVisible) then
    self._core:update(dt, mouseX, mouseY)
  end
end

function SingleWaveScene:drawPanel(panelId)
  local layout = PANEL_LAYOUT[panelId]
  local x = self:getPanelX(panelId)
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", x, layout.y, layout.w, layout.h, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", x, layout.y, layout.w, layout.h, 8, 8)
  return x, layout.y, layout.w, layout.h
end

function SingleWaveScene:drawWavePanel()
  local x, y, w, _ = self:drawPanel("wave")
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.hud.wave_title"), x + 12, y + 10, w - 24, "left")
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.printf(t("single.wave.hud.wave_value", {
    wave = tostring(self._waveManager and self._waveManager:getWaveIndex() or 1)
  }), x + 12, y + 42, w - 24, "left")
end

function SingleWaveScene:drawScorePanel()
  local x, y, w, _ = self:drawPanel("score")
  local score = self._waveManager and self._waveManager:getScoreSnapshot() or { maxCombo = 0, enemiesKilled = 0 }
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.hud.score_title"), x + 12, y + 10, w - 24, "left")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.wave.hud.max_combo", {
    value = tostring(score.maxCombo)
  }), x + 12, y + 48, w - 24, "left")
  love.graphics.printf(t("single.wave.hud.enemies_killed", {
    value = tostring(score.enemiesKilled)
  }), x + 12, y + 76, w - 24, "left")
end

function SingleWaveScene:drawRelicPanel()
  local x, y, w, _ = self:drawPanel("relic")
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.hud.relic_title"), x + 12, y + 10, w - 24, "left")

  local metrics = self:getRelicScrollMetrics()
  local viewport = metrics.viewport
  local relicList = self._waveManager and self._waveManager:getRelicBuffEntryList() or {}
  local previousScissorX, previousScissorY, previousScissorW, previousScissorH = love.graphics.getScissor()
  love.graphics.setScissor(viewport.x, viewport.y, viewport.w, viewport.h)
  love.graphics.setFont(FontManager.getFont("small"))
  for index, relic in ipairs(relicList) do
    local relicId = tostring(relic.relicId or "")
    local lineY = viewport.y + (index - 1) * metrics.lineHeight - self._relicScrollOffset
    local nameText = t("single.relic.name." .. relicId)
    if type(nameText) ~= "string" or nameText:find("^%[%[missing:") then
      nameText = relicId
    end
    local descText = t("single.relic.desc." .. relicId)
    if type(descText) ~= "string" or descText:find("^%[%[missing:") then
      descText = ""
    end
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(nameText, viewport.x + 2, lineY)
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(descText, viewport.x + 2, lineY + 12)
  end
  if previousScissorW then
    love.graphics.setScissor(previousScissorX, previousScissorY, previousScissorW, previousScissorH)
  else
    love.graphics.setScissor()
  end

  if metrics.maxOffset > 0 then
    love.graphics.setColor(0.18, 0.20, 0.26, 1.0)
    love.graphics.rectangle("fill", metrics.handleRect.x, viewport.y, metrics.handleRect.w, viewport.h, 4, 4)
    love.graphics.setColor(Constants.COLOR_BUTTON_HOVER)
    love.graphics.rectangle("fill", metrics.handleRect.x, metrics.handleRect.y, metrics.handleRect.w, metrics.handleRect.h, 4, 4)
  end
end

function SingleWaveScene:drawDeckZone()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", DECK_ZONE_RECT.x, DECK_ZONE_RECT.y, DECK_ZONE_RECT.w, DECK_ZONE_RECT.h, 10, 10)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", DECK_ZONE_RECT.x, DECK_ZONE_RECT.y, DECK_ZONE_RECT.w, DECK_ZONE_RECT.h, 10, 10)
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.hud.deck_title"), DECK_ZONE_RECT.x, DECK_ZONE_RECT.y + 16, DECK_ZONE_RECT.w, "center")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.wave.hud.deck_count", {
    drawCount = tostring(self._waveManager and self._waveManager:getDrawPileCount() or 0),
    discardCount = tostring(self._waveManager and self._waveManager:getDiscardPileCount() or 0),
    handCount = tostring(self._waveManager and self._waveManager:getHandCount() or 0),
    handMax = tostring(HAND_MAX_COUNT)
  }), DECK_ZONE_RECT.x + 8, DECK_ZONE_RECT.y + 54, DECK_ZONE_RECT.w - 16, "center")
end

function SingleWaveScene:drawDeckStackPrimitive(centerX, centerY, count, alpha)
  local drawCount = math.max(1, math.floor(tonumber(count) or 1))
  local safeAlpha = clamp(tonumber(alpha) or 1.0, 0, 1)
  for depth = 1, drawCount do
    love.graphics.setColor(0.21, 0.28, 0.44, 0.95 * safeAlpha)
    love.graphics.rectangle("fill", centerX - 36 + depth * 2, centerY - 52 + depth * 2, 72, 104, 7, 7)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], safeAlpha)
    love.graphics.rectangle("line", centerX - 36 + depth * 2, centerY - 52 + depth * 2, 72, 104, 7, 7)
  end
end

function SingleWaveScene:drawIntroOverlay()
  local centerX = BOARD_CENTER_X
  local centerY = BOARD_CENTER_Y
  local phase = self._intro.phase

  if phase == "card_timeline" and self._intro.cardAnimator then
    self._intro.cardAnimator:draw()
  end

  if phase == "deck_move" then
    local progress = clamp(self._intro.deckMoveElapsedSec / INTRO_DECK_MOVE_SEC, 0, 1)
    local eased = easeOutCubic(progress)
    local targetX, targetY = self:getDeckCenter()
    local drawX = lerp(centerX, targetX, eased)
    local drawY = lerp(centerY, targetY, eased)
    local stackCount = math.min(10, math.max(4, math.floor((self._intro.introDeckTotalCount or 5) * 0.16)))
    self:drawDeckStackPrimitive(drawX, drawY, stackCount, 1.0)
  end
end

function SingleWaveScene:drawUpgradeOverlay(mouseX, mouseY)
  love.graphics.setColor(0, 0, 0, 0.62)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 108, 118, Constants.BASE_WORLD_W - 216, Constants.BASE_WORLD_H - 188, 12, 12)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 108, 118, Constants.BASE_WORLD_W - 216, Constants.BASE_WORLD_H - 188, 12, 12)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.upgrade.title"), 0, 138, Constants.BASE_WORLD_W, "center")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.wave.upgrade.subtitle"), 0, 182, Constants.BASE_WORLD_W, "center")

  for index, button in ipairs(self._upgradeButtonList) do
    local option = self._upgradeOptionList[index]
    button.isPressed = self._selectedUpgradeIndex == index
    button:draw(mouseX, mouseY)
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(self:getUpgradeCategoryLabel(option), button.x + 12, button.y + 12, button.w - 24, "left")
    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf(self:getUpgradeOptionTitle(option), button.x + 12, button.y + 42, button.w - 24, "left")
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(self:getUpgradeOptionDesc(option), button.x + 12, button.y + 84, button.w - 24, "left")
  end

  self._confirmUpgradeButton.isEnabled = self._selectedUpgradeIndex ~= nil
  self._confirmUpgradeButton:draw(mouseX, mouseY)
end

function SingleWaveScene:drawUpgradeResolveAnimation()
  local anim = self._upgradeResolveAnim
  if type(anim) ~= "table" then
    return
  end

  local progress = clamp(anim.elapsedSec / math.max(0.001, anim.durationSec), 0, 1)
  local eased = easeOutCubic(progress)
  local drawX = lerp(anim.sourceX or BOARD_CENTER_X, anim.targetX or BOARD_CENTER_X, eased)
  local drawY = lerp(anim.sourceY or BOARD_CENTER_Y, anim.targetY or BOARD_CENTER_Y, eased)

  if anim.kind == "card" then
    CardView.drawCard({
      x = drawX,
      y = drawY,
      w = Constants.CARD_W,
      h = Constants.CARD_H,
      label = tostring(anim.label or ""),
      backLabel = "?",
      isFaceUp = true,
      scale = lerp(1.0, 0.9, eased),
      alpha = 1.0,
      flipScaleX = 1.0,
      borderThickness = Constants.CARD_BORDER_THICKNESS,
      glowAlpha = Constants.CARD_GLOW_ALPHA,
      isHovered = false,
      isSelected = true
    })
    if anim.toDeck then
      local pulse = 1.0 + math.sin(progress * math.pi * 4) * 0.08
      local deckX, deckY = self:getDeckCenter()
      self:drawDeckStackPrimitive(deckX, deckY, 6, clamp(pulse, 0.75, 1.0))
    end
    return
  end

  if anim.kind == "relic" then
    love.graphics.setColor(0.96, 0.86, 0.38, 0.95 * (1.0 - progress * 0.3))
    love.graphics.rectangle("fill", drawX - 86, drawY - 22, 172, 44, 12, 12)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", drawX - 86, drawY - 22, 172, 44, 12, 12)
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(0.12, 0.12, 0.12, 1.0)
    love.graphics.printf(tostring(anim.label or ""), drawX - 76, drawY - 8, 152, "center")
    return
  end

  if anim.kind == "hand_op" then
    local deckX, deckY = self:getDeckCenter()
    local pulse = 1.0 + math.sin(progress * math.pi * 6) * 0.12
    love.graphics.setColor(0.40, 0.76, 1.0, 0.22)
    love.graphics.rectangle("fill", deckX - 78 * pulse, deckY - 112 * pulse, 156 * pulse, 224 * pulse, 12, 12)
    love.graphics.setColor(0.62, 0.88, 1.0, 0.92)
    love.graphics.rectangle("line", deckX - 78 * pulse, deckY - 112 * pulse, 156 * pulse, 224 * pulse, 12, 12)
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf(t("single.wave.upgrade.status.hand_op_applied"), deckX - 140, deckY + 122, 280, "center")
  end
end

function SingleWaveScene:drawPauseOverlay(mouseX, mouseY)
  love.graphics.setColor(0, 0, 0, 0.56)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 438, 188, 404, 296, 12, 12)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 438, 188, 404, 296, 12, 12)
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.pause.title"), 438, 206, 404, "center")
  self._pauseResumeButton:draw(mouseX, mouseY)
  self._pauseLobbyButton:draw(mouseX, mouseY)
  self._pauseResetButton:draw(mouseX, mouseY)
  self._pauseSettingsButton:draw(mouseX, mouseY)
end

function SingleWaveScene:drawSettingsOverlay(mouseX, mouseY)
  love.graphics.setColor(0, 0, 0, 0.64)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
  local panelX = (Constants.BASE_WORLD_W - 560) * 0.5
  local panelY = 186
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", panelX, panelY, 560, 320, 12, 12)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", panelX, panelY, 560, 320, 12, 12)
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("lobby.overlay.settings.title"), panelX, panelY + 16, 560, "center")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("lobby.overlay.settings.display_mode"), panelX + 40, panelY + 72, 480, "left")
  love.graphics.printf(t("lobby.overlay.settings.language"), panelX + 40, panelY + 136, 480, "left")

  self._settingsModeWindowedButton.isPressed = self._settingsDisplayMode == Constants.DISPLAY_MODE_WINDOWED
  self._settingsModeFullscreenButton.isPressed = self._settingsDisplayMode == Constants.DISPLAY_MODE_FULLSCREEN
  self._settingsLanguageKoButton.isPressed = self._settingsLanguage == "ko"
  self._settingsLanguageEnButton.isPressed = self._settingsLanguage == "en"
  self._settingsModeWindowedButton:draw(mouseX, mouseY)
  self._settingsModeFullscreenButton:draw(mouseX, mouseY)
  self._settingsLanguageKoButton:draw(mouseX, mouseY)
  self._settingsLanguageEnButton:draw(mouseX, mouseY)
  self._settingsSaveButton:draw(mouseX, mouseY)
  self._settingsCancelButton:draw(mouseX, mouseY)
end

function SingleWaveScene:drawRunEndOverlay(mouseX, mouseY)
  love.graphics.setColor(0, 0, 0, 0.52)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", 408, 238, 464, 214, 12, 12)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", 408, 238, 464, 214, 12, 12)
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  local titleKey = (self._runEndResult == "draw") and "single.wave.result.draw" or "single.wave.result.lose"
  love.graphics.printf(t(titleKey), 408, 264, 464, "center")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.wave.result.subtitle"), 408, 312, 464, "center")
  self._pauseLobbyButton:draw(mouseX, mouseY)
  self._pauseResetButton:draw(mouseX, mouseY)
end

function SingleWaveScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  if self._core then
    self._core:draw(mouseX, mouseY)
  else
    local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
    local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5
    love.graphics.setColor(Constants.COLOR_PANEL)
    love.graphics.rectangle("fill", boardX, boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", boardX, boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
  end

  self:drawWavePanel()
  self:drawScorePanel()
  self:drawRelicPanel()
  local shouldDrawDeckZone = (not self._intro.isActive) or self._intro.phase == "deck_move"
  if shouldDrawDeckZone then
    self:drawDeckZone()
    if not (self._intro.isActive and self._intro.phase == "deck_move") then
      local deckX, deckY = self:getDeckCenter()
      local drawCount = self._waveManager and self._waveManager:getDrawPileCount() or 0
      local stackCount = math.min(10, math.max(4, math.floor(math.max(4, drawCount) * 0.16)))
      self:drawDeckStackPrimitive(deckX, deckY, stackCount, 1.0)
    end
  end

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.wave.title"), 0, 8, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.wave.stage_line", {
    stage = tostring(self._waveManager and self._waveManager:getStageIndex() or 1),
    wave = tostring(self._waveManager and self._waveManager:getWaveIndex() or 1)
  }), 0, 46, Constants.BASE_WORLD_W, "center")

  if self._intro.isActive then
    self:drawIntroOverlay()
  end

  if self._upgradeResolveAnim then
    self:drawUpgradeResolveAnimation()
  end

  if self._isUpgradePending and self._isUpgradeOverlayVisible then
    self:drawUpgradeOverlay(mouseX, mouseY)
  elseif self._isUpgradePending and self._isUpgradeHiddenByEsc then
    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_DANGER)
    love.graphics.printf(t("single.wave.upgrade.status.reopen_required"), 0, Constants.BASE_WORLD_H * 0.5 - 42, Constants.BASE_WORLD_W, "center")
    self._reopenUpgradeButton:draw(mouseX, mouseY)
  end

  if self._isPauseOverlayVisible then
    self:drawPauseOverlay(mouseX, mouseY)
  end

  if self._isSettingsOverlayVisible then
    self:drawSettingsOverlay(mouseX, mouseY)
  end

  if self._isRunEnded then
    self:drawRunEndOverlay(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 694, Constants.BASE_WORLD_W, "center")
end

function SingleWaveScene:handleRelicScrollMousePressed(mouseX, mouseY, button)
  if button ~= 1 then
    return false
  end
  local metrics = self:getRelicScrollMetrics()
  if metrics.maxOffset <= 0 then
    return false
  end
  if pointInRect(mouseX, mouseY, metrics.handleRect) then
    self._isRelicScrollbarDragging = true
    self._relicDragStartY = mouseY
    self._relicDragStartOffset = self._relicScrollOffset
    return true
  end
  if pointInRect(mouseX, mouseY, metrics.viewport) then
    self._isRelicPanelDragging = true
    self._relicDragStartY = mouseY
    self._relicDragStartOffset = self._relicScrollOffset
    return true
  end
  return false
end

function SingleWaveScene:mousepressed(mouseX, mouseY, button)
  if self._upgradeResolveAnim then
    return
  end

  if self._isSettingsOverlayVisible then
    if button ~= 1 then
      return
    end
    if self._settingsModeWindowedButton:isHovered(mouseX, mouseY) then
      self._settingsModeWindowedButton:onClick()
      return
    end
    if self._settingsModeFullscreenButton:isHovered(mouseX, mouseY) then
      self._settingsModeFullscreenButton:onClick()
      return
    end
    if self._settingsLanguageKoButton:isHovered(mouseX, mouseY) then
      self._settingsLanguageKoButton:onClick()
      return
    end
    if self._settingsLanguageEnButton:isHovered(mouseX, mouseY) then
      self._settingsLanguageEnButton:onClick()
      return
    end
    if self._settingsSaveButton:isHovered(mouseX, mouseY) then
      self._settingsSaveButton:onClick()
      return
    end
    if self._settingsCancelButton:isHovered(mouseX, mouseY) then
      self._settingsCancelButton:onClick()
    end
    return
  end

  if self._isPauseOverlayVisible then
    if button ~= 1 then
      return
    end
    if self._pauseResumeButton:isHovered(mouseX, mouseY) then
      self._pauseResumeButton:onClick()
      return
    end
    if self._pauseLobbyButton:isHovered(mouseX, mouseY) then
      self._pauseLobbyButton:onClick()
      return
    end
    if self._pauseResetButton:isHovered(mouseX, mouseY) then
      self._pauseResetButton:onClick()
      return
    end
    if self._pauseSettingsButton:isHovered(mouseX, mouseY) then
      self._pauseSettingsButton:onClick()
    end
    return
  end

  if self._isRunEnded then
    if button ~= 1 then
      return
    end
    if self._pauseLobbyButton:isHovered(mouseX, mouseY) then
      self._pauseLobbyButton:onClick()
      return
    end
    if self._pauseResetButton:isHovered(mouseX, mouseY) then
      self._pauseResetButton:onClick()
    end
    return
  end

  if self._isUpgradePending and self._isUpgradeOverlayVisible then
    if button ~= 1 then
      return
    end
    for _, optionButton in ipairs(self._upgradeButtonList) do
      if optionButton:isHovered(mouseX, mouseY) then
        optionButton:onClick()
        return
      end
    end
    if self._confirmUpgradeButton:isHovered(mouseX, mouseY) then
      self._confirmUpgradeButton:onClick()
    end
    return
  end

  if self._isUpgradePending and self._isUpgradeHiddenByEsc then
    if button == 1 and self._reopenUpgradeButton:isHovered(mouseX, mouseY) then
      self._reopenUpgradeButton:onClick()
    end
    return
  end

  if self._intro.isActive then
    return
  end

  if self:handleRelicScrollMousePressed(mouseX, mouseY, button) then
    return
  end

  if self._core then
    self._core:mousepressed(mouseX, mouseY, button)
  end
end

function SingleWaveScene:mousereleased(mouseX, mouseY, button)
  if button == 1 then
    self._isRelicPanelDragging = false
    self._isRelicScrollbarDragging = false
  end
  if self._isPauseOverlayVisible or self._isUpgradeOverlayVisible or self._isSettingsOverlayVisible or self._intro.isActive or self._isRunEnded or self._upgradeResolveAnim then
    return
  end
  if self._core then
    self._core:mousereleased(mouseX, mouseY, button)
  end
end

function SingleWaveScene:mousemoved(mouseX, mouseY, dx, dy)
  if self._isRelicScrollbarDragging then
    local metrics = self:getRelicScrollMetrics()
    local handleTravel = math.max(1, metrics.viewport.h - metrics.handleRect.h)
    local offsetPerPixel = metrics.maxOffset / handleTravel
    self._relicScrollOffset = clamp(self._relicDragStartOffset + (mouseY - self._relicDragStartY) * offsetPerPixel, 0, metrics.maxOffset)
    return
  end
  if self._isRelicPanelDragging then
    self:scrollRelicList(-(mouseY - self._relicDragStartY))
    self._relicDragStartY = mouseY
    return
  end
  if self._isPauseOverlayVisible or self._isUpgradeOverlayVisible or self._isSettingsOverlayVisible or self._intro.isActive or self._isRunEnded or self._upgradeResolveAnim then
    return
  end
  if self._core then
    self._core:mousemoved(mouseX, mouseY, dx, dy)
  end
end

function SingleWaveScene:wheelmoved(_x, y)
  if self._intro.isActive then
    return
  end
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local metrics = self:getRelicScrollMetrics()
  if pointInRect(mouseX, mouseY, metrics.viewport) then
    self:scrollRelicList(-y * 30)
    return
  end
  if self._isPauseOverlayVisible or self._isUpgradeOverlayVisible or self._isSettingsOverlayVisible or self._intro.isActive or self._isRunEnded or self._upgradeResolveAnim then
    return
  end
  if self._core then
    self._core:wheelmoved(mouseX, mouseY, 0, y)
  end
end

function SingleWaveScene:keypressed(key)
  if self._upgradeResolveAnim then
    return
  end

  if self._isSettingsOverlayVisible then
    if key == "escape" then
      self:closeSettingsOverlay()
    end
    return
  end

  if key == "escape" then
    if self._isPauseOverlayVisible then
      self._isPauseOverlayVisible = false
      return
    end
    if self._isUpgradePending and self._isUpgradeOverlayVisible then
      self._isUpgradeOverlayVisible = false
      self._isUpgradeHiddenByEsc = true
      self:setStatus(t("single.wave.upgrade.status.reopen_required"), Constants.COLOR_DANGER)
      return
    end
    self._isPauseOverlayVisible = true
    return
  end

  if key == "u" and self._isUpgradePending and self._isUpgradeHiddenByEsc then
    self._isUpgradeOverlayVisible = true
    self._isUpgradeHiddenByEsc = false
    return
  end

  if self._isPauseOverlayVisible or self._isUpgradeOverlayVisible or self._isUpgradePending or self._intro.isActive or self._isRunEnded then
    return
  end
  if self._core and self._core:keypressed(key) then
    return
  end
end

function SingleWaveScene:onAppEvent(event)
  if self._core then
    self._core:onAppEvent(event)
  end
end

function SingleWaveScene:onSceneWillChange(event)
  if self._core then
    self._core:onSceneWillChange(event)
  end
end

function SingleWaveScene:exit()
  if self._core then
    self._core:exit()
  end
end

return SingleWaveScene
