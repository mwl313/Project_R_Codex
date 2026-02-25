--[[
파일명: runtime_relic_store.lua
모듈명: RuntimeRelicStore

역할:
- 싱글 웨이브 런 동안 생성된 절차 유물을 메모리에 저장/조회한다.
- 런 리셋/종료 시 clear()로 정리한다.
]]

local RuntimeRelicStore = {}

local relicById = {}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end
  local copied = {}
  for key, nestedValue in pairs(value) do
    copied[key] = deepCopy(nestedValue)
  end
  return copied
end

function RuntimeRelicStore.clear()
  relicById = {}
end

function RuntimeRelicStore.register(relicDef)
  if type(relicDef) ~= "table" then
    return false, "invalid_relic_def"
  end
  local relicId = tostring(relicDef.relicId or relicDef.id or "")
  if relicId == "" then
    return false, "invalid_relic_id"
  end

  local normalized = deepCopy(relicDef)
  normalized.relicId = relicId
  normalized.id = relicId
  normalized.tunables = type(normalized.tunables) == "table" and normalized.tunables or {}
  normalized.buffLines = type(normalized.buffLines) == "table" and normalized.buffLines or {}
  normalized.debuffLines = type(normalized.debuffLines) == "table" and normalized.debuffLines or {}
  normalized.meta = type(normalized.meta) == "table" and normalized.meta or {}
  relicById[relicId] = normalized
  return true, relicId
end

function RuntimeRelicStore.get(relicId)
  local key = tostring(relicId or "")
  if key == "" then
    return nil
  end
  local relic = relicById[key]
  if not relic then
    return nil
  end
  return deepCopy(relic)
end

function RuntimeRelicStore.listAll()
  local list = {}
  for _, relic in pairs(relicById) do
    list[#list + 1] = deepCopy(relic)
  end
  return list
end

return RuntimeRelicStore
