--[[
파일명: single_deck_clean_scene.lua
모듈명: SingleDeckCleanScene

역할:
- 덱 정리 노드에서 카드 1장을 무료로 제거한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local CardRegistry = require("single.card_registry")
local SingleRunState = require("single.single_run_state")
local SingleNodeFlow = require("single.single_node_flow")

local SingleDeckCleanScene = {}
SingleDeckCleanScene.__index = SingleDeckCleanScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function cardNameById(cardId)
  local card = CardRegistry.getCard(cardId)
  if card and type(card.nameKo) == "string" then
    return card.nameKo
  end
  return tostring(cardId or "")
end

function SingleDeckCleanScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _itemButtons = {},
    _listScroll = 0,
    _pendingAutoComplete = false,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleDeckCleanScene)
  return instance
end

function SingleDeckCleanScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleDeckCleanScene:getDeck()
  return SingleRunState.getRunDeck(self._runState, self._profile)
end

function SingleDeckCleanScene:getVisibleRowCount()
  return 8
end

function SingleDeckCleanScene:getMaxScroll()
  local deck = self:getDeck()
  return math.max(0, (deck and #deck.cards or 0) - self:getVisibleRowCount())
end

function SingleDeckCleanScene:scrollBy(delta)
  self._listScroll = math.max(0, math.min(self:getMaxScroll(), self._listScroll + delta))
  self:rebuildItemButtons()
end

function SingleDeckCleanScene:completeNode()
  SingleNodeFlow.completeNodeAndReturnMap(self._app, self._profile, self._runState)
end

function SingleDeckCleanScene:removeCard(deckIndex)
  local deck = self:getDeck()
  local removed = SingleRunState.removeCardFromRunDeck(deck, deckIndex)
  if not removed then
    self:setStatus(t("single.deck_clean.status.remove_fail"), Constants.COLOR_DANGER)
    return
  end
  self:setStatus(t("single.deck_clean.status.remove_ok", {
    card = cardNameById(removed)
  }), Constants.COLOR_TEXT_SUB)
  self:completeNode()
end

function SingleDeckCleanScene:rebuildItemButtons()
  self._itemButtons = {}
  local deck = self:getDeck()
  local cards = (deck and deck.cards) or {}
  local startIndex = 1 + self._listScroll
  local endIndex = math.min(#cards, startIndex + self:getVisibleRowCount() - 1)
  local startY = 236
  local rowGap = 54
  for index = startIndex, endIndex do
    local cardId = tostring(cards[index] or "")
    local targetDeckIndex = index
    local rowY = startY + (index - startIndex) * rowGap
    self._itemButtons[#self._itemButtons + 1] = {
      rowY = rowY,
      actionButton = Button.new({
        x = 908,
        y = rowY - 2,
        w = 160,
        h = 40,
        label = t("single.deck_clean.button.remove"),
        onClick = function()
          self:removeCard(targetDeckIndex)
        end
      }),
      label = string.format("%02d. %s", targetDeckIndex, cardNameById(cardId))
    }
  end
end

function SingleDeckCleanScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or {}
  self._listScroll = 0
  self._pendingAutoComplete = false
  SingleRunState.ensureDefaults(self._runState, self._profile)
  local deck = self:getDeck()
  if not deck or #deck.cards <= 0 then
    self:setStatus(t("single.deck_clean.status.deck_empty"), Constants.COLOR_DANGER)
    self._pendingAutoComplete = true
    return
  end
  self:rebuildItemButtons()
  self._lastLanguage = self._app:getLanguage()
  self:setStatus(t("single.deck_clean.status.ready"), Constants.COLOR_TEXT_SUB)
end

function SingleDeckCleanScene:update(_dt)
  if self._pendingAutoComplete then
    self._pendingAutoComplete = false
    self:completeNode()
    return
  end
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildItemButtons()
    self._lastLanguage = self._app:getLanguage()
  end
end

function SingleDeckCleanScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.deck_clean.title"), 0, 78, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.deck_clean.subtitle"), 0, 134, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  for _, row in ipairs(self._itemButtons) do
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(row.label, 208, row.rowY + 8)
    row.actionButton:draw(mouseX, mouseY)
  end

  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleDeckCleanScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  for _, row in ipairs(self._itemButtons) do
    if row.actionButton:isHovered(mouseX, mouseY) then
      row.actionButton:onClick()
      return
    end
  end
end

function SingleDeckCleanScene:wheelmoved(_x, y)
  if y > 0 then
    self:scrollBy(-1)
  elseif y < 0 then
    self:scrollBy(1)
  end
end

function SingleDeckCleanScene:keypressed(key)
  if key == "up" then
    self:scrollBy(-1)
    return
  end
  if key == "down" then
    self:scrollBy(1)
    return
  end
  if key == "escape" then
    return
  end
end

function SingleDeckCleanScene:onAppEvent(_event)
end

return SingleDeckCleanScene
