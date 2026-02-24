--[[
파일명: single_shop_scene.lua
모듈명: SingleShopScene

역할:
- 상점 노드 동작을 처리한다.
- 카드 구매/강화/제거 중 1회 행동 후 맵으로 복귀한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local SingleRunState = require("single.single_run_state")
local SingleEconomy = require("single.single_economy")
local CardRegistry = require("single.card_registry")
local RewardPicker = require("single.reward_picker")
local SingleDeckManager = require("single.single_deck_manager")
local SingleDiscardOverlay = require("overlays.single_discard_overlay")
local SingleNodeFlow = require("single.single_node_flow")

local SingleShopScene = {}
SingleShopScene.__index = SingleShopScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function reasonToText(reasonCode)
  local reasonKeyByCode = {
    invalid_deck = "single.reason.invalid_deck",
    unknown_card_id = "single.reason.unknown_card_id",
    duplicate_limit = "single.reason.duplicate_limit",
    deck_full = "single.reason.deck_full"
  }
  local key = reasonKeyByCode[tostring(reasonCode or "")]
  if not key then
    return tostring(reasonCode or "unknown")
  end
  return t(key)
end

local function cardNameById(cardId)
  local card = CardRegistry.getCard(cardId)
  if card and type(card.nameKo) == "string" then
    return card.nameKo
  end
  return tostring(cardId or "")
end

function SingleShopScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _nodeType = "shop",
    _nodeId = "",
    _stageIndex = 1,
    _prices = nil,
    _mode = "buy",
    _modeButtons = {},
    _itemButtons = {},
    _leaveButton = nil,
    _offerCardIdList = {},
    _listScroll = 0,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage(),
    _discardOverlay = nil
  }
  setmetatable(instance, SingleShopScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleShopScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleShopScene:getRunDeck()
  return SingleRunState.getRunDeck(self._runState, self._profile)
end

function SingleShopScene:getVisibleRowCount()
  return 7
end

function SingleShopScene:getMaxScroll()
  local deck = self:getRunDeck()
  local total = (deck and #deck.cards) or 0
  return math.max(0, total - self:getVisibleRowCount())
end

function SingleShopScene:scrollBy(delta)
  self._listScroll = math.max(0, math.min(self:getMaxScroll(), self._listScroll + delta))
  self:rebuildItemButtons()
end

function SingleShopScene:completeNode()
  SingleNodeFlow.completeNodeAndReturnMap(self._app, self._profile, self._runState)
end

function SingleShopScene:openForcedDiscardOverlay()
  local deck = self:getRunDeck()
  if not deck then
    self:completeNode()
    return
  end
  self._discardOverlay = SingleDiscardOverlay.new({
    titleText = t("single.discard_overlay.title"),
    messageText = t("single.discard_overlay.message", {
      maxSize = tostring(SingleDeckManager.MAX_DECK_SIZE)
    }),
    maxDeckSize = SingleDeckManager.MAX_DECK_SIZE,
    deckCards = deck.cards,
    resolveCardName = cardNameById,
    onDiscard = function(discardIndex)
      local removed = SingleRunState.removeCardFromRunDeck(deck, discardIndex)
      if not removed then
        return false, t("single.discard_overlay.status.discard_failed")
      end
      self._discardOverlay = nil
      self:completeNode()
      return true
    end
  })
end

function SingleShopScene:ensureDeckLimitOrComplete()
  local deck = self:getRunDeck()
  if not deck then
    self:completeNode()
    return
  end
  if #deck.cards > SingleDeckManager.MAX_DECK_SIZE then
    self:openForcedDiscardOverlay()
    return
  end
  self:completeNode()
end

function SingleShopScene:rollShopOffers()
  self._offerCardIdList = RewardPicker.pick3({
    nodeType = "shop",
    stageIndex = self._stageIndex,
    isBoss = false,
    rngSeed = (tonumber(self._runState and self._runState.rngSeed) or os.time()) + 3001
  })
end

function SingleShopScene:tryBuy(cardId)
  local card = CardRegistry.getCard(cardId)
  if not card then
    self:setStatus(t("single.shop.status.buy_fail", {
      reason = reasonToText("unknown_card_id")
    }), Constants.COLOR_DANGER)
    return
  end

  local price = SingleEconomy.getBuyCardPrice(card.rarity)
  if not SingleRunState.spendGold(self._runState, price) then
    self:setStatus(t("single.shop.status.not_enough_gold"), Constants.COLOR_DANGER)
    return
  end

  local deck = self:getRunDeck()
  local addOk, addReason = SingleRunState.addCardToRunDeck(deck, cardId, {
    allowOverflow = true
  })
  if not addOk then
    SingleRunState.addGold(self._runState, price)
    self:setStatus(t("single.shop.status.buy_fail", {
      reason = reasonToText(addReason)
    }), Constants.COLOR_DANGER)
    return
  end

  self:setStatus(t("single.shop.status.buy_ok", {
    card = card.nameKo,
    gold = tostring(math.max(0, math.floor(self._runState.gold or 0)))
  }), Constants.COLOR_TEXT_SUB)
  self:ensureDeckLimitOrComplete()
end

function SingleShopScene:tryUpgrade(cardId)
  local price = self._prices.upgrade
  if not SingleRunState.spendGold(self._runState, price) then
    self:setStatus(t("single.shop.status.not_enough_gold"), Constants.COLOR_DANGER)
    return
  end
  local nextLevel = SingleRunState.addUpgradeLevel(self._runState, cardId, 1)
  self:setStatus(t("single.shop.status.upgrade_ok", {
    card = cardNameById(cardId),
    level = tostring(nextLevel)
  }), Constants.COLOR_TEXT_SUB)
  self:completeNode()
end

function SingleShopScene:tryRemove(deckIndex)
  local price = self._prices.remove
  if not SingleRunState.spendGold(self._runState, price) then
    self:setStatus(t("single.shop.status.not_enough_gold"), Constants.COLOR_DANGER)
    return
  end
  local deck = self:getRunDeck()
  local removed = SingleRunState.removeCardFromRunDeck(deck, deckIndex)
  if not removed then
    SingleRunState.addGold(self._runState, price)
    self:setStatus(t("single.shop.status.remove_fail"), Constants.COLOR_DANGER)
    return
  end
  self:setStatus(t("single.shop.status.remove_ok", {
    card = cardNameById(removed)
  }), Constants.COLOR_TEXT_SUB)
  self:completeNode()
end

function SingleShopScene:rebuildModeButtons()
  local startX = 244
  local gap = 16
  local buttonW = 250
  local buttonY = 162
  local modeDefList = {
    { id = "buy", key = "single.shop.mode.buy" },
    { id = "upgrade", key = "single.shop.mode.upgrade" },
    { id = "remove", key = "single.shop.mode.remove" }
  }

  self._modeButtons = {}
  for index, modeDef in ipairs(modeDefList) do
    local modeId = modeDef.id
    self._modeButtons[#self._modeButtons + 1] = Button.new({
      x = startX + (index - 1) * (buttonW + gap),
      y = buttonY,
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

function SingleShopScene:rebuildItemButtons()
  self._itemButtons = {}
  local listStartY = 246
  local rowGap = 52

  if self._mode == "buy" then
    for index, cardId in ipairs(self._offerCardIdList) do
      local targetCardId = cardId
      local card = CardRegistry.getCard(cardId)
      local rarity = card and card.rarity or "COMMON"
      local price = SingleEconomy.getBuyCardPrice(rarity)
      self._itemButtons[#self._itemButtons + 1] = {
        cardId = targetCardId,
        rowY = listStartY + (index - 1) * rowGap,
        label = string.format("%s (%dG)", cardNameById(targetCardId), price),
        detail = (card and card.descKo) or "",
        actionButton = Button.new({
          x = 898,
          y = listStartY + (index - 1) * rowGap - 2,
          w = 180,
          h = 38,
          label = t("single.shop.button.buy"),
          onClick = function()
            self:tryBuy(targetCardId)
          end
        }),
        action = function()
          self:tryBuy(targetCardId)
        end
      }
    end
    return
  end

  local deck = self:getRunDeck()
  local cards = (deck and deck.cards) or {}
  local startIndex = 1 + self._listScroll
  local endIndex = math.min(#cards, startIndex + self:getVisibleRowCount() - 1)
  for index = startIndex, endIndex do
    local cardId = tostring(cards[index] or "")
    local targetCardId = cardId
    local targetDeckIndex = index
    local rowY = listStartY + (index - startIndex) * rowGap
    local upgradeLevel = SingleRunState.getUpgradeLevel(self._runState, targetCardId)
    local detailText = t("single.shop.row.level", {
      level = tostring(upgradeLevel)
    })
    local actionLabel = self._mode == "upgrade"
      and t("single.shop.button.buy_upgrade", { price = tostring(self._prices.upgrade) })
      or t("single.shop.button.buy_remove", { price = tostring(self._prices.remove) })

    self._itemButtons[#self._itemButtons + 1] = {
      cardId = targetCardId,
      deckIndex = targetDeckIndex,
      rowY = rowY,
      label = string.format("%02d. %s", targetDeckIndex, cardNameById(targetCardId)),
      detail = detailText,
      actionLabel = actionLabel,
      actionButton = Button.new({
        x = 898,
        y = rowY - 2,
        w = 180,
        h = 38,
        label = actionLabel,
        onClick = function()
          if self._mode == "upgrade" then
            self:tryUpgrade(targetCardId)
          else
            self:tryRemove(targetDeckIndex)
          end
        end
      }),
      action = function()
        if self._mode == "upgrade" then
          self:tryUpgrade(targetCardId)
        else
          self:tryRemove(targetDeckIndex)
        end
      end
    }
  end
end

function SingleShopScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._leaveButton = Button.new({
    x = Constants.BASE_WORLD_W - 190,
    y = 666,
    w = 150,
    h = 40,
    label = t("single.shop.button.leave"),
    onClick = function()
      self:completeNode()
    end
  })
  self:rebuildModeButtons()
  self:rebuildItemButtons()
end

function SingleShopScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or {}
  self._nodeType = tostring((params and params.nodeType) or "shop")
  self._nodeId = tostring((params and params.nodeId) or "")
  self._stageIndex = math.max(1, math.floor(tonumber(params and params.stageIndex) or 1))

  SingleRunState.ensureDefaults(self._runState, self._profile)
  self._prices = SingleEconomy.getShopPrices()
  self._mode = "buy"
  self._listScroll = 0
  self._discardOverlay = nil
  self:rollShopOffers()
  self:rebuildLocalizedUi()
  self:setStatus(t("single.shop.status.ready"), Constants.COLOR_TEXT_SUB)
end

function SingleShopScene:update(dt)
  if self._discardOverlay then
    self._discardOverlay:update(dt)
  end
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleShopScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.shop.title"), 0, 66, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.shop.gold_line", {
    gold = tostring(math.max(0, math.floor(tonumber(self._runState.gold) or 0)))
  }), 0, 116, Constants.BASE_WORLD_W, "center")

  for index, button in ipairs(self._modeButtons) do
    local isCurrent = (index == 1 and self._mode == "buy")
      or (index == 2 and self._mode == "upgrade")
      or (index == 3 and self._mode == "remove")
    button.isPressed = isCurrent
    button:draw(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  for _, row in ipairs(self._itemButtons) do
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.print(row.label, 206, row.rowY)
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.print(row.detail, 206, row.rowY + 22)
    if row.actionButton then
      row.actionButton:draw(mouseX, mouseY)
    end
  end

  self._leaveButton:draw(mouseX, mouseY)

  if self._discardOverlay then
    self._discardOverlay:draw(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleShopScene:mousepressed(mouseX, mouseY, button)
  if self._discardOverlay and self._discardOverlay:mousepressed(mouseX, mouseY, button) then
    return
  end
  if button ~= 1 then
    return
  end

  if self._leaveButton:isHovered(mouseX, mouseY) then
    self._leaveButton:onClick()
    return
  end

  for _, modeButton in ipairs(self._modeButtons) do
    if modeButton:isHovered(mouseX, mouseY) then
      modeButton:onClick()
      return
    end
  end

  for _, row in ipairs(self._itemButtons) do
    if row.actionButton and row.actionButton:isHovered(mouseX, mouseY) then
      row.actionButton:onClick()
      return
    end
  end
end

function SingleShopScene:wheelmoved(_x, y)
  if self._discardOverlay then
    self._discardOverlay:wheelmoved(_x, y)
    return
  end
  if self._mode == "buy" then
    return
  end
  if y > 0 then
    self:scrollBy(-1)
  elseif y < 0 then
    self:scrollBy(1)
  end
end

function SingleShopScene:keypressed(key)
  if self._discardOverlay and self._discardOverlay:keypressed(key) then
    return
  end
  if key == "up" then
    self:scrollBy(-1)
    return
  end
  if key == "down" then
    self:scrollBy(1)
    return
  end
  if key == "escape" then
    -- 강제 노드 처리 구간이므로 Esc로는 닫지 않는다.
    return
  end
end

function SingleShopScene:onAppEvent(_event)
end

return SingleShopScene
