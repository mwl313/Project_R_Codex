--[[
파일명: single_run_state.lua
모듈명: SingleRunState

역할:
- 런 전용 상태(골드/런 덱/카드 업그레이드/임시 수정자)를 관리한다.
- 영구 프로필(profile)과 분리된 런 데이터 접근 유틸을 제공한다.
]]

local SingleDeckManager = require("single.single_deck_manager")
local CardRegistry = require("single.card_registry")

local SingleRunState = {}

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

local function cloneDeckFromProfile(profile)
  local sourceDeck = getDefaultDeck(profile)
  local cards = {}
  if sourceDeck and type(sourceDeck.cards) == "table" then
    for _, cardId in ipairs(sourceDeck.cards) do
      cards[#cards + 1] = tostring(cardId)
    end
  end
  return {
    deckId = "run_default",
    name = "런 덱",
    cards = cards
  }
end

function SingleRunState.ensureDefaults(runState, profile)
  if type(runState) ~= "table" then
    return nil
  end
  if type(runState.gold) ~= "number" then
    runState.gold = 0
  end
  runState.gold = math.max(0, math.floor(runState.gold))

  if type(runState.cardUpgrades) ~= "table" then
    runState.cardUpgrades = {}
  end
  if type(runState.tempModifiers) ~= "table" then
    runState.tempModifiers = {}
  end
  if type(runState.runtimeDeck) ~= "table" or type(runState.runtimeDeck.cards) ~= "table" then
    runState.runtimeDeck = cloneDeckFromProfile(profile)
  end
  if type(runState.runtimeDeck.cards) ~= "table" then
    runState.runtimeDeck.cards = {}
  end
  return runState
end

function SingleRunState.getRunDeck(runState, profile)
  SingleRunState.ensureDefaults(runState, profile)
  return runState and runState.runtimeDeck or nil
end

function SingleRunState.countInDeck(deck, cardId)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return 0
  end
  local normalizedId = tostring(cardId or "")
  local count = 0
  for _, id in ipairs(deck.cards) do
    if tostring(id) == normalizedId then
      count = count + 1
    end
  end
  return count
end

function SingleRunState.addCardToRunDeck(deck, cardId, options)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return false, "invalid_deck"
  end
  local normalizedId = tostring(cardId or "")
  if normalizedId == "" or not CardRegistry.getCard(normalizedId) then
    return false, "unknown_card_id"
  end

  local currentCount = SingleRunState.countInDeck(deck, normalizedId)
  if currentCount >= SingleDeckManager.MAX_DUPLICATE_PER_CARD then
    return false, "duplicate_limit"
  end

  local allowOverflow = type(options) == "table" and options.allowOverflow == true
  if (not allowOverflow) and #deck.cards >= SingleDeckManager.MAX_DECK_SIZE then
    return false, "deck_full"
  end

  deck.cards[#deck.cards + 1] = normalizedId
  return true
end

function SingleRunState.removeCardFromRunDeck(deck, index)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return nil
  end
  local safeIndex = tonumber(index)
  if type(safeIndex) ~= "number" then
    return nil
  end
  safeIndex = math.floor(safeIndex)
  if safeIndex < 1 or safeIndex > #deck.cards then
    return nil
  end
  local removed = deck.cards[safeIndex]
  table.remove(deck.cards, safeIndex)
  return removed
end

function SingleRunState.addGold(runState, amount)
  if type(runState) ~= "table" then
    return 0
  end
  SingleRunState.ensureDefaults(runState, nil)
  runState.gold = math.max(0, math.floor((runState.gold or 0) + (tonumber(amount) or 0)))
  return runState.gold
end

function SingleRunState.spendGold(runState, amount)
  if type(runState) ~= "table" then
    return false
  end
  SingleRunState.ensureDefaults(runState, nil)
  local cost = math.max(0, math.floor(tonumber(amount) or 0))
  if (runState.gold or 0) < cost then
    return false
  end
  runState.gold = math.max(0, runState.gold - cost)
  return true
end

function SingleRunState.getUpgradeLevel(runState, cardId)
  if type(runState) ~= "table" or type(runState.cardUpgrades) ~= "table" then
    return 0
  end
  local level = tonumber(runState.cardUpgrades[tostring(cardId or "")]) or 0
  level = math.floor(level)
  if level < 0 then
    return 0
  end
  return level
end

function SingleRunState.addUpgradeLevel(runState, cardId, amount)
  if type(runState) ~= "table" then
    return 0
  end
  SingleRunState.ensureDefaults(runState, nil)
  local key = tostring(cardId or "")
  local current = SingleRunState.getUpgradeLevel(runState, key)
  local nextValue = math.max(0, current + math.max(0, math.floor(tonumber(amount) or 1)))
  runState.cardUpgrades[key] = nextValue
  return nextValue
end

return SingleRunState
