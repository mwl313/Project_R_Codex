--[[
파일명: map_templates_loader.lua
모듈명: MapTemplatesLoader
]]

local LoaderUtils = require("single.single_json_loader")

local MapTemplatesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  templates = {
    {
      templateId = "stage1_template",
      stageIndex = 1,
      nodeCount = 6,
      bossAtEnd = true,
      nodeWeights = {
        mob = 0.6,
        elite = 0.2,
        rest = 0.2,
        event = 0.0,
        shop = 0.0,
        deck_clean = 0.0
      }
    }
  }
}

local function sanitizeTemplate(entry)
  local source = LoaderUtils.toTable(entry, {})
  local nodeWeights = LoaderUtils.toTable(source.nodeWeights, {})
  return {
    templateId = LoaderUtils.toString(source.templateId, "template_unknown"),
    stageIndex = LoaderUtils.toNumber(source.stageIndex, 1),
    nodeCount = LoaderUtils.toNumber(source.nodeCount, 6),
    bossAtEnd = LoaderUtils.toBoolean(source.bossAtEnd, true),
    nodeWeights = {
      mob = LoaderUtils.toNumber(nodeWeights.mob, 0.6),
      elite = LoaderUtils.toNumber(nodeWeights.elite, 0.2),
      rest = LoaderUtils.toNumber(nodeWeights.rest, 0.2),
      event = LoaderUtils.toNumber(nodeWeights.event, 0.0),
      shop = LoaderUtils.toNumber(nodeWeights.shop, 0.0),
      deck_clean = LoaderUtils.toNumber(nodeWeights.deck_clean, 0.0)
    }
  }
end

local function sanitize(raw)
  local source = LoaderUtils.toTable(raw, {})
  local sanitized = {
    version = LoaderUtils.toNumber(source.version, DEFAULT_DATA.version),
    templates = {}
  }

  for _, entry in ipairs(LoaderUtils.toArray(source.templates, {})) do
    if type(entry) == "table" then
      sanitized.templates[#sanitized.templates + 1] = sanitizeTemplate(entry)
    end
  end

  if #sanitized.templates <= 0 then
    sanitized.templates = LoaderUtils.deepCopy(DEFAULT_DATA.templates)
  end
  return sanitized
end

function MapTemplatesLoader.load()
  local raw = LoaderUtils.readJson("shared/map_templates.json", "map_templates")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end
  return sanitize(raw)
end

return MapTemplatesLoader
