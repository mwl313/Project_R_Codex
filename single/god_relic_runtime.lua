--[[
파일명: god_relic_runtime.lua
모듈명: GodRelicRuntime

역할:
- 싱글 웨이브 런타임에서 갓 유물 스택(SSOT: runState.godRelicCounts)을 관리한다.
- 갓 유물 UI 표시용 라인 생성 유틸을 제공한다.
]]

local GodRelicDefs = require("single.god_relic_defs")

local GodRelicRuntime = {}

local function toNonNegativeInt(value)
  local numberValue = tonumber(value)
  if type(numberValue) ~= "number" or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
    return 0
  end
  return math.max(0, math.floor(numberValue))
end

function GodRelicRuntime.initRunState(runState)
  if type(runState) ~= "table" then
    return
  end
  if type(runState.godRelicCounts) ~= "table" then
    runState.godRelicCounts = {}
  end
  if type(runState.godRelicIds) ~= "table" then
    runState.godRelicIds = {}
  end
end

function GodRelicRuntime.clear(runState)
  if type(runState) ~= "table" then
    return
  end
  runState.godRelicCounts = {}
  runState.godRelicIds = {}
end

function GodRelicRuntime.getCount(runState, godRelicId)
  if type(runState) ~= "table" or type(runState.godRelicCounts) ~= "table" then
    return 0
  end
  local key = tostring(godRelicId or "")
  if key == "" then
    return 0
  end
  return toNonNegativeInt(runState.godRelicCounts[key])
end

function GodRelicRuntime.addGodRelic(runState, godRelicId)
  if type(runState) ~= "table" then
    return false, 0
  end
  GodRelicRuntime.initRunState(runState)
  local key = tostring(godRelicId or "")
  if key == "" or not GodRelicDefs.getById(key) then
    return false, 0
  end

  local nextCount = toNonNegativeInt(runState.godRelicCounts[key]) + 1
  runState.godRelicCounts[key] = nextCount
  runState.godRelicIds[#runState.godRelicIds + 1] = key
  return true, nextCount
end

function GodRelicRuntime.toUiLines(runState)
  GodRelicRuntime.initRunState(runState)
  local lineList = {}
  local counts = runState.godRelicCounts

  local function append(lineText)
    lineList[#lineList + 1] = tostring(lineText)
  end

  for _, relic in ipairs(GodRelicDefs.LIST) do
    local count = toNonNegativeInt(counts[relic.id])
    if count > 0 then
      if relic.id == GodRelicDefs.ID_ACTION_POWER then
        append(string.format("[GOD] %s +%d", relic.nameKo, count * math.max(1, toNonNegativeInt(relic.perStack))))
      elseif relic.id == GodRelicDefs.ID_INFINITE_POWER then
        append(string.format("[GOD] %s: 매턴 드로우 %d", relic.nameKo, count * math.max(1, toNonNegativeInt(relic.perStack))))
      elseif relic.id == GodRelicDefs.ID_SAFETY then
        append(string.format("[GOD] %s: ON", relic.nameKo))
      elseif relic.id == GodRelicDefs.ID_PRECISION_CONTROL then
        append(string.format("[GOD] %s: 반사선 %d차", relic.nameKo, count * math.max(1, toNonNegativeInt(relic.perStack))))
      elseif relic.id == GodRelicDefs.ID_PIERCING_SHOT then
        append(string.format("[GOD] %s: 턴당 %d회", relic.nameKo, count * math.max(1, toNonNegativeInt(relic.perStack))))
      else
        append(string.format("[GOD] %s x%d", relic.nameKo or relic.id, count))
      end
    end
  end

  return lineList
end

return GodRelicRuntime
