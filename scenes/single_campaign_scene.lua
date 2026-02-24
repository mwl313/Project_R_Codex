--[[
파일명: single_campaign_scene.lua
모듈명: SingleCampaignScene

역할:
- 싱글 캠페인 진입점.
- 런 시작/카드 관리 분기를 제공한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local SingleProfileStore = require("single.single_profile_store")
local SingleDeckManager = require("single.single_deck_manager")
local SingleRunManager = require("single.single_run_manager")
local SingleRunState = require("single.single_run_state")

local SingleCampaignScene = {}
SingleCampaignScene.__index = SingleCampaignScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local REASON_I18N_KEY_BY_CODE = {
  invalid_deck = "single.reason.invalid_deck",
  unknown_card_id = "single.reason.unknown_card_id",
  duplicate_limit_exceeded = "single.reason.duplicate_limit_exceeded",
  owned_count_exceeded = "single.reason.owned_count_exceeded",
  deck_size_exceeded = "single.reason.deck_size_exceeded",
  deck_too_small = "single.reason.deck_too_small"
}

local function reasonToText(reasonCode)
  local code = tostring(reasonCode or "")
  local key = REASON_I18N_KEY_BY_CODE[code]
  if not key then
    return code
  end
  return t(key)
end

local function getDefaultDeck(profile)
  if type(profile) ~= "table" or type(profile.decks) ~= "table" then
    return nil
  end
  for _, deck in ipairs(profile.decks) do
    if type(deck) == "table" and tostring(deck.deckId or "") == "default" then
      return deck
    end
  end
  return profile.decks[1]
end

local function countOwnedCards(profile)
  local total = 0
  if type(profile) ~= "table" or type(profile.collection) ~= "table" or type(profile.collection.cards) ~= "table" then
    return total
  end
  for _, entry in pairs(profile.collection.cards) do
    if type(entry) == "table" and type(entry.ownedCount) == "number" and entry.ownedCount > 0 then
      total = total + 1
    end
  end
  return total
end

function SingleCampaignScene.new(app)
  local instance = {
    _app = app,
    _backScene = "play",
    _backButton = nil,
    _runButton = nil,
    _deckButton = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _profile = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleCampaignScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleCampaignScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)

  self._runButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280,
    label = t("single.campaign.button.run_start"),
    onClick = function()
      self:startRun()
    end
  })

  self._deckButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280 + Constants.BUTTON_H + Constants.BUTTON_GAP,
    label = t("single.campaign.button.deck_manage"),
    onClick = function()
      self._app:goScene("single_deck_manage", {
        backScene = "single_campaign",
        profile = self._profile
      }, Config.TRANSITION_FORWARD)
    end
  })
end

function SingleCampaignScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleCampaignScene:reloadProfile()
  local profile, loadErr = SingleProfileStore.load()
  self._profile = profile
  if loadErr then
    self:setStatus(t("single.campaign.status.profile_recovered"), Constants.COLOR_DANGER)
  else
    self:setStatus(t("single.campaign.status.profile_loaded"), Constants.COLOR_TEXT_SUB)
  end
end

function SingleCampaignScene:startRun()
  local deck = getDefaultDeck(self._profile)
  if not deck then
    self:setStatus(t("single.campaign.status.deck_missing"), Constants.COLOR_DANGER)
    return
  end

  local isValid, errList = SingleDeckManager.validateDeck(deck, self._profile.collection)
  if not isValid then
    self:setStatus(t("single.campaign.status.deck_invalid", {
      reason = reasonToText(errList and errList[1])
    }), Constants.COLOR_DANGER)
    return
  end

  local runState = SingleRunManager.newRun("default", {
    templateId = "template_a",
    stageIndex = 1
  })
  SingleRunState.ensureDefaults(runState, self._profile)
  self._app:goScene("single_map", {
    backScene = "single_campaign",
    profile = self._profile,
    runState = runState
  }, Config.TRANSITION_FORWARD)
end

function SingleCampaignScene:enter(params)
  self._backScene = (params and params.backScene) or "play"
  self:rebuildLocalizedUi()
  self:reloadProfile()
end

function SingleCampaignScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleCampaignScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local deck = getDefaultDeck(self._profile)
  local deckSize = deck and #deck.cards or 0
  local ownedCardCount = countOwnedCards(self._profile)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.campaign.title"), 0, 108, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.campaign.subtitle"), 0, 160, Constants.BASE_WORLD_W, "center")

  love.graphics.printf(t("single.campaign.summary", {
    deckSize = tostring(deckSize),
    ownedKinds = tostring(ownedCardCount)
  }), 0, 214, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._runButton:draw(mouseX, mouseY)
  self._deckButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleCampaignScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._runButton:isHovered(mouseX, mouseY) then
    self._runButton:onClick()
    return
  end
  if self._deckButton:isHovered(mouseX, mouseY) then
    self._deckButton:onClick()
  end
end

function SingleCampaignScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function SingleCampaignScene:onAppEvent(_event)
end

return SingleCampaignScene
