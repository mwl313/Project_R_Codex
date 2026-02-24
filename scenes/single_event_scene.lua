--[[
파일명: single_event_scene.lua
모듈명: SingleEventScene

역할:
- 이벤트 노드에서 2지선다 결과를 적용한다.
- 결과는 런 상태(runState)만 변경하며, 필요 시 전투로 분기한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local CardRules = require("shared.card_rules")
local CardRegistry = require("single.card_registry")
local SingleRunState = require("single.single_run_state")
local SingleNodeFlow = require("single.single_node_flow")
local SingleDeckManager = require("single.single_deck_manager")
local SingleDiscardOverlay = require("overlays.single_discard_overlay")
local EventTablesLoader = require("single.event_tables_loader")

local SingleEventScene = {}
SingleEventScene.__index = SingleEventScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function makeRng(seed)
  if love and love.math and love.math.newRandomGenerator then
    return love.math.newRandomGenerator(seed or os.time())
  end
  math.randomseed(seed or os.time())
  return nil
end

local function randomInt(rng, minValue, maxValue)
  if maxValue <= minValue then
    return minValue
  end
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function weightedPick(eventList, rng)
  local total = 0
  for _, eventDef in ipairs(eventList or {}) do
    total = total + math.max(0.01, tonumber(eventDef.weight) or 1.0)
  end
  if total <= 0 then
    return eventList[1]
  end
  local cursor = (rng and rng:random() or math.random()) * total
  local accum = 0
  for _, eventDef in ipairs(eventList or {}) do
    accum = accum + math.max(0.01, tonumber(eventDef.weight) or 1.0)
    if cursor <= accum then
      return eventDef
    end
  end
  return eventList[#eventList]
end

local function cardNameById(cardId)
  local card = CardRegistry.getCard(cardId)
  if card and type(card.nameKo) == "string" then
    return card.nameKo
  end
  return tostring(cardId or "")
end

function SingleEventScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _nodeId = "",
    _stageIndex = 1,
    _rng = nil,
    _eventDef = nil,
    _choiceButtons = {},
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _discardOverlay = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleEventScene)
  return instance
end

function SingleEventScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleEventScene:getDeck()
  return SingleRunState.getRunDeck(self._runState, self._profile)
end

function SingleEventScene:completeNode()
  SingleNodeFlow.completeNodeAndReturnMap(self._app, self._profile, self._runState)
end

function SingleEventScene:openDiscardOverlayThenComplete()
  local deck = self:getDeck()
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

function SingleEventScene:completeOrDiscardIfOverflow()
  local deck = self:getDeck()
  if deck and #deck.cards > SingleDeckManager.MAX_DECK_SIZE then
    self:openDiscardOverlayThenComplete()
    return
  end
  self:completeNode()
end

function SingleEventScene:pickRandomDeckCardId()
  local deck = self:getDeck()
  if not deck or #deck.cards <= 0 then
    return nil, nil
  end
  local deckIndex = randomInt(self._rng, 1, #deck.cards)
  return tostring(deck.cards[deckIndex]), deckIndex
end

function SingleEventScene:pickRandomRareCardId()
  local runtimePool = CardRules.getCardPool(CardRules.GAME_MODE_SINGLE)
  local rarePool = {}
  for _, runtimeCardId in ipairs(runtimePool) do
    local saveCardId = CardRegistry.fromRuntimeCardId(runtimeCardId)
    local cardDef = CardRegistry.getCard(saveCardId)
    if cardDef and cardDef.rarity == "RARE" then
      rarePool[#rarePool + 1] = saveCardId
    end
  end
  if #rarePool <= 0 then
    return nil
  end
  return rarePool[randomInt(self._rng, 1, #rarePool)]
end

function SingleEventScene:applyOutcome(outcome)
  local outcomeType = tostring(outcome and outcome.type or "")

  if outcomeType == "gain_gold" then
    local amount = math.max(0, math.floor(tonumber(outcome.amount) or 0))
    SingleRunState.addGold(self._runState, amount)
    self:setStatus(t("single.event.status.gold_gain", { gold = tostring(amount) }), Constants.COLOR_TEXT_SUB)
    self:completeNode()
    return
  end

  if outcomeType == "lose_gold" then
    local amount = math.max(0, math.floor(tonumber(outcome.amount) or 0))
    SingleRunState.addGold(self._runState, -amount)
    self:setStatus(t("single.event.status.gold_lose", { gold = tostring(amount) }), Constants.COLOR_TEXT_SUB)
    self:completeNode()
    return
  end

  if outcomeType == "temp_modifier" then
    local key = tostring(outcome.key or "")
    if key ~= "" then
      self._runState.tempModifiers[key] = tonumber(outcome.value) or 0
    end
    self:setStatus(t("single.event.status.temp_applied"), Constants.COLOR_TEXT_SUB)
    self:completeNode()
    return
  end

  if outcomeType == "upgrade_random" then
    local cardId = self:pickRandomDeckCardId()
    if cardId then
      local level = SingleRunState.addUpgradeLevel(self._runState, cardId, 1)
      self:setStatus(t("single.event.status.upgrade_random", {
        card = cardNameById(cardId),
        level = tostring(level)
      }), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("single.event.status.deck_empty"), Constants.COLOR_DANGER)
    end
    self:completeNode()
    return
  end

  if outcomeType == "remove_random" then
    local _, deckIndex = self:pickRandomDeckCardId()
    if deckIndex then
      local removed = SingleRunState.removeCardFromRunDeck(self:getDeck(), deckIndex)
      self:setStatus(t("single.event.status.remove_random", {
        card = cardNameById(removed)
      }), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("single.event.status.deck_empty"), Constants.COLOR_DANGER)
    end
    self:completeNode()
    return
  end

  if outcomeType == "buy_rare_offer" then
    local cost = math.max(0, math.floor(tonumber(outcome.cost) or 30))
    local cardId = self:pickRandomRareCardId()
    if not cardId then
      self:setStatus(t("single.event.status.rare_missing"), Constants.COLOR_DANGER)
      self:completeNode()
      return
    end
    if not SingleRunState.spendGold(self._runState, cost) then
      self:setStatus(t("single.event.status.not_enough_gold"), Constants.COLOR_DANGER)
      return
    end
    local addOk = SingleRunState.addCardToRunDeck(self:getDeck(), cardId, {
      allowOverflow = true
    })
    if not addOk then
      SingleRunState.addGold(self._runState, cost)
      self:setStatus(t("single.event.status.buy_fail"), Constants.COLOR_DANGER)
      return
    end
    self:setStatus(t("single.event.status.buy_rare_ok", {
      card = cardNameById(cardId)
    }), Constants.COLOR_TEXT_SUB)
    self:completeOrDiscardIfOverflow()
    return
  end

  if outcomeType == "mystery_fight" then
    local fightNodeType = tostring(outcome.nodeType or "elite")
    self._app:goScene("single_combat", {
      backScene = "single_map",
      profile = self._profile,
      runState = self._runState,
      nodeType = fightNodeType,
      nodeId = self._nodeId .. "_event_fight",
      stageIndex = self._stageIndex
    }, Config.TRANSITION_FORWARD)
    return
  end

  if outcomeType == "duplicate_random" then
    local cardId = self:pickRandomDeckCardId()
    if not cardId then
      self:setStatus(t("single.event.status.deck_empty"), Constants.COLOR_DANGER)
      self:completeNode()
      return
    end
    local addOk = SingleRunState.addCardToRunDeck(self:getDeck(), cardId, {
      allowOverflow = true
    })
    if not addOk then
      self:setStatus(t("single.event.status.duplicate_fail"), Constants.COLOR_DANGER)
      self:completeNode()
      return
    end
    self:setStatus(t("single.event.status.duplicate_ok", {
      card = cardNameById(cardId)
    }), Constants.COLOR_TEXT_SUB)
    self:completeOrDiscardIfOverflow()
    return
  end

  if outcomeType == "remove_n" then
    local removeCount = math.max(1, math.floor(tonumber(outcome.count) or 1))
    local removedCount = 0
    for _ = 1, removeCount do
      local _, deckIndex = self:pickRandomDeckCardId()
      if not deckIndex then
        break
      end
      SingleRunState.removeCardFromRunDeck(self:getDeck(), deckIndex)
      removedCount = removedCount + 1
    end
    self:setStatus(t("single.event.status.remove_n_ok", {
      count = tostring(removedCount)
    }), Constants.COLOR_TEXT_SUB)
    self:completeNode()
    return
  end

  self:completeNode()
end

function SingleEventScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._choiceButtons = {}
  local choiceList = (self._eventDef and self._eventDef.choices) or {}
  local startX = 264
  local gap = 24
  local buttonW = 360
  for index = 1, 2 do
    local choice = choiceList[index]
    local choiceLocal = choice
    self._choiceButtons[index] = Button.new({
      x = startX + (index - 1) * (buttonW + gap),
      y = 394,
      w = buttonW,
      h = 120,
      label = choiceLocal and t(choiceLocal.labelKey) or "-",
      onClick = function()
        if not choiceLocal then
          return
        end
        self:applyOutcome(choiceLocal.outcome)
      end
    })
  end
end

function SingleEventScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or {}
  self._nodeId = tostring((params and params.nodeId) or "")
  self._stageIndex = math.max(1, math.floor(tonumber(params and params.stageIndex) or 1))
  SingleRunState.ensureDefaults(self._runState, self._profile)
  self._discardOverlay = nil

  local seed = (tonumber(self._runState.rngSeed) or os.time()) + (self._runState.depthIndex or 1) * 811
  self._rng = makeRng(seed)
  local loaded = EventTablesLoader.load()
  local eventList = (loaded and loaded.events) or {}
  self._eventDef = weightedPick(eventList, self._rng) or eventList[1]
  self:rebuildLocalizedUi()
  self:setStatus(t("single.event.status.ready"), Constants.COLOR_TEXT_SUB)
end

function SingleEventScene:update(dt)
  if self._discardOverlay then
    self._discardOverlay:update(dt)
  end
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleEventScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local eventDef = self._eventDef or { titleKey = "single.event.title", descKey = "single.event.desc" }

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.event.title"), 0, 70, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.event.gold_line", {
    gold = tostring(math.max(0, math.floor(tonumber(self._runState.gold) or 0)))
  }), 0, 126, Constants.BASE_WORLD_W, "center")

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t(eventDef.titleKey), 0, 186, Constants.BASE_WORLD_W, "center")

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t(eventDef.descKey), 220, 238, Constants.BASE_WORLD_W - 440, "center")

  for _, button in ipairs(self._choiceButtons) do
    button:draw(mouseX, mouseY)
  end

  if self._discardOverlay then
    self._discardOverlay:draw(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function SingleEventScene:mousepressed(mouseX, mouseY, button)
  if self._discardOverlay and self._discardOverlay:mousepressed(mouseX, mouseY, button) then
    return
  end
  if button ~= 1 then
    return
  end
  for _, choiceButton in ipairs(self._choiceButtons) do
    if choiceButton:isHovered(mouseX, mouseY) then
      choiceButton:onClick()
      return
    end
  end
end

function SingleEventScene:wheelmoved(x, y)
  if self._discardOverlay then
    self._discardOverlay:wheelmoved(x, y)
  end
end

function SingleEventScene:keypressed(key)
  if self._discardOverlay and self._discardOverlay:keypressed(key) then
    return
  end
  if key == "escape" then
    return
  end
end

function SingleEventScene:onAppEvent(_event)
end

return SingleEventScene
