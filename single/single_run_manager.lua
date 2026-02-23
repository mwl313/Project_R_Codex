--[[
파일명: single_run_manager.lua
모듈명: SingleRunManager

역할:
- 싱글 런 상태(노드 진행/전투 결과)를 관리한다.
]]

local SingleRunManager = {}

local NODE_TEMPLATE_LIST = {
  { nodeId = "node_1", type = "combat", titleKo = "1단계 전투" },
  { nodeId = "node_2", type = "combat", titleKo = "2단계 전투" },
  { nodeId = "node_3", type = "boss", titleKo = "보스 전투" }
}

local function cloneNodes()
  local nodes = {}
  for _, node in ipairs(NODE_TEMPLATE_LIST) do
    nodes[#nodes + 1] = {
      nodeId = node.nodeId,
      type = node.type,
      titleKo = node.titleKo
    }
  end
  return nodes
end

function SingleRunManager.newRun(deckId)
  local nowMs = os.time() * 1000
  return {
    runId = "run_" .. tostring(nowMs),
    deckId = tostring(deckId or "default"),
    nodes = cloneNodes(),
    currentNodeIndex = 1,
    lastCombatResult = nil,
    finished = false,
    isVictory = false
  }
end

function SingleRunManager.getCurrentNode(runState)
  if type(runState) ~= "table" or runState.finished == true then
    return nil
  end
  local index = math.max(1, math.floor(tonumber(runState.currentNodeIndex) or 1))
  local nodes = type(runState.nodes) == "table" and runState.nodes or {}
  return nodes[index]
end

function SingleRunManager.advanceNode(runState)
  if type(runState) ~= "table" then
    return nil
  end
  local nodes = type(runState.nodes) == "table" and runState.nodes or {}
  local nextIndex = math.max(1, math.floor(tonumber(runState.currentNodeIndex) or 1) + 1)
  runState.currentNodeIndex = nextIndex
  if nextIndex > #nodes then
    runState.finished = true
  end
  return SingleRunManager.getCurrentNode(runState)
end

function SingleRunManager.setCombatResult(runState, result)
  if type(runState) ~= "table" then
    return
  end
  local normalized = tostring(result or "")
  if normalized ~= "win" and normalized ~= "lose" then
    normalized = "lose"
  end
  runState.lastCombatResult = normalized
  if normalized == "lose" then
    runState.finished = true
    runState.isVictory = false
  end
end

return SingleRunManager
