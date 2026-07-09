--[[
파일명: match_history.lua
모듈명: MatchHistory

역할:
- 대전 결과를 로컬 love.filesystem에 저장하고 조회한다.
- 최대 50경기 FIFO 보관
- stats(승/패/승률/캐릭터별)는 records에서 실시간 계산

외부에서 사용 가능한 함수:
- MatchHistory.load() → records[], stats
- MatchHistory.save(record) → void
- MatchHistory.getRecent(n) → records[]
- MatchHistory.getStats() → stats

주의:
- love.filesystem 접근은 pcall로 감싸서 실패해도 크래시 방지
]]

local Json = require("utils.json")

local MatchHistory = {}

local MAX_RECORDS = 50

local function getFilePath()
  return love.filesystem.getSaveDirectory() .. "/match_history.json"
end

--- records와 stats를 파일에서 읽어온다.
--- @return table[] records, table stats
function MatchHistory.load()
  local ok, data = pcall(function()
    return love.filesystem.read("match_history.json")
  end)
  if not ok or not data or data == "" then
    return {}, MatchHistory.getStatsForRecords({})
  end

  local okParse, parsed = pcall(Json.decode, data)
  if not okParse or type(parsed) ~= "table" then
    return {}, MatchHistory.getStatsForRecords({})
  end

  local records = type(parsed.records) == "table" and parsed.records or {}
  return records, MatchHistory.getStatsForRecords(records)
end

--- records 배열로부터 stats를 계산한다.
--- @param table[] records
--- @return table stats
function MatchHistory.getStatsForRecords(records)
  local totalGames = #records
  local wins = 0
  local losses = 0
  local characterStats = {}

  for _, record in ipairs(records) do
    if record.result == "win" then
      wins = wins + 1
    elseif record.result == "loss" then
      losses = losses + 1
    end

    local charId = record.myCharacter
    if charId and charId ~= "" then
      if not characterStats[charId] then
        characterStats[charId] = { played = 0, wins = 0 }
      end
      characterStats[charId].played = characterStats[charId].played + 1
      if record.result == "win" then
        characterStats[charId].wins = characterStats[charId].wins + 1
      end
    end
  end

  local winRate = totalGames > 0 and (wins / totalGames) or 0

  return {
    totalGames = totalGames,
    wins = wins,
    losses = losses,
    winRate = winRate,
    characterStats = characterStats
  }
end

--- 새 경기 기록을 저장한다.
--- @param table record
function MatchHistory.save(record)
  local records = MatchHistory.load()

  -- 최신 기록을 앞에 추가
  table.insert(records, 1, record)

  -- 최대 50경기 유지
  while #records > MAX_RECORDS do
    table.remove(records)
  end

  local data = Json.encode({
    records = records
  })

  local ok, err = pcall(function()
    love.filesystem.write("match_history.json", data)
  end)
  if not ok then
    -- 저장 실패는 무시 (비로그인/샌드박스 환경 대응)
  end
end

--- 최근 n경기를 반환한다.
--- @param number n
--- @return table[]
function MatchHistory.getRecent(n)
  local records = MatchHistory.load()
  local count = math.min(n or 10, #records)
  local result = {}
  for i = 1, count do
    result[i] = records[i]
  end
  return result
end

--- 통계를 반환한다.
--- @return table stats
function MatchHistory.getStats()
  local records = MatchHistory.load()
  return MatchHistory.getStatsForRecords(records)
end

return MatchHistory
