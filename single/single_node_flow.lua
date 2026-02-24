--[[
파일명: single_node_flow.lua
모듈명: SingleNodeFlow

역할:
- 비전투 노드(상점/휴식/덱정리/이벤트) 완료 후 공통 진행 처리를 담당한다.
]]

local Config = require("config")
local SingleRunManager = require("single.single_run_manager")

local SingleNodeFlow = {}

function SingleNodeFlow.completeNodeAndReturnMap(app, profile, runState)
  local nextNode = SingleRunManager.advanceDepth(runState)
  if nextNode then
    app:goScene("single_map", {
      backScene = "single_campaign",
      profile = profile,
      runState = runState
    }, Config.TRANSITION_FORWARD)
    return
  end

  runState.finished = true
  runState.isVictory = true
  app:goScene("single_result", {
    profile = profile,
    runState = runState,
    result = "win"
  }, Config.TRANSITION_FORWARD)
end

return SingleNodeFlow
