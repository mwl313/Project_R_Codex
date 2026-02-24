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

local function getNodeCountFromRun(runState)
  if type(runState) ~= "table" then
    return 0
  end
  if type(runState.nodes) == "table" then
    local nodeCount = #runState.nodes
    if nodeCount > 0 then
      return nodeCount
    end
  end
  if type(runState.choiceSets) == "table" then
    return #runState.choiceSets
  end
  return 0
end

local function getStoredChoicesAtDepth(runState, depth)
  if type(runState) ~= "table" then
    return {}
  end

  local index = math.max(1, math.floor(tonumber(depth) or 1))
  if type(runState.choiceSets) == "table" and type(runState.choiceSets[index]) == "table" and #runState.choiceSets[index] > 0 then
    return runState.choiceSets[index]
  end

  local nodes = type(runState.nodes) == "table" and runState.nodes or {}
  local node = nodes[index]
  if type(node) == "table" then
    return { node }
  end
  return {}
end

local function findNodeInChoices(choices, nodeId)
  local targetId = tostring(nodeId or "")
  for _, node in ipairs(choices or {}) do
    if type(node) == "table" and tostring(node.nodeId or "") == targetId then
      return node
    end
  end
  return nil
end

local function getSelectedOrDefaultFromStored(runState, depth)
  local choices = getStoredChoicesAtDepth(runState, depth)
  local selectedByDepth = type(runState.selectedByDepth) == "table" and runState.selectedByDepth or nil
  if selectedByDepth then
    local selectedId = selectedByDepth[depth]
    if selectedId then
      local selectedNode = findNodeInChoices(choices, selectedId)
      if selectedNode then
        return selectedNode
      end
    end
  end
  return choices[1]
end

local function buildChosenTypeCountBeforeDepth(runState, depth)
  local counts = {}
  local depthNumber = math.max(1, math.floor(tonumber(depth) or 1))
  for i = 1, depthNumber - 1 do
    local node = getSelectedOrDefaultFromStored(runState, i)
    if type(node) == "table" then
      local nodeType = tostring(node.type or "mob")
      counts[nodeType] = (counts[nodeType] or 0) + 1
    end
  end
  return counts
end

local function buildFallbackChoiceSetForDepth(runState, depth)
  local choices = getStoredChoicesAtDepth(runState, depth)
  if #choices > 0 then
    return choices
  end
  local stageIndex = math.max(1, math.floor(tonumber(runState and runState.stageIndex) or 1))
  local depthIndex = math.max(1, math.floor(tonumber(depth) or 1))
  return {
    {
      nodeId = string.format("s%d_d%02d_a", stageIndex, depthIndex),
      stageIndex = stageIndex,
      nodeIndex = depthIndex,
      type = "mob",
      titleKey = "single.node.mob",
      fallbackTitleKo = "잡몹 전투"
    }
  }
end

local function ensureChoiceSetForDepth(runState, depth)
  if type(runState) ~= "table" then
    return {}
  end

  local depthIndex = math.max(1, math.floor(tonumber(depth) or 1))
  runState.choiceSets = type(runState.choiceSets) == "table" and runState.choiceSets or {}
  local existingChoices = runState.choiceSets[depthIndex]
  if type(existingChoices) == "table" and #existingChoices > 0 then
    return existingChoices
  end

  local template = type(runState.templateForChoices) == "table" and runState.templateForChoices or nil
  local nodeCount = getNodeCountFromRun(runState)
  local linearNode = type(runState.nodes) == "table" and runState.nodes[depthIndex] or nil
  local mainType = (type(linearNode) == "table" and tostring(linearNode.type or "mob")) or "mob"

  if type(template) ~= "table" then
    local fallbackChoices = buildFallbackChoiceSetForDepth(runState, depthIndex)
    runState.choiceSets[depthIndex] = fallbackChoices
    return fallbackChoices
  end

  local chosenCountsBefore = buildChosenTypeCountBeforeDepth(runState, depthIndex)
  local generatedChoices = SingleStageGenerator.generateChoiceSetForDepth(
    template,
    depthIndex,
    runState.stageIndex,
    nodeCount,
    mainType,
    chosenCountsBefore,
    (tonumber(runState.rngSeed) or os.time()) + depthIndex * 131
  )

  if type(generatedChoices) ~= "table" or #generatedChoices <= 0 then
    generatedChoices = buildFallbackChoiceSetForDepth(runState, depthIndex)
  end

  runState.choiceSets[depthIndex] = generatedChoices
  return generatedChoices
end

local function getSelectedOrDefaultNode(runState, depth)
  local choices = ensureChoiceSetForDepth(runState, depth)
  local selectedByDepth = type(runState.selectedByDepth) == "table" and runState.selectedByDepth or nil
  if selectedByDepth then
    local selectedId = selectedByDepth[depth]
    if selectedId then
      local selectedNode = findNodeInChoices(choices, selectedId)
      if selectedNode then
        return selectedNode
      end
    end
  end

  local firstNode = choices[1]
  if firstNode and type(firstNode.nodeId) == "string" then
    runState.selectedByDepth = type(runState.selectedByDepth) == "table" and runState.selectedByDepth or {}
    runState.selectedByDepth[depth] = firstNode.nodeId
  end
  return firstNode
end

function SingleRunManager.newRun(deckId, options)
  local optionTable = type(options) == "table" and options or {}
  local nowMs = os.time() * 1000
  local templateId = tostring(optionTable.templateId or "template_a")
  local stageIndex = math.max(1, math.floor(tonumber(optionTable.stageIndex) or 1))
  local rngSeed = tonumber(optionTable.rngSeed) or nowMs

  local nodes = buildFallbackNodes()
  local templateForChoices = nil
  local templateData = SingleDataLoader.loadSingleStageTemplates()
  local template = findTemplate(templateData and templateData.templates, templateId, stageIndex)
  if type(template) == "table" then
    local templateForBuild = cloneTemplate(template)
    templateForBuild.stageIndex = stageIndex
    local generated = SingleStageGenerator.generateNodes(templateForBuild, rngSeed)
    if type(generated) == "table" and #generated > 0 then
      nodes = generated
      templateForChoices = cloneTemplate(templateForBuild)
    end
  end

  return {
    runId = "run_" .. tostring(nowMs),
    deckId = tostring(deckId or "default"),
    templateId = templateId,
    stageIndex = stageIndex,
    rngSeed = rngSeed,
    nodes = nodes,
    depthIndex = 1,
    choiceSets = {},
    selectedByDepth = {},
    templateForChoices = templateForChoices,
    currentNodeIndex = 1,
    gold = 0,
    cardUpgrades = {},
    tempModifiers = {},
    runtimeDeck = nil,
    lastCombatResult = nil,
    finished = false,
    isVictory = false
  }
end

function SingleRunManager.getNodeCount(runState)
  return getNodeCountFromRun(runState)
end

function SingleRunManager.getCurrentDepth(runState)
  if type(runState) ~= "table" then
    return 1
  end
  local nodeCount = math.max(1, getNodeCountFromRun(runState))
  local depth = math.floor(tonumber(runState.depthIndex) or tonumber(runState.currentNodeIndex) or 1)
  if depth < 1 then
    depth = 1
  elseif depth > nodeCount then
    depth = nodeCount
  end
  return depth
end

function SingleRunManager.getOrBuildChoicesForDepth(runState, depth)
  if type(runState) ~= "table" then
    return {}
  end
  local targetDepth = depth
  if targetDepth == nil then
    targetDepth = SingleRunManager.getCurrentDepth(runState)
  end
  return ensureChoiceSetForDepth(runState, targetDepth)
end

function SingleRunManager.getChoices(runState)
  local depth = SingleRunManager.getCurrentDepth(runState)
  return SingleRunManager.getOrBuildChoicesForDepth(runState, depth)
end

function SingleRunManager.selectChoice(runState, nodeId)
  if type(runState) ~= "table" or runState.finished == true then
    return false, "invalid_state"
  end
  local depth = SingleRunManager.getCurrentDepth(runState)
  local choices = ensureChoiceSetForDepth(runState, depth)
  local selectedNode = findNodeInChoices(choices, nodeId)
  if not selectedNode then
    return false, "choice_not_found"
  end

  if type(runState.templateForChoices) == "table" then
    local chosenCountsBefore = buildChosenTypeCountBeforeDepth(runState, depth)
    local feasible = SingleStageGenerator.isChoiceTypeFeasible(
      runState.templateForChoices,
      depth,
      getNodeCountFromRun(runState),
      chosenCountsBefore,
      selectedNode.type
    )
    if not feasible then
      runState.choiceSets[depth] = nil
      choices = ensureChoiceSetForDepth(runState, depth)
      selectedNode = findNodeInChoices(choices, nodeId) or choices[1]
      if not selectedNode then
        return false, "constraint_violation"
      end
    end
  end

  runState.selectedByDepth = type(runState.selectedByDepth) == "table" and runState.selectedByDepth or {}
  runState.selectedByDepth[depth] = tostring(selectedNode.nodeId)
  runState.depthIndex = depth
  runState.currentNodeIndex = depth
  return true
end

function SingleRunManager.getCurrentNode(runState)
  if type(runState) ~= "table" or runState.finished == true then
    return nil
  end

  local depth = SingleRunManager.getCurrentDepth(runState)
  local selectedNode = getSelectedOrDefaultNode(runState, depth)
  if type(selectedNode) == "table" then
    return selectedNode
  end

  local nodes = type(runState.nodes) == "table" and runState.nodes or {}
  return nodes[depth]
end

function SingleRunManager.advanceDepth(runState)
  if type(runState) ~= "table" then
    return nil
  end

  local nodeCount = getNodeCountFromRun(runState)
  local nextDepth = SingleRunManager.getCurrentDepth(runState) + 1
  runState.depthIndex = nextDepth
  runState.currentNodeIndex = nextDepth
  if nextDepth > nodeCount then
    runState.finished = true
    return nil
  end

  ensureChoiceSetForDepth(runState, nextDepth)
  return SingleRunManager.getCurrentNode(runState)
end

function SingleRunManager.advanceNode(runState)
  if type(runState) ~= "table" then
    return nil
  end

  if type(runState.choiceSets) == "table" and #runState.choiceSets > 0 then
    return SingleRunManager.advanceDepth(runState)
  end

  local nodes = type(runState.nodes) == "table" and runState.nodes or {}
  local nextIndex = math.max(1, math.floor(tonumber(runState.currentNodeIndex) or 1) + 1)
  runState.currentNodeIndex = nextIndex
  runState.depthIndex = nextIndex
  if nextIndex > #nodes then
    runState.finished = true
    return nil
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
