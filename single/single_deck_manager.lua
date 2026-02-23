--[[
파일명: single_deck_manager.lua
모듈명: SingleDeckManager

역할:
- 싱글 덱 유효성 검사/추가/삭제/카운팅을 담당한다.
]]

local CardRegistry = require("single.card_registry")

local SingleDeckManager = {
  START_DECK_SIZE = 5,
  MAX_DECK_SIZE = 15,
  MAX_DUPLICATE_PER_CARD = 3
}

local function toOwnedCount(collection, cardId)
  if type(collection) ~= "table" then
    return 0
  end
  local cards = collection.cards
  if type(cards) ~= "table" then
    return 0
  end
  local entry = cards[cardId]
  if type(entry) ~= "table" or type(entry.ownedCount) ~= "number" then
    return 0
  end
  local owned = math.floor(entry.ownedCount)
  if owned < 0 then
    return 0
  end
  if owned > SingleDeckManager.MAX_DUPLICATE_PER_CARD then
    return SingleDeckManager.MAX_DUPLICATE_PER_CARD
  end
  return owned
end

function SingleDeckManager.countInDeck(deck, cardId)
  local cards = deck and deck.cards or {}
  local count = 0
  for _, id in ipairs(cards) do
    if id == cardId then
      count = count + 1
    end
  end
  return count
end

function SingleDeckManager.validateDeck(deck, collection)
  local errors = {}
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return false, { "invalid_deck" }
  end

  local cards = deck.cards
  if #cards > SingleDeckManager.MAX_DECK_SIZE then
    errors[#errors + 1] = "deck_size_exceeded"
  end
  if #cards < SingleDeckManager.START_DECK_SIZE then
    errors[#errors + 1] = "deck_too_small"
  end

  local countById = {}
  for _, cardId in ipairs(cards) do
    local normalizedCardId = tostring(cardId)
    if not CardRegistry.getCard(normalizedCardId) then
      errors[#errors + 1] = "unknown_card_id"
    else
      countById[normalizedCardId] = (countById[normalizedCardId] or 0) + 1
    end
  end

  for cardId, cardCount in pairs(countById) do
    if cardCount > SingleDeckManager.MAX_DUPLICATE_PER_CARD then
      errors[#errors + 1] = "duplicate_limit_exceeded"
    end
    if cardCount > toOwnedCount(collection, cardId) then
      errors[#errors + 1] = "owned_count_exceeded"
    end
  end

  return #errors == 0, errors
end

function SingleDeckManager.addToDeck(deck, cardId, collection, options)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return false, "invalid_deck"
  end

  local normalizedCardId = tostring(cardId or "")
  if normalizedCardId == "" or not CardRegistry.getCard(normalizedCardId) then
    return false, "unknown_card_id"
  end

  local currentCount = SingleDeckManager.countInDeck(deck, normalizedCardId)
  if currentCount >= SingleDeckManager.MAX_DUPLICATE_PER_CARD then
    return false, "duplicate_limit"
  end

  local ownedCount = toOwnedCount(collection, normalizedCardId)
  if currentCount >= ownedCount then
    return false, "owned_count"
  end

  local allowOverflowSize = type(options) == "table" and options.allowOverflowSize == true
  if (not allowOverflowSize) and #deck.cards >= SingleDeckManager.MAX_DECK_SIZE then
    return false, "deck_full"
  end

  deck.cards[#deck.cards + 1] = normalizedCardId
  return true, nil
end

function SingleDeckManager.removeFromDeck(deck, index)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then
    return nil
  end
  local safeIndex = tonumber(index)
  if not safeIndex then
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

return SingleDeckManager
