--[[
파일명: single_economy.lua
모듈명: SingleEconomy

역할:
- SP 런 전용 경제 규칙(골드 보상/상점 가격)을 SSOT에서 읽어 제공한다.
]]

local SingleCampaignRulesLoader = require("single.single_campaign_rules_loader")
local RelicEffects = require("single.relic_effects")

local SingleEconomy = {}

local cachedRules = nil

local function getRules()
  if not cachedRules then
    cachedRules = SingleCampaignRulesLoader.load()
  end
  return cachedRules
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

function SingleEconomy.resetCache()
  cachedRules = nil
end

function SingleEconomy.rollCombatGold(nodeType, rng, runState)
  local rules = getRules()
  local economy = type(rules.economy) == "table" and rules.economy or {}
  local rewardTable = type(economy.goldReward) == "table" and economy.goldReward or {}
  local entry = rewardTable[tostring(nodeType or "mob")]
  if type(entry) ~= "table" then
    entry = rewardTable.mob
  end
  if type(entry) ~= "table" then
    entry = { 10, 20 }
  end
  local minValue = math.max(0, math.floor(tonumber(entry[1]) or 10))
  local maxValue = math.max(minValue, math.floor(tonumber(entry[2]) or minValue))
  local rolled = randomInt(rng, minValue, maxValue)
  return RelicEffects.applyGoldModifiers(runState, rolled)
end

function SingleEconomy.getShopPrices()
  local rules = getRules()
  local economy = type(rules.economy) == "table" and rules.economy or {}
  local prices = type(economy.shopPrices) == "table" and economy.shopPrices or {}
  return {
    buyCardBase = math.max(0, math.floor(tonumber(prices.buyCardBase) or 35)),
    buyCardRareExtra = math.max(0, math.floor(tonumber(prices.buyCardRareExtra) or 10)),
    upgrade = math.max(0, math.floor(tonumber(prices.upgrade) or 40)),
    remove = math.max(0, math.floor(tonumber(prices.remove) or 30))
  }
end

function SingleEconomy.getBuyCardPrice(cardRarity)
  local prices = SingleEconomy.getShopPrices()
  local rarity = tostring(cardRarity or "COMMON"):upper()
  if rarity == "COMMON" then
    return prices.buyCardBase
  end
  return prices.buyCardBase + prices.buyCardRareExtra
end

return SingleEconomy
