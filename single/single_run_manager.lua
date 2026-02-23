--[[
파일명: single_run_manager.lua
모듈명: SingleRunManager

역할:
- 싱글 런 상태(노드 진행/전투 결과)를 관리한다.
]]

local SingleRunManager = {}

local SingleDataLoader = require("single.single_data_loader")
local SingleStageGenerator = require("single.single_stage_generator")

local function buildFallbackNodes()
  local nodes = {}
  local typeList = { "mob", "mob", "boss" }
  for index = 1, #typeList do
    local nodeType = typeList[index]
    nodes[index] = {
      nodeId = string.format("s1_n%02d", index),
      stageIndex = 1,
      nodeIndex = index,
      type = nodeType,
      titleKey = "single.node." .. nodeType,
      fallbackTitleKo = (nodeType == "boss") and "보스 전투" or "잡몹 전투"
    }
  end
  return nodes
end

local function cloneTemplate(source)
  local copied = {}
  for key, value in pairs(source or {}) do
    if type(value) == "table" then
      local nested = {}
      for nestedKey, nestedValue in pairs(value) do
        if type(nestedValue) == "table" then
          local deepNested = {}
          for deepKey, deepValue in pairs(nestedValue) do
            deepNested[deepKey] = deepValue
          end
          nested[nestedKey] = deepNested
        else
          nested[nestedKey] = nestedValue
        end
      end
      copied[key] = nested
    else
      copied[key] = value
    end
  end
  return copied
end

local function findTemplate(templateList, templateId, stageIndex)
  if type(templateList) ~= "table" then
    return nil
  end

  local templateIdText = tostring(templateId or "template_a")
  local stageNumber = math.max(1, math.floor(tonumber(stageIndex) or 1))
  local firstTemplate = nil
  local stageMatchedTemplate = nil

  for _, template in ipairs(templateList) do
    if type(template) == "table" then
      firstTemplate = firstTemplate or template
      if tostring(template.templateId or "") == templateIdText then
        return template
      end
      if stageMatchedTemplate == nil and math.floor(tonumber(template.stageIndex) or 0) == stageNumber then
        stageMatchedTemplate = template
      end
    end
  end

  return stageMatchedTemplate or firstTemplate
end

function SingleRunManager.newRun(deckId, options)
  local optionTable = type(options) == "table" and options or {}
  local nowMs = os.time() * 1000
  local templateId = tostring(optionTable.templateId or "template_a")
  local stageIndex = math.max(1, math.floor(tonumber(optionTable.stageIndex) or 1))
  local rngSeed = tonumber(optionTable.rngSeed) or nowMs

  local nodes = buildFallbackNodes()
  local templateData = SingleDataLoader.loadSingleStageTemplates()
  local template = findTemplate(templateData and templateData.templates, templateId, stageIndex)
  if type(template) == "table" then
    local templateForBuild = cloneTemplate(template)
    templateForBuild.stageIndex = stageIndex
    local generated = SingleStageGenerator.generateNodes(templateForBuild, rngSeed)
    if type(generated) == "table" and #generated > 0 then
      nodes = generated
    end
  end

  return {
    runId = "run_" .. tostring(nowMs),
    deckId = tostring(deckId or "default"),
    templateId = templateId,
    stageIndex = stageIndex,
    rngSeed = rngSeed,
    nodes = nodes,
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
