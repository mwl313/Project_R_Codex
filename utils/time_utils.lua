--[[
파일명: time_utils.lua
모듈명: TimeUtils

역할:
- epoch(ms) 기준 현재 시간/잔여 시간 계산을 공통화한다.
- 서버(Date.now epoch ms)와 클라(love.timer monotonic sec) 기준 불일치를 흡수한다.

외부에서 사용 가능한 함수:
- TimeUtils.nowEpochMs()
- TimeUtils.getRemainingSeconds(endsAtMs)
]]

local TimeUtils = {}

local function getMonotonicMs()
  if love and love.timer and love.timer.getTime then
    local isOk, value = pcall(love.timer.getTime)
    if isOk and type(value) == "number" and value == value then
      return value * 1000
    end
  end
  local clockValue = os.clock()
  if type(clockValue) == "number" and clockValue == clockValue then
    return clockValue * 1000
  end
  return nil
end

-- Anchor monotonic clock to unix epoch once, then use monotonic delta.
-- This keeps ms precision while matching server epoch-based timers.
local initialMonotonicMs = getMonotonicMs() or 0
local epochOffsetMs = os.time() * 1000 - initialMonotonicMs

function TimeUtils.nowEpochMs()
  local monotonicMs = getMonotonicMs()
  if monotonicMs then
    return math.floor(epochOffsetMs + monotonicMs)
  end
  return math.floor(os.time() * 1000)
end

function TimeUtils.getRemainingSeconds(endsAtMs)
  if type(endsAtMs) ~= "number" or endsAtMs ~= endsAtMs then
    return 0
  end
  local remainingMs = endsAtMs - TimeUtils.nowEpochMs()
  return math.max(0, math.ceil(remainingMs / 1000))
end

return TimeUtils
