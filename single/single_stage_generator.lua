--[[
파일명: single_stage_generator.lua
모듈명: SingleStageGenerator

역할:
- SP-01.5 템플릿 기반으로 스테이지 노드 리스트를 생성한다.
- 제약 충돌 시 안전한 3노드 폴백([mob, mob, boss])을 반환한다.
]]

local SingleStageGenerator = {}

local ALL_NODE_TYPES = {
  "mob",
  "elite",
  "boss",
  "shop",
  "rest",
  "deck_clean",
  "event"
}

local TITLE_KEY_BY_TYPE = {
  mob = "single.node.mob",
  elite = "single.node.elite",
  boss = "single.node.boss",
  shop = "single.node.shop",
  rest = "single.node.rest",
  deck_clean = "single.node.deck_clean",
  event = "single.node.event"
}

local FALLBACK_TITLE_KO_BY_TYPE = {
  mob = "잡몹 전투",
  elite = "엘리트 전투",
  boss = "보스 전투",
  shop = "상점",
  rest = "휴식",
  deck_clean = "덱 정리",
  event = "이벤트"
}

local MIN_LIMIT_KEY_BY_TYPE = {
  elite = "eliteMin",
  shop = "shopMin",
  deck_clean = "deckCleanMin",
  event = "eventMin"
}

local MAX_LIMIT_KEY_BY_TYPE = {
  elite = "eliteMax",
  shop = "shopMax",
  deck_clean = "deckCleanMax",
  event = "eventMax"
}

local CHOICE_ALT_TYPES = {
  "mob",
  "elite",
  "shop",
  "deck_clean",
  "event"
}

local REQUIRED_DECISION_TYPES = {
  "elite",
  "shop",
  "deck_clean",
  "event"
}

local function createRand(seed)
  local resolvedSeed = tonumber(seed) or os.time()
  if love and love.math and type(love.math.newRandomGenerator) == "function" then
    local rng = love.math.newRandomGenerator(resolvedSeed)
    return function(minValue, maxValue)
      if minValue and maxValue then
        return rng:random(minValue, maxValue)
      end
      return rng:random()
    end
  end

  math.randomseed(resolvedSeed)
  return function(minValue, maxValue)
    if minValue and maxValue then
      return math.random(minValue, maxValue)
    end
    return math.random()
  end
end

local function fallbackNodes(stageIndex)
  local resolvedStage = math.max(1, math.floor(tonumber(stageIndex) or 1))
  local typeList = { "mob", "mob", "boss" }
  local nodes = {}
  for i = 1, #typeList do
    local nodeType = typeList[i]
    nodes[i] = {
      nodeId = string.format("s%d_n%02d", resolvedStage, i),
      stageIndex = resolvedStage,
      nodeIndex = i,
      type = nodeType,
      titleKey = TITLE_KEY_BY_TYPE[nodeType],
      fallbackTitleKo = FALLBACK_TITLE_KO_BY_TYPE[nodeType]
    }
  end
  return nodes
end

local function inSet(setTable, value)
  return type(setTable) == "table" and setTable[value] == true
end

local function violatesBackToBack(prevType, nextType, backToBackSet)
  if type(prevType) ~= "string" or type(nextType) ~= "string" then
    return false
  end
  return inSet(backToBackSet, prevType) and inSet(backToBackSet, nextType)
end

local function weightedOrder(candidates, weightByType, rand, minCounts, currentCounts)
  local pool = {}
  for _, value in ipairs(candidates) do
    pool[#pool + 1] = value
  end

  local ordered = {}
  while #pool > 0 do
    local totalWeight = 0
    local weightList = {}
    for index, nodeType in ipairs(pool) do
      local baseWeight = tonumber(weightByType[nodeType]) or 0
      if baseWeight < 0 then
        baseWeight = 0
      end
      local current = tonumber(currentCounts[nodeType]) or 0
      local minValue = tonumber(minCounts[nodeType]) or 0
      if current < minValue then
        baseWeight = baseWeight + 2.0
      end
      if baseWeight <= 0 then
        baseWeight = 0.0001
      end
      weightList[index] = baseWeight
      totalWeight = totalWeight + baseWeight
    end

    local selectedIndex = 1
    if totalWeight > 0 then
      local pick = rand() * totalWeight
      local accum = 0
      for index, w in ipairs(weightList) do
        accum = accum + w
        if pick <= accum then
          selectedIndex = index
          break
        end
      end
    else
      selectedIndex = rand(1, #pool)
    end

    ordered[#ordered + 1] = pool[selectedIndex]
    table.remove(pool, selectedIndex)
  end
  return ordered
end

local function buildNode(stageIndex, depthIndex, slotCode, nodeType)
  local resolvedType = tostring(nodeType or "mob")
  return {
    nodeId = string.format("s%d_d%02d_%s", stageIndex, depthIndex, tostring(slotCode or "a")),
    stageIndex = stageIndex,
    nodeIndex = depthIndex,
    type = resolvedType,
    titleKey = TITLE_KEY_BY_TYPE[resolvedType] or "single.node.mob",
    fallbackTitleKo = FALLBACK_TITLE_KO_BY_TYPE[resolvedType] or FALLBACK_TITLE_KO_BY_TYPE.mob
  }
end

local function shuffleArray(valueList, rand)
  local shuffled = {}
  for _, value in ipairs(valueList) do
    shuffled[#shuffled + 1] = value
  end
  for index = #shuffled, 2, -1 do
    local swapIndex = rand(1, index)
    shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
  end
  return shuffled
end

local function pickAlternativeType(mainType, pickedTypes, rand)
  local shuffled = shuffleArray(CHOICE_ALT_TYPES, rand)

  for _, nodeType in ipairs(shuffled) do
    if nodeType ~= mainType and pickedTypes[nodeType] ~= 2 then
      return nodeType
    end
  end
  for _, nodeType in ipairs(shuffled) do
    if nodeType ~= mainType then
      return nodeType
    end
  end
  return "mob"
end

local function getDecisionDepthEnd(nodeCount, bossAtEnd, restBeforeBoss)
  local reservedCount = 0
  if bossAtEnd then
    reservedCount = reservedCount + 1
  end
  if restBeforeBoss then
    reservedCount = reservedCount + 1
  end
  return math.max(1, nodeCount - reservedCount)
end

local function buildChoiceLimitTable(template, nodeCount)
  local limits = type(template.limits) == "table" and template.limits or {}
  return {
    mob = {
      min = 0,
      max = nodeCount
    },
    elite = {
      min = math.max(0, math.floor(tonumber(limits.eliteMin) or 0)),
      max = math.max(0, math.floor(tonumber(limits.eliteMax) or nodeCount))
    },
    shop = {
      min = math.max(0, math.floor(tonumber(limits.shopMin) or 0)),
      max = math.max(0, math.floor(tonumber(limits.shopMax) or nodeCount))
    },
    deck_clean = {
      min = math.max(0, math.floor(tonumber(limits.deckCleanMin) or 0)),
      max = math.max(0, math.floor(tonumber(limits.deckCleanMax) or nodeCount))
    },
    event = {
      min = math.max(0, math.floor(tonumber(limits.eventMin) or 0)),
      max = math.max(0, math.floor(tonumber(limits.eventMax) or nodeCount))
    }
  }
end

local function cloneCountTable(source)
  local copied = {}
  for key, value in pairs(source or {}) do
    copied[key] = math.max(0, math.floor(tonumber(value) or 0))
  end
  return copied
end

local function getMissingCount(limitTable, chosenCounts, nodeType)
  local limit = limitTable[nodeType]
  if type(limit) ~= "table" then
    return 0
  end
  local selected = tonumber(chosenCounts[nodeType]) or 0
  return math.max(0, (tonumber(limit.min) or 0) - selected)
end

function SingleStageGenerator.isChoiceTypeFeasible(template, depthIndex, nodeCount, chosenCountsBefore, candidateType)
  local source = type(template) == "table" and template or {}
  local depth = math.max(1, math.floor(tonumber(depthIndex) or 1))
  local totalNodeCount = math.max(3, math.floor(tonumber(nodeCount) or 10))
  local bossAtEnd = source.bossAtEnd ~= false
  local restBeforeBoss = source.restBeforeBoss == true
  local decisionDepthEnd = getDecisionDepthEnd(totalNodeCount, bossAtEnd, restBeforeBoss)

  local choiceType = tostring(candidateType or "mob")

  if bossAtEnd and depth == totalNodeCount then
    return choiceType == "boss"
  end
  if restBeforeBoss and depth == (totalNodeCount - 1) then
    return choiceType == "rest"
  end
  if depth > decisionDepthEnd then
    return false
  end

  local isAllowedType = false
  for _, nodeType in ipairs(CHOICE_ALT_TYPES) do
    if nodeType == choiceType then
      isAllowedType = true
      break
    end
  end
  if not isAllowedType then
    return false
  end

  local limitTable = buildChoiceLimitTable(source, totalNodeCount)
  local chosenAfter = cloneCountTable(chosenCountsBefore)
  chosenAfter[choiceType] = (chosenAfter[choiceType] or 0) + 1

  local candidateLimit = limitTable[choiceType]
  if type(candidateLimit) == "table" then
    local maxValue = math.max(0, math.floor(tonumber(candidateLimit.max) or totalNodeCount))
    if (chosenAfter[choiceType] or 0) > maxValue then
      return false
    end
  end

  local remainingDepthCount = decisionDepthEnd - depth
  local remainingNeedSum = 0
  for _, requiredType in ipairs(REQUIRED_DECISION_TYPES) do
    local needed = getMissingCount(limitTable, chosenAfter, requiredType)
    if needed > remainingDepthCount then
      return false
    end
    remainingNeedSum = remainingNeedSum + needed
  end

  if remainingNeedSum > remainingDepthCount then
    return false
  end
  return true
end

function SingleStageGenerator.generateChoiceSetForDepth(template, depthIndex, stageIndex, nodeCount, mainType, chosenCountsBefore, rngSeed)
  local source = type(template) == "table" and template or {}
  local resolvedStage = math.max(1, math.floor(tonumber(stageIndex) or tonumber(source.stageIndex) or 1))
  local depth = math.max(1, math.floor(tonumber(depthIndex) or 1))
  local totalNodeCount = math.max(3, math.floor(tonumber(nodeCount) or tonumber(source.nodeCount) or 10))
  local bossAtEnd = source.bossAtEnd ~= false
  local restBeforeBoss = source.restBeforeBoss == true
  local decisionDepthEnd = getDecisionDepthEnd(totalNodeCount, bossAtEnd, restBeforeBoss)
  local selectedCounts = cloneCountTable(chosenCountsBefore)
  local rand = createRand((tonumber(rngSeed) or os.time()) + depth * 7919)

  if bossAtEnd and depth == totalNodeCount then
    return {
      buildNode(resolvedStage, depth, "a", "boss")
    }
  end
  if restBeforeBoss and depth == (totalNodeCount - 1) then
    return {
      buildNode(resolvedStage, depth, "a", "rest")
    }
  end
  if depth > decisionDepthEnd then
    return {
      buildNode(resolvedStage, depth, "a", "mob")
    }
  end

  local feasibleTypeList = {}
  for _, nodeType in ipairs(CHOICE_ALT_TYPES) do
    if SingleStageGenerator.isChoiceTypeFeasible(source, depth, totalNodeCount, selectedCounts, nodeType) then
      feasibleTypeList[#feasibleTypeList + 1] = nodeType
    end
  end
  if #feasibleTypeList <= 0 then
    if SingleStageGenerator.isChoiceTypeFeasible(source, depth, totalNodeCount, selectedCounts, "mob") then
      feasibleTypeList[1] = "mob"
    else
      feasibleTypeList[1] = "event"
    end
  end

  local primaryType = tostring(mainType or "mob")
  if primaryType == "boss" or primaryType == "rest" then
    primaryType = "mob"
  end

  local isPrimaryFeasible = false
  for _, nodeType in ipairs(feasibleTypeList) do
    if nodeType == primaryType then
      isPrimaryFeasible = true
      break
    end
  end
  if not isPrimaryFeasible then
    if SingleStageGenerator.isChoiceTypeFeasible(source, depth, totalNodeCount, selectedCounts, "mob") then
      primaryType = "mob"
    else
      primaryType = feasibleTypeList[1]
    end
  end

  table.sort(feasibleTypeList, function(aType, bType)
    local aNeed = getMissingCount(buildChoiceLimitTable(source, totalNodeCount), selectedCounts, aType)
    local bNeed = getMissingCount(buildChoiceLimitTable(source, totalNodeCount), selectedCounts, bType)
    if aNeed == bNeed then
      return aType < bType
    end
    return aNeed > bNeed
  end)

  local selectedTypes = { primaryType }
  local usedTypeMap = { [primaryType] = true }

  local shuffledFeasible = shuffleArray(feasibleTypeList, rand)
  table.sort(shuffledFeasible, function(aType, bType)
    local aNeed = getMissingCount(buildChoiceLimitTable(source, totalNodeCount), selectedCounts, aType)
    local bNeed = getMissingCount(buildChoiceLimitTable(source, totalNodeCount), selectedCounts, bType)
    if aNeed == bNeed then
      return aType < bType
    end
    return aNeed > bNeed
  end)

  for _, nodeType in ipairs(shuffledFeasible) do
    if #selectedTypes >= 3 then
      break
    end
    if not usedTypeMap[nodeType] then
      selectedTypes[#selectedTypes + 1] = nodeType
      usedTypeMap[nodeType] = true
    end
  end

  local mobFeasible = SingleStageGenerator.isChoiceTypeFeasible(source, depth, totalNodeCount, selectedCounts, "mob")
  while #selectedTypes < 3 do
    if mobFeasible then
      selectedTypes[#selectedTypes + 1] = "mob"
    else
      selectedTypes[#selectedTypes + 1] = selectedTypes[1]
    end
  end

  return {
    buildNode(resolvedStage, depth, "a", selectedTypes[1]),
    buildNode(resolvedStage, depth, "b", selectedTypes[2]),
    buildNode(resolvedStage, depth, "c", selectedTypes[3])
  }
end

function SingleStageGenerator.generateChoiceSets(template, rngSeed, linearNodes)
  local source = type(template) == "table" and template or {}
  local resolvedStage = math.max(1, math.floor(tonumber(source.stageIndex) or 1))
  local baseNodes = type(linearNodes) == "table" and linearNodes or SingleStageGenerator.generateNodes(source, rngSeed)
  if type(baseNodes) ~= "table" or #baseNodes <= 0 then
    baseNodes = fallbackNodes(resolvedStage)
  end

  local nodeCount = #baseNodes
  local choiceSets = {}
  local chosenCounts = {}

  for depth = 1, nodeCount do
    local mainNode = baseNodes[depth]
    local mainType = (type(mainNode) == "table" and mainNode.type) or "mob"
    local choices = SingleStageGenerator.generateChoiceSetForDepth(
      source,
      depth,
      resolvedStage,
      nodeCount,
      mainType,
      chosenCounts,
      (tonumber(rngSeed) or os.time()) + depth * 97
    )
    choiceSets[depth] = choices

    local selectedNode = choices[1]
    if type(selectedNode) == "table" then
      local selectedType = tostring(selectedNode.type or "mob")
      chosenCounts[selectedType] = (chosenCounts[selectedType] or 0) + 1
    end
  end

  return choiceSets
end

function SingleStageGenerator.generateNodes(template, rngSeed)
  local source = type(template) == "table" and template or nil
  if not source then
    return fallbackNodes(1)
  end

  local stageIndex = math.max(1, math.floor(tonumber(source.stageIndex) or 1))
  local nodeCount = math.max(3, math.floor(tonumber(source.nodeCount) or 10))
  local bossAtEnd = source.bossAtEnd ~= false
  local restBeforeBoss = source.restBeforeBoss == true
  local weights = type(source.weights) == "table" and source.weights or {}
  local limits = type(source.limits) == "table" and source.limits or {}
  local constraints = type(source.constraints) == "table" and source.constraints or {}

  local noSameTypeStreak = math.max(2, math.floor(tonumber(constraints.noSameTypeStreak) or 3))
  local backToBackSet = {}
  if type(constraints.noBackToBack) == "table" then
    for _, value in ipairs(constraints.noBackToBack) do
      if type(value) == "string" and value ~= "" then
        backToBackSet[value] = true
      end
    end
  end

  local rand = createRand(rngSeed)
  local resolvedTypeByIndex = {}
  local currentCounts = {}
  for _, nodeType in ipairs(ALL_NODE_TYPES) do
    currentCounts[nodeType] = 0
  end

  if bossAtEnd then
    resolvedTypeByIndex[nodeCount] = "boss"
    currentCounts.boss = 1
  end
  if restBeforeBoss and nodeCount >= 2 then
    resolvedTypeByIndex[nodeCount - 1] = "rest"
    currentCounts.rest = currentCounts.rest + 1
  end

  local minCounts = {}
  local maxCounts = {}
  for _, nodeType in ipairs(ALL_NODE_TYPES) do
    local minKey = MIN_LIMIT_KEY_BY_TYPE[nodeType]
    local maxKey = MAX_LIMIT_KEY_BY_TYPE[nodeType]
    local minValue = minKey and math.max(0, math.floor(tonumber(limits[minKey]) or 0)) or 0
    local maxValue = maxKey and math.max(0, math.floor(tonumber(limits[maxKey]) or nodeCount)) or nodeCount

    if nodeType == "boss" and bossAtEnd then
      minValue = math.max(minValue, 1)
      maxValue = 1
    end
    if nodeType == "rest" and restBeforeBoss then
      minValue = math.max(minValue, 1)
    end

    minCounts[nodeType] = minValue
    maxCounts[nodeType] = math.max(minValue, maxValue)
  end

  for _, nodeType in ipairs(ALL_NODE_TYPES) do
    local fixedCount = currentCounts[nodeType] or 0
    if fixedCount > maxCounts[nodeType] then
      return fallbackNodes(stageIndex)
    end
  end

  local variableIndexList = {}
  for index = 1, nodeCount do
    if resolvedTypeByIndex[index] == nil then
      variableIndexList[#variableIndexList + 1] = index
    end
  end

  local function remainingRequiredAfter(counts, nextSlotCount)
    local required = 0
    for _, nodeType in ipairs(ALL_NODE_TYPES) do
      local need = math.max(0, (minCounts[nodeType] or 0) - (counts[nodeType] or 0))
      required = required + need
    end
    return required <= nextSlotCount
  end

  local function wouldViolateStreak(index, nodeType)
    local streak = 1
    local cursor = index - 1
    while cursor >= 1 and resolvedTypeByIndex[cursor] == nodeType do
      streak = streak + 1
      cursor = cursor - 1
    end
    return streak >= noSameTypeStreak
  end

  local function canPlace(index, nodeType)
    if (currentCounts[nodeType] or 0) + 1 > (maxCounts[nodeType] or nodeCount) then
      return false
    end

    local prevType = resolvedTypeByIndex[index - 1]
    if violatesBackToBack(prevType, nodeType, backToBackSet) then
      return false
    end
    if wouldViolateStreak(index, nodeType) then
      return false
    end

    local nextFixedType = resolvedTypeByIndex[index + 1]
    if nextFixedType then
      if violatesBackToBack(nodeType, nextFixedType, backToBackSet) then
        return false
      end
      if nextFixedType == nodeType then
        local streak = 1
        local cursor = index - 1
        while cursor >= 1 and resolvedTypeByIndex[cursor] == nodeType do
          streak = streak + 1
          cursor = cursor - 1
        end
        if (streak + 1) >= noSameTypeStreak then
          return false
        end
      end
    end

    return true
  end

  local function solve(position)
    if position > #variableIndexList then
      for _, nodeType in ipairs(ALL_NODE_TYPES) do
        if (currentCounts[nodeType] or 0) < (minCounts[nodeType] or 0) then
          return false
        end
      end
      return true
    end

    local index = variableIndexList[position]
    local candidates = {}
    for _, nodeType in ipairs(ALL_NODE_TYPES) do
      if canPlace(index, nodeType) then
        candidates[#candidates + 1] = nodeType
      end
    end
    if #candidates <= 0 then
      return false
    end

    local ordered = weightedOrder(candidates, weights, rand, minCounts, currentCounts)
    for _, nodeType in ipairs(ordered) do
      resolvedTypeByIndex[index] = nodeType
      currentCounts[nodeType] = (currentCounts[nodeType] or 0) + 1

      local remainingSlots = #variableIndexList - position
      local feasible = remainingRequiredAfter(currentCounts, remainingSlots)
      if feasible and solve(position + 1) then
        return true
      end

      currentCounts[nodeType] = currentCounts[nodeType] - 1
      resolvedTypeByIndex[index] = nil
    end

    return false
  end

  if not remainingRequiredAfter(currentCounts, #variableIndexList) then
    return fallbackNodes(stageIndex)
  end
  if not solve(1) then
    return fallbackNodes(stageIndex)
  end

  local nodes = {}
  for index = 1, nodeCount do
    local nodeType = resolvedTypeByIndex[index] or "mob"
    nodes[index] = {
      nodeId = string.format("s%d_n%02d", stageIndex, index),
      stageIndex = stageIndex,
      nodeIndex = index,
      type = nodeType,
      titleKey = TITLE_KEY_BY_TYPE[nodeType],
      fallbackTitleKo = FALLBACK_TITLE_KO_BY_TYPE[nodeType]
    }
  end
  return nodes
end

return SingleStageGenerator
