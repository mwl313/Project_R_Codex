--[[
파일명: single_data_loader.lua
모듈명: SingleDataLoader

역할:
- SP-01.5용 SSOT JSON(스테이지 템플릿/캠페인 룰)을 안전하게 로드한다.
- 파일이 없거나 손상된 경우 기본값으로 폴백한다.
]]

local LoaderUtils = require("single.single_json_loader")

local SingleDataLoader = {}

local DEFAULT_STAGE_TEMPLATES = {
  version = 1,
  templates = {
    {
      templateId = "template_a",
      stageIndex = 1,
      nodeCount = 10,
      bossAtEnd = true,
      restBeforeBoss = true,
      weights = {
        mob = 0.55,
        elite = 0.10,
        shop = 0.10,
        rest = 0.00,
        deck_clean = 0.10,
        event = 0.15
      },
      limits = {
        eliteMin = 1,
        eliteMax = 1,
        shopMin = 1,
        shopMax = 1,
        deckCleanMin = 1,
        deckCleanMax = 1,
        eventMin = 1,
        eventMax = 1
      },
      constraints = {
        noSameTypeStreak = 3,
        noBackToBack = { "shop", "rest", "deck_clean" }
      }
    }
  }
}

local DEFAULT_CAMPAIGN_RULES = {
  version = 1,
  deck = {
    maxSize = 15,
    maxDuplicatePerCard = 3,
    drawPerBattle = 5
  }
}

local function sanitizeWeights(source)
  local entry = LoaderUtils.toTable(source, {})
  return {
    mob = math.max(0, LoaderUtils.toNumber(entry.mob, 0.55)),
    elite = math.max(0, LoaderUtils.toNumber(entry.elite, 0.10)),
    shop = math.max(0, LoaderUtils.toNumber(entry.shop, 0.10)),
    rest = math.max(0, LoaderUtils.toNumber(entry.rest, 0.00)),
    deck_clean = math.max(0, LoaderUtils.toNumber(entry.deck_clean, 0.10)),
    event = math.max(0, LoaderUtils.toNumber(entry.event, 0.15))
  }
end

local function sanitizeLimits(source)
  local entry = LoaderUtils.toTable(source, {})
  return {
    eliteMin = math.max(0, math.floor(LoaderUtils.toNumber(entry.eliteMin, 0))),
    eliteMax = math.max(0, math.floor(LoaderUtils.toNumber(entry.eliteMax, 99))),
    shopMin = math.max(0, math.floor(LoaderUtils.toNumber(entry.shopMin, 0))),
    shopMax = math.max(0, math.floor(LoaderUtils.toNumber(entry.shopMax, 99))),
    deckCleanMin = math.max(0, math.floor(LoaderUtils.toNumber(entry.deckCleanMin, 0))),
    deckCleanMax = math.max(0, math.floor(LoaderUtils.toNumber(entry.deckCleanMax, 99))),
    eventMin = math.max(0, math.floor(LoaderUtils.toNumber(entry.eventMin, 0))),
    eventMax = math.max(0, math.floor(LoaderUtils.toNumber(entry.eventMax, 99)))
  }
end

local function sanitizeConstraints(source)
  local entry = LoaderUtils.toTable(source, {})
  local backToBack = {}
  for _, value in ipairs(LoaderUtils.toArray(entry.noBackToBack, {})) do
    if type(value) == "string" and value ~= "" then
      backToBack[#backToBack + 1] = value
    end
  end
  return {
    noSameTypeStreak = math.max(2, math.floor(LoaderUtils.toNumber(entry.noSameTypeStreak, 3))),
    noBackToBack = backToBack
  }
end

local function sanitizeTemplate(source)
  local entry = LoaderUtils.toTable(source, {})
  return {
    templateId = LoaderUtils.toString(entry.templateId, "template_a"),
    stageIndex = math.max(1, math.floor(LoaderUtils.toNumber(entry.stageIndex, 1))),
    nodeCount = math.max(3, math.floor(LoaderUtils.toNumber(entry.nodeCount, 10))),
    bossAtEnd = LoaderUtils.toBoolean(entry.bossAtEnd, true),
    restBeforeBoss = LoaderUtils.toBoolean(entry.restBeforeBoss, true),
    weights = sanitizeWeights(entry.weights),
    limits = sanitizeLimits(entry.limits),
    constraints = sanitizeConstraints(entry.constraints)
  }
end

function SingleDataLoader.loadSingleStageTemplates()
  local raw = LoaderUtils.readJson("shared/single_stage_templates.json", "single_stage_templates")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_STAGE_TEMPLATES)
  end

  local templates = {}
  for _, value in ipairs(LoaderUtils.toArray(raw.templates, {})) do
    if type(value) == "table" then
      templates[#templates + 1] = sanitizeTemplate(value)
    end
  end
  if #templates <= 0 then
    LoaderUtils.warn("single_stage_templates", "templates_empty_fallback")
    templates = LoaderUtils.deepCopy(DEFAULT_STAGE_TEMPLATES.templates)
  end

  return {
    version = math.max(1, math.floor(LoaderUtils.toNumber(raw.version, 1))),
    templates = templates
  }
end

function SingleDataLoader.loadSingleCampaignRules()
  local raw = LoaderUtils.readJson("shared/single_campaign_rules.json", "single_campaign_rules_sp15")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_CAMPAIGN_RULES)
  end

  local deck = LoaderUtils.toTable(raw.deck, {})
  return {
    version = math.max(1, math.floor(LoaderUtils.toNumber(raw.version, 1))),
    deck = {
      maxSize = math.max(1, math.floor(LoaderUtils.toNumber(deck.maxSize, DEFAULT_CAMPAIGN_RULES.deck.maxSize))),
      maxDuplicatePerCard = math.max(1, math.floor(LoaderUtils.toNumber(deck.maxDuplicatePerCard, DEFAULT_CAMPAIGN_RULES.deck.maxDuplicatePerCard))),
      drawPerBattle = math.max(1, math.floor(LoaderUtils.toNumber(deck.drawPerBattle, DEFAULT_CAMPAIGN_RULES.deck.drawPerBattle)))
    }
  }
end

return SingleDataLoader
