--[[
파일명: single_profile_store.lua
모듈명: SingleProfileStore

역할:
- 싱글 프로필 저장/로드/기본값 복구를 담당한다.
- 손상된 파일에서도 크래시 없이 기본값으로 복구한다.
]]

local Json = require("utils.json")
local CardRegistry = require("single.card_registry")
local DeckManager = require("single.single_deck_manager")

local SingleProfileStore = {
  SAVE_DIR = "save",
  SAVE_PATH = "save/single_profile.json",
  SAVE_VERSION = 1
}

local function clampOwnedCount(value)
  local numberValue = tonumber(value) or 0
  numberValue = math.floor(numberValue)
  if numberValue < 0 then
    return 0
  end
  if numberValue > DeckManager.MAX_DUPLICATE_PER_CARD then
    return DeckManager.MAX_DUPLICATE_PER_CARD
  end
  return numberValue
end

local function ensureDirectory()
  if not love or not love.filesystem then
    return false, "filesystem_unavailable"
  end
  local info = love.filesystem.getInfo(SingleProfileStore.SAVE_DIR)
  if info and info.type == "directory" then
    return true, nil
  end
  local ok, err = pcall(love.filesystem.createDirectory, SingleProfileStore.SAVE_DIR)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

local function buildDefaultCollection()
  local cards = {}
  for _, card in ipairs(CardRegistry.listAll()) do
    cards[card.id] = { ownedCount = 0 }
  end
  for _, starterId in ipairs(CardRegistry.getStarterCardIds()) do
    cards[starterId] = cards[starterId] or {}
    cards[starterId].ownedCount = 1
  end
  return {
    cards = cards
  }
end

local function buildDefaultDeck()
  local cards = {}
  for _, starterId in ipairs(CardRegistry.getStarterCardIds()) do
    cards[#cards + 1] = starterId
  end
  return {
    deckId = "default",
    name = "기본 덱",
    cards = cards
  }
end

function SingleProfileStore.ensureDefaults(profile)
  local nextProfile = type(profile) == "table" and profile or {}
  nextProfile.version = SingleProfileStore.SAVE_VERSION
  nextProfile.collection = type(nextProfile.collection) == "table" and nextProfile.collection or buildDefaultCollection()
  nextProfile.collection.cards = type(nextProfile.collection.cards) == "table" and nextProfile.collection.cards or buildDefaultCollection().cards
  nextProfile.decks = type(nextProfile.decks) == "table" and nextProfile.decks or { buildDefaultDeck() }

  if #nextProfile.decks == 0 then
    nextProfile.decks[1] = buildDefaultDeck()
  end

  local hasDefault = false
  for _, deck in ipairs(nextProfile.decks) do
    if type(deck) == "table" and tostring(deck.deckId or "") == "default" then
      hasDefault = true
      break
    end
  end
  if not hasDefault then
    nextProfile.decks[#nextProfile.decks + 1] = buildDefaultDeck()
  end

  return nextProfile
end

function SingleProfileStore.validateAndFix(profile)
  local fixed = SingleProfileStore.ensureDefaults(profile)
  local validCardIdSet = {}
  for _, card in ipairs(CardRegistry.listAll()) do
    validCardIdSet[card.id] = true
    fixed.collection.cards[card.id] = fixed.collection.cards[card.id] or { ownedCount = 0 }
    fixed.collection.cards[card.id].ownedCount = clampOwnedCount(fixed.collection.cards[card.id].ownedCount)
  end

  -- SP-01 기본 스타터 세트는 항상 보유 1장 이상으로 복구한다.
  -- 손상 저장 데이터에서도 기본 덱(5장)을 안정적으로 재구성하기 위한 가드레일이다.
  for _, starterId in ipairs(CardRegistry.getStarterCardIds()) do
    fixed.collection.cards[starterId] = fixed.collection.cards[starterId] or { ownedCount = 0 }
    fixed.collection.cards[starterId].ownedCount = math.max(1, clampOwnedCount(fixed.collection.cards[starterId].ownedCount))
  end

  for cardId, entry in pairs(fixed.collection.cards) do
    if not validCardIdSet[cardId] then
      fixed.collection.cards[cardId] = nil
    elseif type(entry) ~= "table" then
      fixed.collection.cards[cardId] = { ownedCount = 0 }
    else
      entry.ownedCount = clampOwnedCount(entry.ownedCount)
    end
  end

  local sanitizedDecks = {}
  for _, deck in ipairs(fixed.decks) do
    if type(deck) == "table" then
      local nextDeck = {
        deckId = tostring(deck.deckId or "default"),
        name = tostring(deck.name or "기본 덱"),
        cards = {}
      }
      local countById = {}
      for _, cardId in ipairs(type(deck.cards) == "table" and deck.cards or {}) do
        local normalizedCardId = tostring(cardId)
        if validCardIdSet[normalizedCardId] then
          local nextCount = (countById[normalizedCardId] or 0) + 1
          local ownedCount = fixed.collection.cards[normalizedCardId] and fixed.collection.cards[normalizedCardId].ownedCount or 0
          if nextCount <= DeckManager.MAX_DUPLICATE_PER_CARD and nextCount <= ownedCount then
            countById[normalizedCardId] = nextCount
            nextDeck.cards[#nextDeck.cards + 1] = normalizedCardId
          end
        end
        if #nextDeck.cards >= DeckManager.MAX_DECK_SIZE then
          break
        end
      end
      sanitizedDecks[#sanitizedDecks + 1] = nextDeck
    end
  end

  if #sanitizedDecks == 0 then
    sanitizedDecks[1] = buildDefaultDeck()
  end
  fixed.decks = sanitizedDecks

  for _, deck in ipairs(fixed.decks) do
    local ok = DeckManager.validateDeck(deck, fixed.collection)
    if not ok then
      local defaultDeck = buildDefaultDeck()
      deck.deckId = deck.deckId ~= "" and deck.deckId or defaultDeck.deckId
      deck.name = deck.name ~= "" and deck.name or defaultDeck.name
      deck.cards = {}
      for _, cardId in ipairs(defaultDeck.cards) do
        DeckManager.addToDeck(deck, cardId, fixed.collection)
      end
    end
  end

  return fixed
end

function SingleProfileStore.load()
  local okRead, rawOrErr = pcall(love.filesystem.read, SingleProfileStore.SAVE_PATH)
  if not okRead then
    local recovered = SingleProfileStore.validateAndFix(nil)
    return recovered, tostring(rawOrErr)
  end
  if type(rawOrErr) ~= "string" or rawOrErr == "" then
    local recovered = SingleProfileStore.validateAndFix(nil)
    return recovered, nil
  end

  local okDecode, parsedOrErr = pcall(Json.decode, rawOrErr)
  if not okDecode or type(parsedOrErr) ~= "table" then
    local recovered = SingleProfileStore.validateAndFix(nil)
    return recovered, "decode_failed"
  end

  return SingleProfileStore.validateAndFix(parsedOrErr), nil
end

function SingleProfileStore.save(profile)
  local okDir, dirErr = ensureDirectory()
  if not okDir then
    return false, dirErr
  end
  local normalized = SingleProfileStore.validateAndFix(profile)
  local okEncode, encodedOrErr = pcall(Json.encode, normalized)
  if not okEncode then
    return false, tostring(encodedOrErr)
  end
  local okWrite, writeErr = pcall(love.filesystem.write, SingleProfileStore.SAVE_PATH, encodedOrErr)
  if not okWrite then
    return false, tostring(writeErr)
  end
  return true, nil
end

return SingleProfileStore
