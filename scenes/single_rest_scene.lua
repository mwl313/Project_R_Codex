--[[
파일명: single_rest_scene.lua
모듈명: SingleRestScene

역할:
- 휴식 노드 동작(무료 강화/무료 제거)을 처리한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local SingleRunState = require("single.single_run_state")
local SingleNodeFlow = require("single.single_node_flow")
local CardRegistry = require("single.card_registry")

local SingleRestScene = {}
SingleRestScene.__index = SingleRestScene

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

function SingleRestScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _mode = "upgrade",
    _modeButtons = {},
    _itemButtons = {},
    _listScroll = 0,
    _pendingAutoComplete = false,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleRestScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleRestScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleRestScene:getDeck()
  return SingleRunState.getRunDeck(self._runState, self._profile)
end

function SingleRestScene:getVisibleRowCount()
  return 8
end

function SingleRestScene:getMaxScroll()
  local deck = self:getDeck()
  return math.max(0, (deck and #deck.cards or 0) - self:getVisibleRowCount())
end

function SingleRestScene:scrollBy(delta)
  self._listScroll = math.max(0, math.min(self:getMaxScroll(), self._listScroll + delta))
  self:rebuildItemButtons()
end

function SingleRestScene:completeNode()
  SingleNodeFlow.completeNodeAndReturnMap(self._app, self._profile, self._runState)
end

function SingleRestScene:applyUpgrade(cardId)
  local nextLevel = SingleRunState.addUpgradeLevel(self._runState, cardId, 1)
  self:setStatus(t("single.rest.status.upgrade_ok", {
    card = cardNameById(cardId),
    level = tostring(nextLevel)
  }), Constants.COLOR_TEXT_SUB)
  self:completeNode()
end

function SingleRestScene:applyRemove(deckIndex)
  local deck = self:getDeck()
  local removed = SingleRunState.removeCardFromRunDeck(deck, deckIndex)
  if not removed then
    self:setStatus(t("single.rest.status.remove_fail"), Constants.COLOR_DANGER)
    return
  end
  self:setStatus(t("single.rest.status.remove_ok", {
    card = cardNameById(removed)
  }), Constants.COLOR_TEXT_SUB)
  self:completeNode()
end

function SingleRestScene:rebuildModeButtons()
  self._modeButtons = {}
  local modeDefs = {
    { id = "upgrade", key = "single.rest.mode.upgrade" },
    { id = "remove", key = "single.rest.mode.remove" }
  }
  local startX = 362
  local gap = 18
  local buttonW = 270
  for index, modeDef in ipairs(modeDefs) do
    local modeId = modeDef.id
    self._modeButtons[#self._modeButtons + 1] = Button.new({
      x = startX + (index - 1) * (buttonW + gap),
      y = 170,
      w = buttonW,
      h = 44,
      label = t(modeDef.key),
      onClick = function()
        self._mode = modeId
        self._listScroll = 0
        self:rebuildItemButtons()
      end
    })
  end
end

function SingleRestScene:rebuildItemButtons()
  self._itemButtons = {}
  local deck = self:getDeck()
  local cards = (deck and deck.cards) or {}
  local startIndex = 1 + self._listScroll
  local endIndex = math.min(#cards, startIndex + self:getVisibleRowCount() - 1)
  local startY = 252
  local rowGap = 52
  for index = startIndex, endIndex do
    local cardId = tostring(cards[index] or "")
    local targetCardId = cardId
    local targetDeckIndex = index
    local rowY = startY + (index - startIndex) * rowGap
    local level = SingleRunState.getUpgradeLevel(self._runState, targetCardId)
    local actionLabel = (self._mode == "upgrade") and t("single.rest.button.upgrade") or t("single.rest.button.remove")
    self._itemButtons[#self._itemButtons + 1] = {
      cardId = targetCardId,
      deckIndex = targetDeckIndex,
      rowY = rowY,
      label = string.format("%02d. %s", targetDeckIndex, cardNameById(targetCardId)),
      detail = t("single.rest.row.level", { level = tostring(level) }),
      actionButton = Button.new({
        x = 910,
        y = rowY - 2,
        w = 150,
        h = 38,
        label = actionLabel,
        onClick = function()
          if self._mode == "upgrade" then
            self:applyUpgrade(targetCardId)
          else
            self:applyRemove(targetDeckIndex)
          end
        end
      })
    }
  end
end

function SingleRestScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self:rebuildModeButtons()
  self:rebuildItemButtons()
end

function SingleRestScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or {}
  self._mode = "upgrade"
  self._listScroll = 0
  self._pendingAutoComplete = false
  SingleRunState.ensureDefaults(self._runState, self._profile)
  local deck = self:getDeck()
  if not deck or #deck.cards <= 0 then
    self:setStatus(t("single.rest.status.deck_empty"), Constants.COLOR_DANGER)
    self._pendingAutoComplete = true
    return
  end
  self:rebuildLocalizedUi()
  self:setStatus(t("single.rest.status.ready"), Constants.COLOR_TEXT_SUB)
end

function SingleRestScene:update(_dt)
  if self._pendingAutoComplete then
    self._pendingAutoComplete = false
    self:completeNode()
    return
  end
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleRestScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.rest.title"), 0, 74, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.rest.subtitle"), 0, 126, Constants.BASE_WORLD_W, "center")

  for index, modeButton in ipairs(self._modeButtons) do
    local isCurrent = (index == 1 and self._mode == "upgrade") or (index == 2 and self._mode == "remove")
    modeButton.isPressed = isCurrent
    modeButton:draw(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  for _, row in ipairs(self._itemButtons) do
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(row.label, 206, row.rowY)
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(row.detail, 206, row.rowY + 22)
    row.actionButton:draw(mouseX, mouseY)
  end

  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleRestScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  for _, modeButton in ipairs(self._modeButtons) do
    if modeButton:isHovered(mouseX, mouseY) then
      modeButton:onClick()
      return
    end
  end
  for _, row in ipairs(self._itemButtons) do
    if row.actionButton:isHovered(mouseX, mouseY) then
      row.actionButton:onClick()
      return
    end
  end
end

function SingleRestScene:wheelmoved(_x, y)
  if y > 0 then
    self:scrollBy(-1)
  elseif y < 0 then
    self:scrollBy(1)
  end
end

function SingleRestScene:keypressed(key)
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

function SingleRestScene:onAppEvent(_event)
end

return SingleRestScene
