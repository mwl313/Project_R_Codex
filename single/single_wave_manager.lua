--[[
파일명: single_wave_manager.lua
모듈명: SingleWaveManager

역할:
- 싱글 웨이브 무한모드 런 상태(웨이브/스코어/덱/핸드/유물)를 관리한다.
- 전투 코어와 분리된 순수 상태 조작 API를 제공한다.
]]

local CardRegistry = require("single.card_registry")
local RelicRegistry = require("single.relic_registry")
local RuntimeRelicStore = require("single.runtime_relic_store")

local SingleWaveManager = {}
SingleWaveManager.__index = SingleWaveManager

local function cloneList(sourceList)
  local copied = {}
  for _, value in ipairs(sourceList or {}) do
    copied[#copied + 1] = value
  end
  return copied
end

local function makeRng(seedValue)
  if love and love.math and type(love.math.newRandomGenerator) == "function" then
    return love.math.newRandomGenerator(seedValue)
  end
  return nil
end

local function randomInt(rng, minValue, maxValue)
  if minValue >= maxValue then
    return minValue
  end
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function shuffleListInPlace(list, rng)
  for index = #list, 2, -1 do
    local swapIndex = randomInt(rng, 1, index)
    list[index], list[swapIndex] = list[swapIndex], list[index]
  end
end

local function getDefaultDeckCardIdList(profile)
  if type(profile) ~= "table" or type(profile.decks) ~= "table" then
    return CardRegistry.getStarterCardIds()
  end
  local selectedDeck = nil
  for _, deck in ipairs(profile.decks) do
    if type(deck) == "table" and tostring(deck.deckId or "") == "default" then
      selectedDeck = deck
      break
    end
  end
  if not selectedDeck then
    selectedDeck = profile.decks[1]
  end
  if type(selectedDeck) ~= "table" or type(selectedDeck.cards) ~= "table" then
    return CardRegistry.getStarterCardIds()
  end

  local cardIdList = {}
  for _, cardId in ipairs(selectedDeck.cards) do
    local normalizedCardId = tostring(cardId or "")
    if normalizedCardId ~= "" and CardRegistry.getCard(normalizedCardId) then
      cardIdList[#cardIdList + 1] = normalizedCardId
    end
  end
  if #cardIdList <= 0 then
    return CardRegistry.getStarterCardIds()
  end
  return cardIdList
end

function SingleWaveManager.new(profile)
  local seedValue = os.time()
  local instance = {
    _profile = profile,
    _rngSeed = seedValue,
    _rng = makeRng(seedValue),
    _runId = "wave_" .. tostring(seedValue),
    _wavesPerStage = 5,
    _waveIndex = 1,
    _stageIndex = 1,
    _isFinished = false,
    _maxCombo = 0,
    _enemiesKilled = 0,
    _drawPileCardIdList = {},
    _discardPileCardIdList = {},
    _handCardIdList = {},
    _relicIdList = {},
    _runtimeState = nil
  }
  setmetatable(instance, SingleWaveManager)
  instance:reset(profile)
  return instance
end

function SingleWaveManager:reset(profile)
  self._profile = profile or self._profile
  self._runId = "wave_" .. tostring(os.time())
  self._waveIndex = 1
  self._stageIndex = 1
  self._isFinished = false
  self._maxCombo = 0
  self._enemiesKilled = 0
  RuntimeRelicStore.clear()
  self._drawPileCardIdList = getDefaultDeckCardIdList(self._profile)
  self._discardPileCardIdList = {}
  self._handCardIdList = {}
  self._relicIdList = {}
  self._runtimeState = {
    runId = self._runId,
    stageIndex = self._stageIndex,
    rngSeed = self._rngSeed,
    runtimeDeck = {
      deckId = "wave_runtime",
      name = "웨이브 런 덱",
      cards = cloneList(self._drawPileCardIdList)
    },
    relicIds = self._relicIdList,
    cardUpgrades = {},
    tempModifiers = {}
  }
  shuffleListInPlace(self._drawPileCardIdList, self._rng)
  self:syncRuntimeDeck()
end

function SingleWaveManager:clearRuntimeRelics()
  RuntimeRelicStore.clear()
  self._relicIdList = {}
  if type(self._runtimeState) == "table" then
    self._runtimeState.relicIds = self._relicIdList
  end
end

function SingleWaveManager:getRuntimeState()
  return self._runtimeState
end

function SingleWaveManager:getRng()
  return self._rng
end

function SingleWaveManager:syncRuntimeDeck()
  if type(self._runtimeState) ~= "table" then
    return
  end
  self._runtimeState.stageIndex = self._stageIndex
  self._runtimeState.runId = self._runId
  if type(self._runtimeState.runtimeDeck) ~= "table" then
    self._runtimeState.runtimeDeck = {
      deckId = "wave_runtime",
      name = "웨이브 런 덱",
      cards = {}
    }
  end
  self._runtimeState.runtimeDeck.cards = cloneList(self._drawPileCardIdList)
end

function SingleWaveManager:getWaveIndex()
  return self._waveIndex
end

function SingleWaveManager:getStageIndex()
  return self._stageIndex
end

function SingleWaveManager:getWaveInStageIndex()
  return ((self._waveIndex - 1) % self._wavesPerStage) + 1
end

function SingleWaveManager:getCurrentNodeType()
  local waveInStage = self:getWaveInStageIndex()
  if waveInStage == self._wavesPerStage then
    return "boss"
  end
  if waveInStage == self._wavesPerStage - 1 then
    return "elite"
  end
  return "mob"
end

function SingleWaveManager:getCurrentNodeId()
  return string.format("wave_%d_s%d_w%d", self._waveIndex, self._stageIndex, self:getWaveInStageIndex())
end

function SingleWaveManager:advanceWave()
  self._waveIndex = self._waveIndex + 1
  self._stageIndex = math.floor((self._waveIndex - 1) / self._wavesPerStage) + 1
  self:syncRuntimeDeck()
end

function SingleWaveManager:getScoreSnapshot()
  return {
    maxCombo = self._maxCombo,
    enemiesKilled = self._enemiesKilled
  }
end

function SingleWaveManager:addEnemiesKilled(count)
  local safeCount = math.max(0, math.floor(tonumber(count) or 0))
  self._enemiesKilled = math.max(0, self._enemiesKilled + safeCount)
end

function SingleWaveManager:updateCombo(comboCount)
  local safeCombo = math.max(0, math.floor(tonumber(comboCount) or 0))
  if safeCombo > self._maxCombo then
    self._maxCombo = safeCombo
  end
end

function SingleWaveManager:getHandCardIdList()
  return cloneList(self._handCardIdList)
end

function SingleWaveManager:setHandCardIdList(cardIdList)
  self._handCardIdList = {}
  for _, cardId in ipairs(cardIdList or {}) do
    local normalizedCardId = tostring(cardId or "")
    if normalizedCardId ~= "" and CardRegistry.getCard(normalizedCardId) then
      self._handCardIdList[#self._handCardIdList + 1] = normalizedCardId
    end
  end
end

function SingleWaveManager:getHandCount()
  return #self._handCardIdList
end

function SingleWaveManager:getDrawPileCount()
  return #self._drawPileCardIdList
end

function SingleWaveManager:getDiscardPileCount()
  return #self._discardPileCardIdList
end

function SingleWaveManager:reshuffleDiscardIntoDraw()
  if #self._discardPileCardIdList <= 0 then
    return false
  end
  for _, cardId in ipairs(self._discardPileCardIdList) do
    self._drawPileCardIdList[#self._drawPileCardIdList + 1] = cardId
  end
  self._discardPileCardIdList = {}
  shuffleListInPlace(self._drawPileCardIdList, self._rng)
  self:syncRuntimeDeck()
  return true
end

function SingleWaveManager:drawOneCard()
  if #self._drawPileCardIdList <= 0 then
    self:reshuffleDiscardIntoDraw()
  end
  if #self._drawPileCardIdList <= 0 then
    return nil
  end
  local cardId = table.remove(self._drawPileCardIdList)
  self:syncRuntimeDeck()
  return cardId
end

function SingleWaveManager:drawCardsToHand(drawCount, maxHandCount)
  local drawnList = {}
  local targetDrawCount = math.max(0, math.floor(tonumber(drawCount) or 0))
  local handLimit = math.max(1, math.floor(tonumber(maxHandCount) or 8))
  for _ = 1, targetDrawCount do
    if #self._handCardIdList >= handLimit then
      break
    end
    local cardId = self:drawOneCard()
    if not cardId then
      break
    end
    self._handCardIdList[#self._handCardIdList + 1] = cardId
    drawnList[#drawnList + 1] = cardId
  end
  return drawnList
end

function SingleWaveManager:addConsumedCard(cardId)
  local normalizedCardId = tostring(cardId or "")
  if normalizedCardId == "" then
    return
  end
  self._discardPileCardIdList[#self._discardPileCardIdList + 1] = normalizedCardId
end

function SingleWaveManager:addCardReward(cardId, maxHandCount)
  local normalizedCardId = tostring(cardId or "")
  if normalizedCardId == "" or not CardRegistry.getCard(normalizedCardId) then
    return false, "invalid_card_id"
  end
  local handLimit = math.max(1, math.floor(tonumber(maxHandCount) or 8))
  if #self._handCardIdList < handLimit then
    self._handCardIdList[#self._handCardIdList + 1] = normalizedCardId
    return true, "hand"
  end
  self._drawPileCardIdList[#self._drawPileCardIdList + 1] = normalizedCardId
  shuffleListInPlace(self._drawPileCardIdList, self._rng)
  self:syncRuntimeDeck()
  return true, "deck"
end

function SingleWaveManager:addRelic(relicId)
  local normalizedRelicId = tostring(relicId or "")
  if normalizedRelicId == "" then
    return false
  end
  if not RelicRegistry.getRelic(normalizedRelicId) then
    return false
  end
  for _, existing in ipairs(self._relicIdList) do
    if tostring(existing) == normalizedRelicId then
      return false
    end
  end
  self._relicIdList[#self._relicIdList + 1] = normalizedRelicId
  return true
end

function SingleWaveManager:getRelicIdList()
  return cloneList(self._relicIdList)
end

function SingleWaveManager:getRelicBuffEntryList()
  local list = {}
  for _, relicId in ipairs(self._relicIdList) do
    local relic = RelicRegistry.getRelic(relicId)
    if relic then
      list[#list + 1] = relic
    end
  end
  return list
end

function SingleWaveManager:applyHandOperation(handOpId, maxHandCount)
  local operationId = tostring(handOpId or "")
  if operationId == "hand_draw_one" then
    local drawnList = self:drawCardsToHand(1, maxHandCount)
    return { isApplied = true, drawnCount = #drawnList }
  end
  if operationId == "hand_draw_two" then
    local drawnList = self:drawCardsToHand(2, maxHandCount)
    return { isApplied = true, drawnCount = #drawnList }
  end
  if operationId == "hand_shuffle_deck" then
    shuffleListInPlace(self._drawPileCardIdList, self._rng)
    self:syncRuntimeDeck()
    return { isApplied = true, drawnCount = 0 }
  end
  if operationId == "hand_recycle_discard" then
    local recycled = self:reshuffleDiscardIntoDraw()
    return { isApplied = recycled, drawnCount = 0 }
  end
  return { isApplied = false, drawnCount = 0 }
end

return SingleWaveManager
