--[[
파일명: single_deck_manage_scene.lua
모듈명: SingleDeckManageScene

역할:
- 싱글 컬렉션/기본 덱 편집 UI를 제공한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local CardRegistry = require("single.card_registry")
local SingleProfileStore = require("single.single_profile_store")
local SingleDeckManager = require("single.single_deck_manager")

local SingleDeckManageScene = {}
SingleDeckManageScene.__index = SingleDeckManageScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local REASON_I18N_KEY_BY_CODE = {
  invalid_deck = "single.reason.invalid_deck",
  unknown_card_id = "single.reason.unknown_card_id",
  duplicate_limit = "single.reason.duplicate_limit",
  duplicate_limit_exceeded = "single.reason.duplicate_limit_exceeded",
  owned_count = "single.reason.owned_count",
  owned_count_exceeded = "single.reason.owned_count_exceeded",
  deck_full = "single.reason.deck_full",
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

local function getOwnedCount(profile, cardId)
  local entry = profile
    and profile.collection
    and profile.collection.cards
    and profile.collection.cards[cardId]
  if type(entry) ~= "table" or type(entry.ownedCount) ~= "number" then
    return 0
  end
  return math.max(0, math.floor(entry.ownedCount))
end

local function removeOneCardById(deck, cardId)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return false
  end
  for index, value in ipairs(deck.cards) do
    if value == cardId then
      table.remove(deck.cards, index)
      return true
    end
  end
  return false
end

function SingleDeckManageScene.new(app)
  local instance = {
    _app = app,
    _backScene = "single_campaign",
    _profile = nil,
    _collectionList = CardRegistry.listAll(),
    _page = 1,
    _pageSize = 6,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage(),
    _backButton = nil,
    _prevPageButton = nil,
    _nextPageButton = nil,
    _rowButtonEntries = {}
  }
  setmetatable(instance, SingleDeckManageScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleDeckManageScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleDeckManageScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end)

  self._prevPageButton = Button.new({
    x = 246,
    y = 630,
    w = 140,
    h = 42,
    label = t("single.deck.button.prev"),
    onClick = function()
      self:changePage(-1)
    end
  })

  self._nextPageButton = Button.new({
    x = Constants.BASE_WORLD_W - 246 - 140,
    y = 630,
    w = 140,
    h = 42,
    label = t("single.deck.button.next"),
    onClick = function()
      self:changePage(1)
    end
  })

  self:rebuildRowButtons()
end

function SingleDeckManageScene:reloadProfile(profileFromParams)
  if type(profileFromParams) == "table" then
    self._profile = SingleProfileStore.validateAndFix(profileFromParams)
    return
  end
  local profile, loadErr = SingleProfileStore.load()
  self._profile = profile
  if loadErr then
    self:setStatus(t("single.deck.status.profile_recovered"), Constants.COLOR_DANGER)
  end
end

function SingleDeckManageScene:changePage(delta)
  local maxPage = math.max(1, math.ceil(#self._collectionList / self._pageSize))
  self._page = math.max(1, math.min(maxPage, self._page + delta))
  self:rebuildRowButtons()
end

function SingleDeckManageScene:saveProfileOrWarn()
  local ok, err = SingleProfileStore.save(self._profile)
  if not ok then
    self:setStatus(t("single.deck.status.save_failed", {
      error = tostring(err or "unknown")
    }), Constants.COLOR_DANGER)
    return false
  end
  return true
end

function SingleDeckManageScene:handleAddCard(cardId)
  local deck = getDefaultDeck(self._profile)
  if not deck then
    self:setStatus(t("single.deck.status.deck_missing"), Constants.COLOR_DANGER)
    return
  end

  local ok, reason = SingleDeckManager.addToDeck(deck, cardId, self._profile.collection)
  if not ok then
    self:setStatus(t("single.deck.status.add_fail", {
      reason = reasonToText(reason)
    }), Constants.COLOR_DANGER)
    return
  end

  if self:saveProfileOrWarn() then
    self:setStatus(t("single.deck.status.add_ok"), Constants.COLOR_TEXT_SUB)
  end
  self:rebuildRowButtons()
end

function SingleDeckManageScene:handleRemoveCard(cardId)
  local deck = getDefaultDeck(self._profile)
  if not deck then
    self:setStatus(t("single.deck.status.deck_missing"), Constants.COLOR_DANGER)
    return
  end

  if not removeOneCardById(deck, cardId) then
    self:setStatus(t("single.deck.status.remove_fail"), Constants.COLOR_DANGER)
    return
  end

  if self:saveProfileOrWarn() then
    self:setStatus(t("single.deck.status.remove_ok"), Constants.COLOR_TEXT_SUB)
  end
  self:rebuildRowButtons()
end

function SingleDeckManageScene:rebuildRowButtons()
  self._rowButtonEntries = {}
  local deck = getDefaultDeck(self._profile)
  local startIndex = (self._page - 1) * self._pageSize + 1
  local endIndex = math.min(#self._collectionList, startIndex + self._pageSize - 1)
  local baseY = 212

  for index = startIndex, endIndex do
    local row = index - startIndex
    local card = self._collectionList[index]
    local cardY = baseY + row * 64

    self._rowButtonEntries[#self._rowButtonEntries + 1] = {
      card = card,
      y = cardY,
      addButton = Button.new({
        x = 874,
        y = cardY - 4,
        w = 110,
        h = 34,
        label = t("single.deck.button.add"),
        onClick = function()
          self:handleAddCard(card.id)
        end
      }),
      removeButton = Button.new({
        x = 996,
        y = cardY - 4,
        w = 110,
        h = 34,
        label = t("single.deck.button.remove"),
        onClick = function()
          self:handleRemoveCard(card.id)
        end
      }),
      inDeck = deck and SingleDeckManager.countInDeck(deck, card.id) or 0,
      owned = getOwnedCount(self._profile, card.id)
    }
  end
end

function SingleDeckManageScene:enter(params)
  self._backScene = (params and params.backScene) or "single_campaign"
  self:reloadProfile(params and params.profile)
  self._page = 1
  self:rebuildLocalizedUi()
  self:setStatus(t("single.deck.status.loaded"), Constants.COLOR_TEXT_SUB)
end

function SingleDeckManageScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleDeckManageScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local deck = getDefaultDeck(self._profile)
  local deckSize = deck and #deck.cards or 0
  local maxPage = math.max(1, math.ceil(#self._collectionList / self._pageSize))

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.deck.title"), 0, 74, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.deck.summary", {
    deckSize = tostring(deckSize),
    maxSize = tostring(SingleDeckManager.MAX_DECK_SIZE),
    page = tostring(self._page),
    maxPage = tostring(maxPage)
  }), 0, 126, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  for _, rowEntry in ipairs(self._rowButtonEntries) do
    local inDeck = deck and SingleDeckManager.countInDeck(deck, rowEntry.card.id) or 0
    local owned = getOwnedCount(self._profile, rowEntry.card.id)
    local ownedText = string.format("%d/3", owned)
    if owned >= 3 then
      ownedText = t("single.deck.owned_max")
    end

    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(rowEntry.card.nameKo, 184, rowEntry.y)
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(t("single.deck.row_owned", { owned = ownedText }), 430, rowEntry.y)
    love.graphics.print(t("single.deck.row_in_deck", { count = tostring(inDeck) }), 620, rowEntry.y)

    rowEntry.addButton:draw(mouseX, mouseY)
    rowEntry.removeButton:draw(mouseX, mouseY)
  end

  self._backButton:draw(mouseX, mouseY)
  self._prevPageButton:draw(mouseX, mouseY)
  self._nextPageButton:draw(mouseX, mouseY)

  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleDeckManageScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._prevPageButton:isHovered(mouseX, mouseY) then
    self._prevPageButton:onClick()
    return
  end
  if self._nextPageButton:isHovered(mouseX, mouseY) then
    self._nextPageButton:onClick()
    return
  end
  for _, rowEntry in ipairs(self._rowButtonEntries) do
    if rowEntry.addButton:isHovered(mouseX, mouseY) then
      rowEntry.addButton:onClick()
      return
    end
    if rowEntry.removeButton:isHovered(mouseX, mouseY) then
      rowEntry.removeButton:onClick()
      return
    end
  end
end

function SingleDeckManageScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, {
      profile = self._profile
    }, Config.TRANSITION_BACK)
    return
  end
  if key == "left" then
    self:changePage(-1)
    return
  end
  if key == "right" then
    self:changePage(1)
  end
end

function SingleDeckManageScene:onAppEvent(_event)
end

return SingleDeckManageScene
