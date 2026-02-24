--[[
파일명: upgrade_draft.lua
모듈명: UpgradeDraft

역할:
- 싱글 웨이브 무한모드 업그레이드 드래프트(3개 선택지)를 생성한다.
- 카테고리 가중치(카드/유물/패조작)와 중복 방지 규칙을 관리한다.
]]

local CardRules = require("shared.card_rules")
local CardRegistry = require("single.card_registry")
local RelicRegistry = require("single.relic_registry")

local UpgradeDraft = {}

UpgradeDraft.CATEGORY_CARD = "card"
UpgradeDraft.CATEGORY_RELIC = "relic"
UpgradeDraft.CATEGORY_HAND_OP = "hand_ops"

local CATEGORY_WEIGHT_LIST = {
  { id = UpgradeDraft.CATEGORY_CARD, weight = 15 },
  { id = UpgradeDraft.CATEGORY_RELIC, weight = 35 },
  { id = UpgradeDraft.CATEGORY_HAND_OP, weight = 50 }
}

local CARD_RARITY_WEIGHT = {
  COMMON = 0.72,
  RARE = 0.22,
  EPIC = 0.06,
  LEGENDARY = 0.00
}

local RELIC_RARITY_WEIGHT = {
  COMMON = 0.68,
  RARE = 0.24,
  EPIC = 0.08,
  LEGENDARY = 0.00
}

local HAND_OP_DEF_LIST = {
  {
    id = "hand_draw_one",
    rarity = "COMMON",
    titleKey = "single.wave.upgrade.hand_op.hand_draw_one.title",
    descKey = "single.wave.upgrade.hand_op.hand_draw_one.desc",
    effectGroupId = "hand_draw"
  },
  {
    id = "hand_draw_two",
    rarity = "RARE",
    titleKey = "single.wave.upgrade.hand_op.hand_draw_two.title",
    descKey = "single.wave.upgrade.hand_op.hand_draw_two.desc",
    effectGroupId = "hand_draw"
  },
  {
    id = "hand_shuffle_deck",
    rarity = "COMMON",
    titleKey = "single.wave.upgrade.hand_op.hand_shuffle_deck.title",
    descKey = "single.wave.upgrade.hand_op.hand_shuffle_deck.desc",
    effectGroupId = "hand_shuffle"
  },
  {
    id = "hand_recycle_discard",
    rarity = "RARE",
    titleKey = "single.wave.upgrade.hand_op.hand_recycle_discard.title",
    descKey = "single.wave.upgrade.hand_op.hand_recycle_discard.desc",
    effectGroupId = "hand_recycle"
  }
}

local function randomFloat(rng)
  if rng and type(rng.random) == "function" then
    return rng:random()
  end
  return math.random()
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

local function weightedPick(weightTable, rng)
  local totalWeight = 0
  for _, entry in ipairs(weightTable or {}) do
    totalWeight = totalWeight + math.max(0, tonumber(entry.weight) or 0)
  end
  if totalWeight <= 0 then
    return nil
  end
  local cursor = randomFloat(rng) * totalWeight
  local accum = 0
  for _, entry in ipairs(weightTable) do
    accum = accum + math.max(0, tonumber(entry.weight) or 0)
    if cursor <= accum then
      return entry.id
    end
  end
  return weightTable[#weightTable] and weightTable[#weightTable].id or nil
end

local function weightedRarityPick(weightMap, rng)
  local weightList = {}
  for rarity, weight in pairs(weightMap or {}) do
    if type(rarity) == "string" then
      weightList[#weightList + 1] = {
        id = rarity,
        weight = weight
      }
    end
  end
  local picked = weightedPick(weightList, rng)
  return picked or "COMMON"
end

local function buildSingleCardPool()
  local runtimeCardIdList = CardRules.getCardPool(CardRules.GAME_MODE_SINGLE)
  local list = {}
  for _, runtimeCardId in ipairs(runtimeCardIdList or {}) do
    local saveCardId = CardRegistry.fromRuntimeCardId(runtimeCardId)
    local cardDef = CardRegistry.getCard(saveCardId)
    if cardDef then
      list[#list + 1] = cardDef
    end
  end
  return list
end

local function pickCardOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
  local candidateList = buildSingleCardPool()
  if #candidateList <= 0 then
    return nil
  end

  local rarity = weightedRarityPick(CARD_RARITY_WEIGHT, context.rng)
  local filteredList = {}
  for _, cardDef in ipairs(candidateList) do
    local optionId = "card:" .. tostring(cardDef.id)
    local effectGroupId = "card:" .. tostring(cardDef.id)
    if not excludedOptionIdSet[optionId] and not excludedEffectGroupIdSet[effectGroupId] and tostring(cardDef.rarity or "COMMON") == rarity then
      filteredList[#filteredList + 1] = cardDef
    end
  end

  if #filteredList <= 0 then
    for _, cardDef in ipairs(candidateList) do
      local optionId = "card:" .. tostring(cardDef.id)
      local effectGroupId = "card:" .. tostring(cardDef.id)
      if not excludedOptionIdSet[optionId] and not excludedEffectGroupIdSet[effectGroupId] then
        filteredList[#filteredList + 1] = cardDef
      end
    end
  end
  if #filteredList <= 0 then
    return nil
  end

  local pickedCard = filteredList[randomInt(context.rng, 1, #filteredList)]
  local cardId = tostring(pickedCard.id)
  return {
    optionId = "card:" .. cardId,
    effectGroupId = "card:" .. cardId,
    category = UpgradeDraft.CATEGORY_CARD,
    rarity = tostring(pickedCard.rarity or "COMMON"),
    titleKey = "",
    descKey = "",
    titleText = tostring(pickedCard.nameKo or cardId),
    descText = tostring(pickedCard.descKo or ""),
    payload = {
      cardId = cardId
    }
  }
end

local function pickRelicOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
  local ownedSet = {}
  if type(context.relicIdList) == "table" then
    for _, relicId in ipairs(context.relicIdList) do
      ownedSet[tostring(relicId or "")] = true
    end
  end

  local rarity = weightedRarityPick(RELIC_RARITY_WEIGHT, context.rng)
  local candidateList = {}
  for _, relic in ipairs(RelicRegistry.listAll()) do
    local relicId = tostring(relic.relicId or "")
    if relicId ~= "" and not ownedSet[relicId] then
      local optionId = "relic:" .. relicId
      local effectGroupId = "relic:" .. relicId
      if not excludedOptionIdSet[optionId] and not excludedEffectGroupIdSet[effectGroupId] and tostring(relic.rarity or "COMMON") == rarity then
        candidateList[#candidateList + 1] = relic
      end
    end
  end

  if #candidateList <= 0 then
    for _, relic in ipairs(RelicRegistry.listAll()) do
      local relicId = tostring(relic.relicId or "")
      if relicId ~= "" and not ownedSet[relicId] then
        local optionId = "relic:" .. relicId
        local effectGroupId = "relic:" .. relicId
        if not excludedOptionIdSet[optionId] and not excludedEffectGroupIdSet[effectGroupId] then
          candidateList[#candidateList + 1] = relic
        end
      end
    end
  end
  if #candidateList <= 0 then
    return nil
  end

  local pickedRelic = candidateList[randomInt(context.rng, 1, #candidateList)]
  local relicId = tostring(pickedRelic.relicId or "")
  return {
    optionId = "relic:" .. relicId,
    effectGroupId = "relic:" .. relicId,
    category = UpgradeDraft.CATEGORY_RELIC,
    rarity = tostring(pickedRelic.rarity or "COMMON"),
    titleKey = "single.relic.name." .. relicId,
    descKey = "single.relic.desc." .. relicId,
    titleText = relicId,
    descText = "",
    payload = {
      relicId = relicId
    }
  }
end

local function pickHandOpOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
  local rarity = weightedRarityPick({
    COMMON = 0.72,
    RARE = 0.28
  }, context.rng)
  local candidateList = {}
  for _, handOp in ipairs(HAND_OP_DEF_LIST) do
    local optionId = "hand:" .. handOp.id
    if tostring(handOp.rarity or "COMMON") == rarity and (not excludedOptionIdSet[optionId]) and (not excludedEffectGroupIdSet[handOp.effectGroupId]) then
      candidateList[#candidateList + 1] = handOp
    end
  end
  if #candidateList <= 0 then
    for _, handOp in ipairs(HAND_OP_DEF_LIST) do
      local optionId = "hand:" .. handOp.id
      if (not excludedOptionIdSet[optionId]) and (not excludedEffectGroupIdSet[handOp.effectGroupId]) then
        candidateList[#candidateList + 1] = handOp
      end
    end
  end
  if #candidateList <= 0 then
    return nil
  end
  local picked = candidateList[randomInt(context.rng, 1, #candidateList)]
  return {
    optionId = "hand:" .. picked.id,
    effectGroupId = tostring(picked.effectGroupId),
    category = UpgradeDraft.CATEGORY_HAND_OP,
    rarity = tostring(picked.rarity or "COMMON"),
    titleKey = picked.titleKey,
    descKey = picked.descKey,
    titleText = picked.id,
    descText = "",
    payload = {
      handOpId = picked.id
    }
  }
end

local function buildOptionByCategory(context, categoryId, excludedOptionIdSet, excludedEffectGroupIdSet)
  if categoryId == UpgradeDraft.CATEGORY_CARD then
    return pickCardOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
  end
  if categoryId == UpgradeDraft.CATEGORY_RELIC then
    return pickRelicOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
  end
  return pickHandOpOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
end

function UpgradeDraft.build(optionContext)
  local context = type(optionContext) == "table" and optionContext or {}
  local optionList = {}
  local excludedOptionIdSet = {}
  local excludedEffectGroupIdSet = {}

  for _ = 1, 3 do
    local pickedOption = nil
    for _ = 1, 12 do
      local categoryId = weightedPick(CATEGORY_WEIGHT_LIST, context.rng) or UpgradeDraft.CATEGORY_HAND_OP
      local candidate = buildOptionByCategory(context, categoryId, excludedOptionIdSet, excludedEffectGroupIdSet)
      if candidate then
        pickedOption = candidate
        break
      end
    end
    if not pickedOption then
      pickedOption = pickHandOpOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
        or pickCardOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
        or pickRelicOption(context, excludedOptionIdSet, excludedEffectGroupIdSet)
    end
    if not pickedOption then
      break
    end
    excludedOptionIdSet[pickedOption.optionId] = true
    excludedEffectGroupIdSet[pickedOption.effectGroupId] = true
    optionList[#optionList + 1] = pickedOption
  end

  while #optionList < 3 do
    optionList[#optionList + 1] = {
      optionId = "hand:hand_shuffle_deck:fallback:" .. tostring(#optionList + 1),
      effectGroupId = "hand_shuffle_fallback_" .. tostring(#optionList + 1),
      category = UpgradeDraft.CATEGORY_HAND_OP,
      rarity = "COMMON",
      titleKey = "single.wave.upgrade.hand_op.hand_shuffle_deck.title",
      descKey = "single.wave.upgrade.hand_op.hand_shuffle_deck.desc",
      titleText = "덱 정렬",
      descText = "",
      payload = {
        handOpId = "hand_shuffle_deck"
      }
    }
  end

  return optionList
end

return UpgradeDraft
