--[[
파일명: abilities/board_effects.lua
모듈명: AbilityBoardEffects

역할:
- 능력 공용 상태 컨테이너(스톤/플레이어/보드/히스토리) 관리
- 보드 지속 효과(빙판/폭발물/블랙홀)와 상태 마커 렌더링
]]

local Constants = require("constants")
local CardRules = require("shared.card_rules")

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

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local GHOST_TUNABLES = CardRules.getCardTunables("ghost")
local GHOST_PASS_THROUGH_OBSTACLES = GHOST_TUNABLES.pass_through_obstacles ~= false
local GHOST_PASS_THROUGH_STONES = GHOST_TUNABLES.pass_through_stones == true

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
    nextShotPowerMultiplier = 1,
    pendingNongaeUntilTurn = nil,
    reversalRewardPending = false,
    reversalRewardCount = 0,
    quickFinishActive = false,
    quickFinishActivationTurn = nil,
    quickFinishDeadlineTurn = nil,
    quickFinishCardsPerTurn = 0
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
    lastOpponentTurnDeaths = {},
    spawnPositionByStoneId = {}
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
        elseif type(defaultValue) == "boolean" then
          status[key] = incoming == true
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
  if type(value) == "table" then
    if type(value.lastOpponentTurnDeaths) == "table" then
      for _, stoneId in ipairs(value.lastOpponentTurnDeaths) do
        if type(stoneId) == "string" then
          normalized.lastOpponentTurnDeaths[#normalized.lastOpponentTurnDeaths + 1] = stoneId
        end
      end
    end
    if type(value.spawnPositionByStoneId) == "table" then
      for stoneId, raw in pairs(value.spawnPositionByStoneId) do
        if type(stoneId) == "string" and type(raw) == "table" and isFiniteNumber(raw.x) and isFiniteNumber(raw.y) then
          normalized.spawnPositionByStoneId[stoneId] = {
            x = raw.x,
            y = raw.y
          }
        end
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
  if type(scene._turnHistory.lastOpponentTurnDeaths) ~= "table" then
    scene._turnHistory.lastOpponentTurnDeaths = {}
  end
  if type(scene._turnHistory.spawnPositionByStoneId) ~= "table" then
    scene._turnHistory.spawnPositionByStoneId = {}
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
  if type(effectPayload.bombAdded) == "table" and type(effectPayload.bombAdded.id) == "string" then
    scene._boardEffects.bombs[#scene._boardEffects.bombs + 1] = cloneTable(effectPayload.bombAdded)
  end
  if type(effectPayload.blackholeEffectAdded) == "table" and type(effectPayload.blackholeEffectAdded.id) == "string" then
    scene._boardEffects.blackholeEffects[#scene._boardEffects.blackholeEffects + 1] = cloneTable(effectPayload.blackholeEffectAdded)
  end
  if type(effectPayload.bombsReplaced) == "table" then
    scene._boardEffects.bombs = cloneTable(effectPayload.bombsReplaced)
  end
  if type(effectPayload.blackholeEffectsReplaced) == "table" then
    scene._boardEffects.blackholeEffects = cloneTable(effectPayload.blackholeEffectsReplaced)
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

local function isStatusActiveUntilTurn(untilTurn, turnIndex)
  return type(untilTurn) == "number" and untilTurn >= turnIndex
end

local function isGhostActiveOnTurn(status, turnIndex)
  if type(status) ~= "table" then
    return false
  end
  if isStatusActiveUntilTurn(status.ghostUntilTurn, turnIndex) then
    return true
  end
  return status.isGhost == true
end

local function isStealthActiveOnTurn(status, turnIndex)
  if type(status) ~= "table" then
    return false
  end
  if isStatusActiveUntilTurn(status.invisibleToOpponentUntilTurn, turnIndex) then
    return true
  end
  return status.isInvisibleToOpponent == true
end

local function isNongaeActiveOnTurn(status, turnIndex)
  if type(status) ~= "table" then
    return false
  end
  if isStatusActiveUntilTurn(status.nongaeUntilTurn, turnIndex) then
    return true
  end
  return status.isNongae == true
end

local function markStoneOut(scene, stone, cause)
  if type(stone) ~= "table" or stone.alive == false then
    return
  end
  stone.alive = false
  if type(scene.onStoneOut) == "function" then
    scene:onStoneOut(stone, cause or "ability")
  end
  if type(scene.getStoneVelocity) == "function" and type(stone.id) == "string" then
    local velocity = scene:getStoneVelocity(stone.id)
    velocity.vx = 0
    velocity.vy = 0
  end
end

function AbilityBoardEffects.isStoneBoundOnCurrentTurn(scene, stoneId)
  local status = AbilityBoardEffects.getStoneStatus(scene, stoneId)
  return isStatusActiveUntilTurn(status.boundUntilTurn, scene._playingTurnIndex or 1)
end

function AbilityBoardEffects.isPlayerAbilitySealed(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local status = scene._playerStatusByIndex[playerIndex]
  if type(status) ~= "table" then
    return false
  end
  return type(status.abilitySealUntilTurn) == "number" and status.abilitySealUntilTurn >= scene._playingTurnIndex
end

function AbilityBoardEffects.isPlayerAbilityBlocked(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local status = scene._playerStatusByIndex[playerIndex]
  if type(status) ~= "table" then
    return false
  end
  local turnIndex = scene._playingTurnIndex or 1
  if type(status.abilitySealUntilTurn) == "number" and status.abilitySealUntilTurn >= turnIndex then
    return true
  end
  if type(status.cannotUseAbilityUntilTurn) == "number" and status.cannotUseAbilityUntilTurn >= turnIndex then
    return true
  end
  return false
end

function AbilityBoardEffects.getPlayerStatus(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local status = scene._playerStatusByIndex[playerIndex]
  if type(status) ~= "table" then
    return createDefaultPlayerStatus()
  end
  return status
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

function AbilityBoardEffects.canStoneCollideWithObstacle(scene, stone, _obstacle)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if not GHOST_PASS_THROUGH_OBSTACLES then
    return true
  end
  if type(stone) ~= "table" or type(stone.id) ~= "string" then
    return true
  end
  local status = AbilityBoardEffects.getStoneStatus(scene, stone.id)
  local turnIndex = scene._playingTurnIndex or 1
  if isGhostActiveOnTurn(status, turnIndex) then
    return false
  end
  return true
end

function AbilityBoardEffects.canStoneCollideWithStone(scene, firstStone, secondStone)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if not GHOST_PASS_THROUGH_STONES then
    return true
  end
  local turnIndex = scene._playingTurnIndex or 1
  if type(firstStone) == "table" and type(firstStone.id) == "string" then
    local firstStatus = AbilityBoardEffects.getStoneStatus(scene, firstStone.id)
    if isGhostActiveOnTurn(firstStatus, turnIndex) then
      return false
    end
  end
  if type(secondStone) == "table" and type(secondStone.id) == "string" then
    local secondStatus = AbilityBoardEffects.getStoneStatus(scene, secondStone.id)
    if isGhostActiveOnTurn(secondStatus, turnIndex) then
      return false
    end
  end
  return true
end

function AbilityBoardEffects.shouldRenderStone(scene, stone)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(stone) ~= "table" or stone.alive == false or type(stone.id) ~= "string" then
    return false
  end
  if type(scene.getMyPlayerIndex) ~= "function" then
    return true
  end
  local myPlayerIndex = scene:getMyPlayerIndex()
  if myPlayerIndex ~= 1 and myPlayerIndex ~= 2 then
    return true
  end
  if stone.ownerPlayerIndex == myPlayerIndex then
    return true
  end
  local status = AbilityBoardEffects.getStoneStatus(scene, stone.id)
  local turnIndex = scene._playingTurnIndex or 1
  if isStealthActiveOnTurn(status, turnIndex) then
    return false
  end
  return true
end

local function pruneExpiredBlackholeEffects(scene)
  local nowMs = (love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()) * 1000
  local nextList = {}
  for _, effect in ipairs(scene._boardEffects.blackholeEffects) do
    if type(effect) == "table" and isFiniteNumber(effect.createdAtMs) and isFiniteNumber(effect.durationMs) then
      if effect.createdAtMs + effect.durationMs >= nowMs then
        nextList[#nextList + 1] = effect
      end
    end
  end
  scene._boardEffects.blackholeEffects = nextList
end

function AbilityBoardEffects.getStepAccelerationForStone(scene, stone, _velocity, _stepSec)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(stone) ~= "table" or stone.alive == false then
    return 0, 0
  end
  pruneExpiredBlackholeEffects(scene)
  local accelX = 0
  local accelY = 0
  for _, effect in ipairs(scene._boardEffects.blackholeEffects) do
    if type(effect) == "table"
      and isFiniteNumber(effect.x)
      and isFiniteNumber(effect.y)
      and isFiniteNumber(effect.radius)
      and isFiniteNumber(effect.accelPxPerSec2)
      and effect.radius > 0
    then
      local dx = effect.x - stone.x
      local dy = effect.y - stone.y
      local distanceSq = dx * dx + dy * dy
      if distanceSq > 1 then
        local distance = math.sqrt(distanceSq)
        if distance <= effect.radius then
          local ratio = 1 - (distance / effect.radius)
          local pull = math.max(0, effect.accelPxPerSec2 * ratio)
          accelX = accelX + (dx / distance) * pull
          accelY = accelY + (dy / distance) * pull
        end
      end
    end
  end
  return accelX, accelY
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

  pruneExpiredBlackholeEffects(scene)
  local nowSec = (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  for _, effect in ipairs(scene._boardEffects.blackholeEffects) do
    if type(effect) == "table"
      and isFiniteNumber(effect.x)
      and isFiniteNumber(effect.y)
      and isFiniteNumber(effect.radius)
    then
      local localX, localY = scene:canonicalToLocal(effect.x, effect.y)
      local worldX = scene._boardX + localX
      local worldY = scene._boardY + localY
      local pulse = 0.75 + 0.25 * math.sin(nowSec * 7)
      love.graphics.setColor(0.10, 0.08, 0.16, 0.22)
      love.graphics.circle("fill", worldX, worldY, effect.radius)
      love.graphics.setColor(0.50, 0.40, 0.85, 0.55 * pulse)
      love.graphics.circle("line", worldX, worldY, effect.radius)
      love.graphics.setColor(0.65, 0.58, 0.96, 0.25 * pulse)
      love.graphics.circle("line", worldX, worldY, effect.radius * 0.6)
    end
  end

  for _, bomb in ipairs(scene._boardEffects.bombs) do
    if type(bomb) == "table" and isFiniteNumber(bomb.x) and isFiniteNumber(bomb.y) then
      local localX, localY = scene:canonicalToLocal(bomb.x, bomb.y)
      local worldX = scene._boardX + localX
      local worldY = scene._boardY + localY
      love.graphics.setColor(0.85, 0.30, 0.22, 0.90)
      love.graphics.circle("fill", worldX, worldY, 9)
      love.graphics.setColor(1.0, 0.78, 0.32, 0.95)
      love.graphics.circle("line", worldX, worldY, 11)
      if isFiniteNumber(bomb.radius) then
        love.graphics.setColor(1.0, 0.55, 0.25, 0.16)
        love.graphics.circle("line", worldX, worldY, bomb.radius)
      end
      if isFiniteNumber(bomb.explodeAtTurn) then
        local remain = math.max(0, bomb.explodeAtTurn - turnIndex)
        love.graphics.setColor(1.0, 0.94, 0.72, 0.90)
        love.graphics.print(tostring(remain), worldX - 4, worldY - 6)
      end
    end
  end
end

function AbilityBoardEffects.drawStoneStatusOverlays(scene)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local turnIndex = scene._playingTurnIndex or 1
  local myPlayerIndex = type(scene.getMyPlayerIndex) == "function" and scene:getMyPlayerIndex() or nil
  for _, stone in ipairs(scene._playingStoneList or {}) do
    if stone.alive ~= false and AbilityBoardEffects.shouldRenderStone(scene, stone) then
      local status = scene._stoneStatusById[stone.id]
      if type(status) == "table" and isStatusActiveUntilTurn(status.boundUntilTurn, turnIndex) then
        local localX, localY = scene:canonicalToLocal(stone.x, stone.y)
        local worldX = scene._boardX + localX
        local worldY = scene._boardY + localY
        love.graphics.setColor(1.0, 0.35, 0.12, 1.0)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", worldX, worldY, Constants.STONE_RADIUS + 5)
        love.graphics.setLineWidth(1)
      end
      if type(status) == "table" and isGhostActiveOnTurn(status, turnIndex) then
        local localX, localY = scene:canonicalToLocal(stone.x, stone.y)
        local worldX = scene._boardX + localX
        local worldY = scene._boardY + localY
        love.graphics.setColor(0.55, 0.85, 1.0, 0.55)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", worldX, worldY, Constants.STONE_RADIUS + 8)
        love.graphics.setLineWidth(1)
      end
      if type(status) == "table" and myPlayerIndex and stone.ownerPlayerIndex == myPlayerIndex and isStealthActiveOnTurn(status, turnIndex) then
        local localX, localY = scene:canonicalToLocal(stone.x, stone.y)
        local worldX = scene._boardX + localX
        local worldY = scene._boardY + localY
        love.graphics.setColor(0.72, 0.48, 1.0, 0.50)
        love.graphics.circle("line", worldX, worldY, Constants.STONE_RADIUS + 3)
      end
    end
  end
end

function AbilityBoardEffects.onTurnStart(scene, _playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  local turnIndex = scene._playingTurnIndex or 1

  for stoneId, status in pairs(scene._stoneStatusById) do
    if type(stoneId) == "string" and type(status) == "table" then
      if type(status.boundUntilTurn) == "number" and status.boundUntilTurn < turnIndex then
        status.boundUntilTurn = nil
      end
      if type(status.ghostUntilTurn) == "number" and status.ghostUntilTurn < turnIndex then
        status.ghostUntilTurn = nil
        status.isGhost = false
      end
      if type(status.invisibleToOpponentUntilTurn) == "number" and status.invisibleToOpponentUntilTurn < turnIndex then
        status.invisibleToOpponentUntilTurn = nil
        status.isInvisibleToOpponent = false
      end
      if type(status.powerMoveUntilTurn) == "number" and status.powerMoveUntilTurn < turnIndex then
        status.powerMoveUntilTurn = nil
      end
      if type(status.nongaeUntilTurn) == "number" and status.nongaeUntilTurn < turnIndex then
        status.nongaeUntilTurn = nil
        status.isNongae = false
      end
      status.spawnLockedThisTurn = false
    end
  end

  local nextIceZones = {}
  for _, zone in ipairs(scene._boardEffects.iceZones) do
    if type(zone.expiresAtTurn) ~= "number" or zone.expiresAtTurn >= turnIndex then
      nextIceZones[#nextIceZones + 1] = zone
    end
  end
  scene._boardEffects.iceZones = nextIceZones
  pruneExpiredBlackholeEffects(scene)
end

function AbilityBoardEffects.onTurnEnd(scene, playerIndex)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if playerIndex ~= 1 and playerIndex ~= 2 then
    return
  end
  local turnIndex = scene._playingTurnIndex or 1
  for _, stone in ipairs(scene._playingStoneList or {}) do
    if stone.alive ~= false and stone.ownerPlayerIndex == playerIndex then
      local status = AbilityBoardEffects.getStoneStatus(scene, stone.id)
      if isNongaeActiveOnTurn(status, turnIndex) then
        markStoneOut(scene, stone, "nongae_self_destruct")
        status.nongaeUntilTurn = nil
        status.isNongae = false
      end
    end
  end
end

function AbilityBoardEffects.onShotPrepare(_scene, _shotParams)
end

function AbilityBoardEffects.onShotResolved(_scene, _shotResult)
end

function AbilityBoardEffects.onStoneOut(_scene, _stone, _cause)
end

function AbilityBoardEffects.onStoneCollisionResolved(scene, firstStone, secondStone)
  AbilityBoardEffects.ensureSceneStateContainers(scene)
  if type(firstStone) ~= "table" or type(secondStone) ~= "table" then
    return
  end
  local turnIndex = scene._playingTurnIndex or 1
  local firstStatus = AbilityBoardEffects.getStoneStatus(scene, firstStone.id)
  local secondStatus = AbilityBoardEffects.getStoneStatus(scene, secondStone.id)
  local firstIsNongae = isNongaeActiveOnTurn(firstStatus, turnIndex)
  local secondIsNongae = isNongaeActiveOnTurn(secondStatus, turnIndex)
  if not firstIsNongae and not secondIsNongae then
    return
  end
  if firstIsNongae and secondStone.alive ~= false then
    markStoneOut(scene, secondStone, "nongae_collision")
  end
  if secondIsNongae and firstStone.alive ~= false then
    markStoneOut(scene, firstStone, "nongae_collision")
  end
end

return AbilityBoardEffects
