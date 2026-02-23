--[[
파일명: single_reward_scene.lua
모듈명: SingleRewardScene

역할:
- 전투 승리 후 카드 보상 3선택 UI를 제공한다.
- 선택 카드 컬렉션 반영 + 덱 추가 + 덱 오버플로우 시 강제 버리기 분기를 처리한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local CardRegistry = require("single.card_registry")
local SingleProfileStore = require("single.single_profile_store")
local SingleDeckManager = require("single.single_deck_manager")
local SingleRunManager = require("single.single_run_manager")

local SingleRewardScene = {}
SingleRewardScene.__index = SingleRewardScene

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

local function createRng()
  if love and love.math and love.math.newRandomGenerator then
    return love.math.newRandomGenerator(os.time())
  end
  math.randomseed(os.time())
  return nil
end

function SingleRewardScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _isBoss = false,
    _choiceList = {},
    _choiceButtonList = {},
    _selectedIndex = nil,
    _confirmButton = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleRewardScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleRewardScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleRewardScene:rebuildChoiceButtons()
  self._choiceButtonList = {}
  local startX = (Constants.BASE_WORLD_W - (3 * 250 + 2 * 26)) * 0.5
  for index = 1, 3 do
    local card = self._choiceList[index]
    self._choiceButtonList[index] = Button.new({
      x = startX + (index - 1) * 276,
      y = 258,
      w = 250,
      h = 220,
      label = card and card.nameKo or "-",
      onClick = function()
        self._selectedIndex = index
      end
    })
  end
end

function SingleRewardScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._confirmButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 528,
    label = t("single.reward.button.confirm"),
    onClick = function()
      self:confirmReward()
    end
  })
  self:rebuildChoiceButtons()
end

function SingleRewardScene:continueAfterReward()
  local nextNode = SingleRunManager.advanceNode(self._runState)
  if nextNode then
    self._app:goScene("single_map", {
      backScene = "single_campaign",
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_FORWARD)
    return
  end

  self._runState.finished = true
  self._runState.isVictory = true
  self._app:goScene("single_result", {
    profile = self._profile,
    runState = self._runState,
    result = "win"
  }, Config.TRANSITION_FORWARD)
end

function SingleRewardScene:confirmReward()
  if not self._selectedIndex then
    self:setStatus(t("single.reward.status.select_required"), Constants.COLOR_DANGER)
    return
  end
  local selectedCard = self._choiceList[self._selectedIndex]
  if not selectedCard then
    self:setStatus(t("single.reward.status.select_required"), Constants.COLOR_DANGER)
    return
  end

  local collectionCards = self._profile and self._profile.collection and self._profile.collection.cards
  if type(collectionCards) ~= "table" then
    self:setStatus(t("single.reward.status.profile_invalid"), Constants.COLOR_DANGER)
    return
  end

  local cardId = selectedCard.id
  collectionCards[cardId] = collectionCards[cardId] or { ownedCount = 0 }
  local previousOwned = tonumber(collectionCards[cardId].ownedCount) or 0
  local nextOwned = math.max(0, math.min(3, math.floor(previousOwned + 1)))
  collectionCards[cardId].ownedCount = nextOwned

  local deck = getDefaultDeck(self._profile)
  if not deck then
    self:setStatus(t("single.reward.status.deck_missing"), Constants.COLOR_DANGER)
    return
  end

  local addOk = SingleDeckManager.addToDeck(deck, cardId, self._profile.collection, {
    allowOverflowSize = true
  })
  if not addOk then
    self:setStatus(t("single.reward.status.add_skipped"), Constants.COLOR_TEXT_SUB)
  else
    self:setStatus(t("single.reward.status.picked", {
      card = selectedCard.nameKo
    }), Constants.COLOR_TEXT_SUB)
  end

  local saveOk, saveErr = SingleProfileStore.save(self._profile)
  if not saveOk then
    self:setStatus(t("single.reward.status.save_failed", {
      error = tostring(saveErr or "unknown")
    }), Constants.COLOR_DANGER)
    return
  end

  if #deck.cards > SingleDeckManager.MAX_DECK_SIZE then
    local nextNode = SingleRunManager.advanceNode(self._runState)
    local nextSceneName = "single_result"
    local nextParams = {
      profile = self._profile,
      runState = self._runState,
      result = "win"
    }
    if nextNode then
      nextSceneName = "single_map"
      nextParams = {
        backScene = "single_campaign",
        profile = self._profile,
        runState = self._runState
      }
    else
      self._runState.finished = true
      self._runState.isVictory = true
    end

    self._app:goScene("single_discard", {
      profile = self._profile,
      runState = self._runState,
      nextSceneName = nextSceneName,
      nextSceneParams = nextParams
    }, Config.TRANSITION_FORWARD)
    return
  end

  self:continueAfterReward()
end

function SingleRewardScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil
  self._isBoss = params and params.isBoss == true or false
  self._choiceList = CardRegistry.getRewardChoices(self._isBoss, createRng())
  self._selectedIndex = nil
  self:rebuildLocalizedUi()
  self:setStatus(t("single.reward.status.choose_one"), Constants.COLOR_TEXT_SUB)
end

function SingleRewardScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleRewardScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.reward.title"), 0, 88, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.reward.subtitle"), 0, 142, Constants.BASE_WORLD_W, "center")

  for index, button in ipairs(self._choiceButtonList) do
    local card = self._choiceList[index]
    button.isPressed = self._selectedIndex == index
    button:draw(mouseX, mouseY)
    if card then
      love.graphics.setFont(FontManager.getFont("small"))
      love.graphics.setColor(Constants.COLOR_TEXT_SUB)
      love.graphics.printf(card.descKo, button.x + 14, button.y + 150, button.w - 28, "center")
    end
  end

  self._confirmButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleRewardScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  for index, choiceButton in ipairs(self._choiceButtonList) do
    if choiceButton:isHovered(mouseX, mouseY) then
      choiceButton:onClick()
      self:setStatus(t("single.reward.status.selected", {
        index = tostring(index)
      }), Constants.COLOR_TEXT_SUB)
      return
    end
  end

  if self._confirmButton:isHovered(mouseX, mouseY) then
    self._confirmButton:onClick()
  end
end

function SingleRewardScene:keypressed(key)
  if key == "escape" then
    self._app:goScene("single_map", {
      backScene = "single_campaign",
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_BACK)
  end
end

function SingleRewardScene:onAppEvent(_event)
end

return SingleRewardScene
