--[[
파일명: single_discard_scene.lua
모듈명: SingleDiscardScene

역할:
- 덱이 15장을 초과했을 때 카드 1장 강제 제거를 처리한다.

주의:
- Deprecated: 강제 버리기 UX는 overlays/single_discard_overlay.lua로 대체되었다.
- 하위 호환/안전 롤백 목적의 보존 파일이며, 신규 흐름에서는 이 씬으로 전환하지 않는다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local SingleProfileStore = require("single.single_profile_store")
local SingleDeckManager = require("single.single_deck_manager")
local CardRegistry = require("single.card_registry")

local SingleDiscardScene = {}
SingleDiscardScene.__index = SingleDiscardScene

local function t(key, vars)
  return I18n.t(key, vars)
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

local function cardNameById(cardId)
  local card = CardRegistry.getCard(cardId)
  if card then
    return card.nameKo
  end
  return tostring(cardId)
end

function SingleDiscardScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _nextSceneName = "single_map",
    _nextSceneParams = nil,
    _selectedIndex = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _backButton = nil,
    _confirmButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleDiscardScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleDiscardScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleDiscardScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene("single_campaign", {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end)

  self._confirmButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 584,
    label = t("single.discard.button.confirm"),
    onClick = function()
      self:confirmDiscard()
    end
  })
end

function SingleDiscardScene:confirmDiscard()
  local deck = getDefaultDeck(self._profile)
  if not deck then
    self:setStatus(t("single.discard.status.deck_missing"), Constants.COLOR_DANGER)
    return
  end
  if not self._selectedIndex then
    self:setStatus(t("single.discard.status.select_required"), Constants.COLOR_DANGER)
    return
  end

  local removed = SingleDeckManager.removeFromDeck(deck, self._selectedIndex)
  if not removed then
    self:setStatus(t("single.discard.status.remove_fail"), Constants.COLOR_DANGER)
    return
  end

  local saveOk, saveErr = SingleProfileStore.save(self._profile)
  if not saveOk then
    self:setStatus(t("single.discard.status.save_failed", {
      error = tostring(saveErr or "unknown")
    }), Constants.COLOR_DANGER)
    return
  end

  self._app:goScene(self._nextSceneName, self._nextSceneParams, Config.TRANSITION_FORWARD)
end

function SingleDiscardScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil
  self._nextSceneName = params and params.nextSceneName or "single_map"
  self._nextSceneParams = params and params.nextSceneParams or {
    profile = self._profile,
    runState = self._runState
  }
  self._selectedIndex = nil
  self:rebuildLocalizedUi()
  self:setStatus(t("single.discard.status.guide"), Constants.COLOR_TEXT_SUB)
end

function SingleDiscardScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleDiscardScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local deck = getDefaultDeck(self._profile)
  local cards = deck and deck.cards or {}

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.discard.title"), 0, 78, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.discard.subtitle", {
    deckSize = tostring(#cards),
    maxSize = tostring(SingleDeckManager.MAX_DECK_SIZE)
  }), 0, 130, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  local startY = 190
  for index, cardId in ipairs(cards) do
    local y = startY + (index - 1) * 26
    local selected = self._selectedIndex == index
    local hovered = mouseX >= 250 and mouseX <= 1030 and mouseY >= y - 2 and mouseY <= y + 20
    local alpha = selected and 0.28 or (hovered and 0.16 or 0.08)
    love.graphics.setColor(0.22, 0.31, 0.52, alpha)
    love.graphics.rectangle("fill", 244, y - 2, 792, 22, 4, 4)

    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(string.format("%02d. %s", index, cardNameById(cardId)), 260, y)
  end

  self._backButton:draw(mouseX, mouseY)
  self._confirmButton:draw(mouseX, mouseY)

  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleDiscardScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end

  local deck = getDefaultDeck(self._profile)
  local cards = deck and deck.cards or {}
  local startY = 190
  for index = 1, #cards do
    local y = startY + (index - 1) * 26
    if mouseX >= 250 and mouseX <= 1030 and mouseY >= y - 2 and mouseY <= y + 20 then
      self._selectedIndex = index
      self:setStatus(t("single.discard.status.selected", {
        card = cardNameById(cards[index])
      }), Constants.COLOR_TEXT_SUB)
      return
    end
  end

  if self._confirmButton:isHovered(mouseX, mouseY) then
    self._confirmButton:onClick()
  end
end

function SingleDiscardScene:keypressed(key)
  if key == "escape" then
    self._app:goScene("single_campaign", {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end
end

function SingleDiscardScene:onAppEvent(_event)
end

return SingleDiscardScene
