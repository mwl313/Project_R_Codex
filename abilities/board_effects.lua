--[[
파일명: abilities/board_effects.lua
모듈명: AbilityBoardEffects

역할:
- 능력 공용 상태 컨테이너(스톤/플레이어/보드/히스토리) 관리
- 보드 지속 효과(빙판)와 상태 마커 렌더링
]]

local Constants = require("constants")

local AbilityBoardEffects = {}

local function cloneTable(value)
  if type(value) ~= "table" then
    return value
  end
  local copied = {}
  for key, nested in pairs(value) do
    copied[key] = cloneTable(nested)
  end
  return copied
end

local function createDefaultStoneStatus()
  return {
    ghostUntilTurn = nil,
    isGhost = false,
    invisibleToOpponentUntilTurn = nil,
    isInvisibleToOpponent = false,
    boundUntilTurn = nil,
    powerMoveCharges = 0,
    powerMoveUntilTurn = nil,
    nongaeUntilTurn = nil,
    isNongae = false,
    spawnLockedThisTurn = false
  }
end

local function createDefaultPlayerStatus()
  return {
    abilitySealUntilTurn = nil,
    reverseUntilTurn = nil,
    cannotUseAbilityUntilTurn = nil,
    suddenDeathEndTurn = nil,
    drawOneRandomCardPerTurnUntilTurn = nil,
    nextShotPowerMultiplier = 1
  }
end

local function createDefaultBoardEffects()
  return {
    iceZones = {},
    bombs = {},
    blackholeEffects = {}
  }
end

local function createDefaultTurnHistory()
  return {
    lastOpponentTurnDeaths = {}
  }
end

local function normalizeStoneStatusMap(value)
  local normalized = {}
  if type(value) ~= "table" then
    return normalized
  end
  for stoneId, raw in pairs(value) do
    if type(stoneId) == "string" then
      local base = createDefaultStoneStatus()
      if type(raw) == "table" then
        for key, defaultValue in pairs(base) do
          local incoming = raw[key]
          if type(defaultValue) == "boolean" then
            base[key] = incoming == true
          elseif type(defaultValue) == "number" then
            if type(incoming) == "number" then
              base[key] = incoming
            end
          else
            base[key] = type(incoming) == "number" and incoming or nil
          end
        end
      end
      normalized[stoneId] = base
    end
  end
  return normalized
end

local function normalizePlayerStatusByIndex(value)
  local normalized = {
    [1] = createDefaultPlayerStatus(),
    [2] = createDefaultPlayerStatus()
  }
  if type(value) ~= "table" then
    return normalized
  end
  for _, playerIndex in ipairs({ 1, 2 }) do
    local raw = value[playerIndex] or value[tostring(playerIndex)]
    if type(raw) == "table" then
      local status = normalized[playerIndex]
      for key, defaultValue in pairs(status) do
        local incoming = raw[key]
        if type(defaultValue) == "number" then
          if type(incoming) == "number" then
            status[key] = incoming
          end
        else
          status[key] = type(incoming) == "number" and incoming or nil
        end
      end
    end
  end
  return normalized
end

local function normalizeBoardEffects(value)
  local normalized = createDefaultBoardEffects()
  if type(value) ~= "table" then
    return normalized
  end
  if type(value.iceZones) == "table" then
    for _, raw in ipairs(value.iceZones) do
      if type(raw) == "table" and type(raw.id) == "string" and type(raw.x) == "number" and type(raw.y) == "number" and type(raw.radius) == "number" then
        normalized.iceZones[#normalized.iceZones + 1] = {
          id = raw.id,
          ownerPlayerIndex = raw.ownerPlayerIndex == 2 and 2 or 1,
          x = raw.x,
          y = raw.y,
          radius = math.max(1, raw.radius),
          dampingMultiplier = type(raw.dampingMultiplier) == "number" and raw.dampingMultiplier or 1,
          expiresAtTurn = type(raw.expiresAtTurn) == "number" and raw.expiresAtTurn or 0
        }
      end
    end
  end
  if type(value.bombs) == "table" then
    normalized.bombs = cloneTable(value.bombs)
  end
  if type(value.blackholeEffects) == "table" then
    normalized.blackholeEffects = cloneTable(value.blackholeEffects)
  end
  return normalized
end

local function normalizeTurnHistory(value)
  local normalized = createDefaultTurnHistory()
  if type(value) == "table" and type(value.lastOpponentTurnDeaths) == "table" then
    for _, stoneId in ipairs(value.lastOpponentTurnDeaths) do
      if type(stoneId) == "string" then
        normalized.lastOpponentTurnDeaths[#normalized.lastOpponentTurnDeaths + 1] = stoneId
      end
    end
  end
  return normalized
end

function AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(scene._stoneStatusById) ~= "table" then
    scene._stoneStatusById = {}
  end
  if type(scene._playerStatusByIndex) ~= "table" then
    scene._playerStatusByIndex = {
      [1] = createDefaultPlayerStatus(),
      [2] = createDefaultPlayerStatus()
    }
  end
  if type(scene._playerStatusByIndex[1]) ~= "table" then
    scene._playerStatusByIndex[1] = createDefaultPlayerStatus()
  end
  if type(scene._playerStatusByIndex[2]) ~= "table" then
    scene._playerStatusByIndex[2] = createDefaultPlayerStatus()
  end
  if type(scene._boardEffects) ~= "table" then
    scene._boardEffects = createDefaultBoardEffects()
  end
  if type(scene._boardEffects.iceZones) ~= "table" then
    scene._boardEffects.iceZones = {}
  end
  if type(scene._boardEffects.bombs) ~= "table" then
    scene._boardEffects.bombs = {}
  end
  if type(scene._boardEffects.blackholeEffects) ~= "table" then
    scene._boardEffects.blackholeEffects = {}
  end
  if type(scene._turnHistory) ~= "table" then
    scene._turnHistory = createDefaultTurnHistory()
  end
end

function AbilityBoardEffects.applyPlayingState(scene, playing)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(playing) ~= "table" then
    return
  end
  scene._stoneStatusById = normalizeStoneStatusMap(playing.stoneStatusById)
  scene._playerStatusByIndex = normalizePlayerStatusByIndex(playing.playerStatusByIndex)
  scene._boardEffects = normalizeBoardEffects(playing.boardEffects)
  scene._turnHistory = normalizeTurnHistory(playing.turnHistory)
end

function AbilityBoardEffects.applyServerCardEffect(scene, effectPayload)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(effectPayload) ~= "table" then
    return
  end
  if type(effectPayload.stoneStatusById) == "table" then
    local patch = normalizeStoneStatusMap(effectPayload.stoneStatusById)
    for stoneId, status in pairs(patch) do
      scene._stoneStatusById[stoneId] = status
    end
  end
  if type(effectPayload.playerStatusByIndex) == "table" then
    scene._playerStatusByIndex = normalizePlayerStatusByIndex(effectPayload.playerStatusByIndex)
  end
  if type(effectPayload.iceZoneAdded) == "table" and type(effectPayload.iceZoneAdded.id) == "string" then
    scene._boardEffects.iceZones[#scene._boardEffects.iceZones + 1] = {
      id = effectPayload.iceZoneAdded.id,
      ownerPlayerIndex = effectPayload.iceZoneAdded.ownerPlayerIndex == 2 and 2 or 1,
      x = effectPayload.iceZoneAdded.x,
      y = effectPayload.iceZoneAdded.y,
      radius = effectPayload.iceZoneAdded.radius,
      dampingMultiplier = effectPayload.iceZoneAdded.dampingMultiplier or 1,
      expiresAtTurn = effectPayload.iceZoneAdded.expiresAtTurn or scene._playingTurnIndex
    }
  end
  if type(effectPayload.movedStones) == "table" then
    local stoneById = {}
    for _, stone in ipairs(scene._playingStoneList or {}) do
      stoneById[stone.id] = stone
    end
    for _, moved in ipairs(effectPayload.movedStones) do
      if type(moved) == "table" and type(moved.id) == "string" then
        local stone = stoneById[moved.id]
        if stone and type(moved.x) == "number" and type(moved.y) == "number" then
          stone.x = moved.x
          stone.y = moved.y
          if moved.resetVelocity and type(scene.getStoneVelocity) == "function" then
            local velocity = scene:getStoneVelocity(stone.id)
            velocity.vx = 0
            velocity.vy = 0
          end
        end
      end
    end
  end
end

function AbilityBoardEffects.getStoneStatus(scene, stoneId)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(stoneId) ~= "string" then
    return createDefaultStoneStatus()
  end
  local status = scene._stoneStatusById[stoneId]
  if type(status) ~= "table" then
    status = createDefaultStoneStatus()
    scene._stoneStatusById[stoneId] = status
  end
  return status
end

function AbilityBoardEffects.isStoneBoundOnCurrentTurn(scene, stoneId)
  local status = AbilityBoardEffects.getStoneStatus(scene, stoneId)
  return type(status.boundUntilTurn) == "number" and status.boundUntilTurn >= scene._playingTurnIndex
end

function AbilityBoardEffects.isPlayerAbilitySealed(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local status = scene._playerStatusByIndex[playerIndex]
  if type(status) ~= "table" then
    return false
  end
  return type(status.abilitySealUntilTurn) == "number" and status.abilitySealUntilTurn >= scene._playingTurnIndex
end

function AbilityBoardEffects.getNextShotPowerMultiplier(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local status = scene._playerStatusByIndex[playerIndex]
  if type(status) ~= "table" then
    return 1
  end
  if type(status.nextShotPowerMultiplier) ~= "number" then
    return 1
  end
  return status.nextShotPowerMultiplier
end

function AbilityBoardEffects.getDampingMultiplierForStone(scene, stone)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(stone) ~= "table" or stone.alive == false then
    return 1
  end
  local turnIndex = scene._playingTurnIndex or 1
  local result = 1
  for _, zone in ipairs(scene._boardEffects.iceZones) do
    if type(zone) == "table" and type(zone.x) == "number" and type(zone.y) == "number" and type(zone.radius) == "number" then
      local isExpired = type(zone.expiresAtTurn) == "number" and zone.expiresAtTurn < turnIndex
      if not isExpired then
        local dx = stone.x - zone.x
        local dy = stone.y - zone.y
        if dx * dx + dy * dy <= zone.radius * zone.radius then
          local dampingMultiplier = type(zone.dampingMultiplier) == "number" and zone.dampingMultiplier or 1
          result = math.max(0.05, math.min(result, dampingMultiplier))
        end
      end
    end
  end
  return result
end

function AbilityBoardEffects.drawBoardEffects(scene)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local turnIndex = scene._playingTurnIndex or 1
  for _, zone in ipairs(scene._boardEffects.iceZones) do
    if type(zone) == "table" and type(zone.x) == "number" and type(zone.y) == "number" and type(zone.radius) == "number" then
      local isExpired = type(zone.expiresAtTurn) == "number" and zone.expiresAtTurn < turnIndex
      if not isExpired then
        local localX, localY = scene:canonicalToLocal(zone.x, zone.y)
        local worldX = scene._boardX + localX
        local worldY = scene._boardY + localY
        love.graphics.setColor(0.30, 0.68, 0.95, 0.16)
        love.graphics.circle("fill", worldX, worldY, zone.radius)
        love.graphics.setColor(0.34, 0.80, 1.00, 0.60)
        love.graphics.circle("line", worldX, worldY, zone.radius)
      end
    end
  end
end

function AbilityBoardEffects.drawStoneStatusOverlays(scene)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  for _, stone in ipairs(scene._playingStoneList or {}) do
    if stone.alive ~= false then
      local status = scene._stoneStatusById[stone.id]
      if type(status) == "table" and type(status.boundUntilTurn) == "number" and status.boundUntilTurn >= scene._playingTurnIndex then
        local localX, localY = scene:canonicalToLocal(stone.x, stone.y)
        local worldX = scene._boardX + localX
        local worldY = scene._boardY + localY
        love.graphics.setColor(1.0, 0.35, 0.12, 1.0)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", worldX, worldY, Constants.STONE_RADIUS + 5)
        love.graphics.setLineWidth(1)
      end
    end
  end
end

function AbilityBoardEffects.onTurnStart(scene, _playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local turnIndex = scene._playingTurnIndex or 1
  local nextIceZones = {}
  for _, zone in ipairs(scene._boardEffects.iceZones) do
    if type(zone.expiresAtTurn) ~= "number" or zone.expiresAtTurn >= turnIndex then
      nextIceZones[#nextIceZones + 1] = zone
    end
  end
  scene._boardEffects.iceZones = nextIceZones
end

function AbilityBoardEffects.onTurnEnd(_scene, _playerIndex)
end

function AbilityBoardEffects.onShotPrepare(_scene, _shotParams)
end

function AbilityBoardEffects.onShotResolved(_scene, _shotResult)
end

function AbilityBoardEffects.onStoneOut(_scene, _stone, _cause)
end

return AbilityBoardEffects
