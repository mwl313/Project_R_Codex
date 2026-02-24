--[[
파일명: event_tables_loader.lua
모듈명: EventTablesLoader

역할:
- 싱글 이벤트 테이블(shared/event_tables.json)을 안전하게 로드/정규화한다.
]]

local LoaderUtils = require("single.single_json_loader")

local EventTablesLoader = {}

local DEFAULT_DATA = {
  version = 1,
  events = {
    {
      eventId = "event_gold_or_draw_penalty",
      weight = 1.0,
      titleKey = "single.event.table.event_gold_or_draw_penalty.title",
      descKey = "single.event.table.event_gold_or_draw_penalty.desc",
      choices = {
        {
          choiceId = "gain_gold",
          labelKey = "single.event.table.event_gold_or_draw_penalty.choice_gain_gold",
          outcome = { type = "gain_gold", amount = 30 }
        },
        {
          choiceId = "lose_draw",
          labelKey = "single.event.table.event_gold_or_draw_penalty.choice_lose_draw",
          outcome = { type = "temp_modifier", key = "nextCombatDrawDelta", value = -1 }
        }
      }
    }
  }
}

local function sanitizeChoice(rawChoice)
  local source = LoaderUtils.toTable(rawChoice, {})
  local outcome = LoaderUtils.toTable(source.outcome, {})
  return {
    choiceId = LoaderUtils.toString(source.choiceId, "choice"),
    labelKey = LoaderUtils.toString(source.labelKey, "single.event.choice.unknown"),
    outcome = {
      type = LoaderUtils.toString(outcome.type, "none"),
      amount = LoaderUtils.toNumber(outcome.amount, nil),
      count = LoaderUtils.toNumber(outcome.count, nil),
      cost = LoaderUtils.toNumber(outcome.cost, nil),
      key = LoaderUtils.toString(outcome.key, nil),
      value = LoaderUtils.toNumber(outcome.value, nil),
      nodeType = LoaderUtils.toString(outcome.nodeType, nil)
    }
  }
end

local function sanitizeEvent(rawEvent)
  local source = LoaderUtils.toTable(rawEvent, {})
  local choiceList = {}
  for _, rawChoice in ipairs(LoaderUtils.toArray(source.choices, {})) do
    if type(rawChoice) == "table" then
      choiceList[#choiceList + 1] = sanitizeChoice(rawChoice)
    end
  end
  if #choiceList < 2 then
    return nil
  end
  return {
    eventId = LoaderUtils.toString(source.eventId, "event_unknown"),
    weight = math.max(0.01, LoaderUtils.toNumber(source.weight, 1.0)),
    titleKey = LoaderUtils.toString(source.titleKey, "single.event.title"),
    descKey = LoaderUtils.toString(source.descKey, "single.event.desc"),
    choices = choiceList
  }
end

function EventTablesLoader.load()
  local raw = LoaderUtils.readJson("shared/event_tables.json", "event_tables")
  if type(raw) ~= "table" then
    return LoaderUtils.deepCopy(DEFAULT_DATA)
  end

  local sanitized = {
    version = LoaderUtils.toNumber(raw.version, DEFAULT_DATA.version),
    events = {}
  }
  for _, rawEvent in ipairs(LoaderUtils.toArray(raw.events, {})) do
    if type(rawEvent) == "table" then
      local eventDef = sanitizeEvent(rawEvent)
      if eventDef then
        sanitized.events[#sanitized.events + 1] = eventDef
      end
    end
  end

  if #sanitized.events <= 0 then
    sanitized.events = LoaderUtils.deepCopy(DEFAULT_DATA.events)
  end
  return sanitized
end

return EventTablesLoader
