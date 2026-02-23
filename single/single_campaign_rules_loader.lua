--[[
파일명: single_campaign_rules_loader.lua
모듈명: SingleCampaignRulesLoader
]]

local LoaderUtils = require("single.single_json_loader")

local SingleCampaignRulesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  deck = {
    startPickCount = 5,
    maxSize = 15,
    maxDuplicatePerCard = 3,
    drawPerBattle = 5
  },
  rarityWeights = {
    base = { COMMON = 0.65, RARE = 0.27, EPIC = 0.08 },
    bossBonus = { EPIC = 0.15 },
    stageScaling = {
      { stageIndex = 1, COMMON = 0.75, RARE = 0.22, EPIC = 0.03 },
      { stageIndex = 2, COMMON = 0.65, RARE = 0.27, EPIC = 0.08 }
    }
  },
  legendaryPolicy = {
    bossOnly = true
  }
}

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = LoaderUtils.deepCopy(DEFAULT_DATA)
  sanitized.version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version)

  local sourceDeck = LoaderUtils.toTable(source.deck, {})
  sanitized.deck.startPickCount = LoaderUtils.toNumber(sourceDeck.startPickCount, DEFAULT_DATA.deck.startPickCount)
  sanitized.deck.maxSize = LoaderUtils.toNumber(sourceDeck.maxSize, DEFAULT_DATA.deck.maxSize)
  sanitized.deck.maxDuplicatePerCard = LoaderUtils.toNumber(sourceDeck.maxDuplicatePerCard, DEFAULT_DATA.deck.maxDuplicatePerCard)
  sanitized.deck.drawPerBattle = LoaderUtils.toNumber(sourceDeck.drawPerBattle, DEFAULT_DATA.deck.drawPerBattle)

  local sourceRarity = LoaderUtils.toTable(source.rarityWeights, {})
  local sourceBase = LoaderUtils.toTable(sourceRarity.base, {})
  sanitized.rarityWeights.base.COMMON = LoaderUtils.toNumber(sourceBase.COMMON, DEFAULT_DATA.rarityWeights.base.COMMON)
  sanitized.rarityWeights.base.RARE = LoaderUtils.toNumber(sourceBase.RARE, DEFAULT_DATA.rarityWeights.base.RARE)
  sanitized.rarityWeights.base.EPIC = LoaderUtils.toNumber(sourceBase.EPIC, DEFAULT_DATA.rarityWeights.base.EPIC)

  local sourceBossBonus = LoaderUtils.toTable(sourceRarity.bossBonus, {})
  sanitized.rarityWeights.bossBonus.EPIC = LoaderUtils.toNumber(sourceBossBonus.EPIC, DEFAULT_DATA.rarityWeights.bossBonus.EPIC)

  local sourceScaling = LoaderUtils.toArray(sourceRarity.stageScaling, {})
  local sanitizedScaling = {}
  for _, entry in ipairs(sourceScaling) do
    if type(entry) == "table" then
      sanitizedScaling[#sanitizedScaling + 1] = {
        stageIndex = LoaderUtils.toNumber(entry.stageIndex, 1),
        COMMON = LoaderUtils.toNumber(entry.COMMON, DEFAULT_DATA.rarityWeights.base.COMMON),
        RARE = LoaderUtils.toNumber(entry.RARE, DEFAULT_DATA.rarityWeights.base.RARE),
        EPIC = LoaderUtils.toNumber(entry.EPIC, DEFAULT_DATA.rarityWeights.base.EPIC)
      }
    end
  end
  if #sanitizedScaling > 0 then
    sanitized.rarityWeights.stageScaling = sanitizedScaling
  end

  local sourceLegendary = LoaderUtils.toTable(source.legendaryPolicy, {})
  sanitized.legendaryPolicy.bossOnly = LoaderUtils.toBoolean(sourceLegendary.bossOnly, DEFAULT_DATA.legendaryPolicy.bossOnly)

  return sanitized
end

function SingleCampaignRulesLoader.load()
  local raw = LoaderUtils.readJson("shared/single_campaign_rules.json", "single_campaign_rules")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return SingleCampaignRulesLoader
