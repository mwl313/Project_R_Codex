--[[
파일명: single_combat_core.lua
모듈명: SingleCombatCore

역할:
- 싱글 전투의 오프라인 코어(물리/턴/카드/AI)를 제공한다.
- 멀티에서 쓰는 공용 모듈(GameMechanics/Abilities/CardHandBar)을 재사용한다.
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local TimeUtils = require("utils.time_utils")
local CardRules = require("shared.card_rules")
local CardRegistry = require("single.card_registry")
local GameMechanics = require("game_mechanics")
local Abilities = require("abilities")
local CardHandBar = require("ui.card_hand_bar")
local CutsceneManager = require("ui.cutscene_manager")
local EffectManager = require("effects.effect_manager")
local SingleAI = require("single.single_ai")
local SingleRunState = require("single.single_run_state")
local InputCaptureGuard = require("utils.input_capture_guard")
local SingleCampaignRulesLoader = require("single.single_campaign_rules_loader")
local RelicEffects = require("single.relic_effects")
local EncountersLoader = require("single.encounters_loader")
local SingleCombatTuning = require("single.single_combat_tuning")
local GodRelicDefs = require("single.god_relic_defs")
local GodRelicRuntime = require("single.god_relic_runtime")

local SingleCombatCore = {}
SingleCombatCore.__index = SingleCombatCore

local function t(key, vars)
  return I18n.t(key, vars)
end

local function clamp(v, minV, maxV)
  if v < minV then
    return minV
  end
  if v > maxV then
    return maxV
  end
  return v
end

local function randomInt(rng, minValue, maxValue)
  if minValue >= maxValue then
    return minValue
  end
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function makeRng(seed)
  if love and love.math and love.math.newRandomGenerator then
    return love.math.newRandomGenerator(seed or os.time())
  end
  return nil
end

local function intersectSegmentWithWorldRect(startX, startY, endX, endY)
  local minX = 0
  local maxX = Constants.BASE_WORLD_W
  local minY = 0
  local maxY = Constants.BASE_WORLD_H
  local dx = endX - startX
  local dy = endY - startY
  local bestT = 1

  local function consider(t)
    if t == nil then
      return
    end
    if t < 0 or t > 1 then
      return
    end
    if t < bestT then
      bestT = t
    end
  end

  if dx ~= 0 then
    consider((minX - startX) / dx)
    consider((maxX - startX) / dx)
  end
  if dy ~= 0 then
    consider((minY - startY) / dy)
    consider((maxY - startY) / dy)
  end

  return startX + dx * bestT, startY + dy * bestT
end

local function getDeck(profile, deckId)
  if type(profile) ~= "table" or type(profile.decks) ~= "table" then
    return nil
  end
  local targetId = tostring(deckId or "default")
  for _, deck in ipairs(profile.decks) do
    if type(deck) == "table" and tostring(deck.deckId or "") == targetId then
      return deck
    end
  end
  return profile.decks[1]
end

local function copyList(list)
  local out = {}
  for _, v in ipairs(list or {}) do
    out[#out + 1] = v
  end
  return out
end

local function countAlive(stones, owner)
  local count = 0
  for _, stone in ipairs(stones or {}) do
    if stone.alive ~= false and stone.ownerPlayerIndex == owner then
      count = count + 1
    end
  end
  return count
end

local function computeAimPreviewSegments(boardX, boardY, stoneRadius, directionX, directionY, bounceCount, startX, startY)
  local segmentList = {}
  local dirLen = math.sqrt(directionX * directionX + directionY * directionY)
  if dirLen <= 0.0001 then
    return segmentList
  end

  local dirX = directionX / dirLen
  local dirY = directionY / dirLen
  local minX = boardX + stoneRadius
  local maxX = boardX + Constants.BOARD_W - stoneRadius
  local minY = boardY + stoneRadius
  local maxY = boardY + Constants.BOARD_H - stoneRadius
  local x = startX
  local y = startY
  local maxSegmentCount = math.max(1, math.floor(tonumber(bounceCount) or 0) + 1)
  local epsilon = 0.0001

  for _ = 1, maxSegmentCount do
    local tx = math.huge
    if dirX > epsilon then
      tx = (maxX - x) / dirX
    elseif dirX < -epsilon then
      tx = (minX - x) / dirX
    end

    local ty = math.huge
    if dirY > epsilon then
      ty = (maxY - y) / dirY
    elseif dirY < -epsilon then
      ty = (minY - y) / dirY
    end

    local travel = math.min(tx, ty)
    if travel == math.huge or travel <= epsilon then
      break
    end

    local hitX = x + dirX * travel
    local hitY = y + dirY * travel
    segmentList[#segmentList + 1] = {
      x1 = x,
      y1 = y,
      x2 = hitX,
      y2 = hitY
    }

    local nearXHit = math.abs(tx - travel) <= 0.001
    local nearYHit = math.abs(ty - travel) <= 0.001
    if nearXHit then
      dirX = -dirX
    end
    if nearYHit then
      dirY = -dirY
    end
    x = hitX
    y = hitY
  end

  return segmentList
end

local NODE_TITLE_KEY_BY_TYPE = {
  mob = "single.node.mob",
  elite = "single.node.elite",
  boss = "single.node.boss",
  shop = "single.node.shop",
  rest = "single.node.rest",
  deck_clean = "single.node.deck_clean",
  event = "single.node.event"
}

local SINGLE_HAND_MAX_COUNT = 8

function SingleCombatCore.new(params)
  local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
  local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5
  local self = setmetatable({
    _app = params.app,
    _profile = params.profile,
    _runState = params.runState,
    _enableGodRelics = params.enableGodRelics == true,
    _nodeType = tostring(params.nodeType or "mob"),
    _nodeId = tostring(params.nodeId or ""),
    _stageIndex = math.max(1, math.floor(tonumber(params.stageIndex) or 1)),
    _onCombatEnd = params.onCombatEnd,
    _onCardConsumed = params.onCardConsumed,
    _onShotResolved = params.onShotResolved,
    _onTurnDrawRequest = params.onTurnDrawRequest,
    _boardX = boardX,
    _boardY = boardY,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,

    _playingStoneList = {},
    _stoneVelocityMap = {},
    _obstacleList = {},
    _lockedStoneIdSet = {},
    _invincibleTurnByPlayer = { [1] = nil, [2] = nil },
    _shockwaveOwnerPlayerIndex = nil,
    _shockwaveSourceStoneId = nil,
    _shockwaveCardScale = 1.0,

    _activePlayerIndex = 1,
    _playingTurnIndex = 1,
    _turnEndsAtMs = nil,
    _playingShotBudget = 1,
    _playingShotUsed = 0,
    _hasUsedCardThisTurn = false,
    _isTurnShotCommitted = false,
    _isShotSimulating = false,
    _simAccumulatorSec = 0,
    _simElapsedSec = 0,
    _shouldSendSnapshotAfterSim = false,

    _isAimDragging = false,
    _isAimRelativeMode = false,
    _aimStoneId = nil,
    _aimStartWorldX = nil,
    _aimStartWorldY = nil,
    _aimAccumWorldDX = 0,
    _aimAccumWorldDY = 0,
    _aimLastMouseWorldX = nil,
    _aimLastMouseWorldY = nil,

    _isFinished = false,
    _result = nil,
    _aiThinkRemainSec = 0,

    _effectManager = EffectManager.new(),
    _playingCardHandBar = nil,
    _handEntrySeq = 0,
    _handEntryList = {},
    _handEntryById = {},
    _pendingCardTargetId = nil,
    _pendingCardTargetEntryId = nil,
    _pendingCardTargetCardId = nil,
    _cutsceneManager = nil,
    _pendingCardCutsceneUse = nil,

    _baseDrawPerBattle = 5,
    _maxShotPower = Constants.MAX_SHOT_POWER,
    _combatTuning = nil,
    _combatStatsByPlayerIndex = {},
    _isTurnTimerDisabled = params.disableTurnTimer == true,
    _isHudSuppressed = params.suppressHud == true,
    _initialHandCardIdList = type(params.initialHandCardIdList) == "table" and params.initialHandCardIdList or nil,
    _pendingShotResolution = nil,
    _bossId = nil,
    _bossGimmickList = {},
    _bossBindUntilTurnByStoneId = {},
    _bossRng = nil,
    _playerPiercingChargesLeft = 0,
    _activeShotStoneId = nil,
    _activeShotOwnerPlayerIndex = nil,
    _activeShotPierceConsumed = false
  }, SingleCombatCore)

  self._playingCardHandBar = CardHandBar.new({
    boardCenterX = boardX + Constants.BOARD_W * 0.5,
    boardCenterY = boardY + Constants.BOARD_H * 0.5,
    canUseCard = function(entryId)
      return self:canUseHandEntry(entryId)
    end,
    onCardDeclared = function(entryId)
      return self:onCardDeclared(entryId)
    end,
    onCardBlocked = function(_entryId)
      self:setStatus(t("single.combat.status.card_cannot_use"), Constants.COLOR_DANGER)
    end
  })
  self._cutsceneManager = CutsceneManager.new()

  local campaignRules = SingleCampaignRulesLoader.load()
  local deckRules = type(campaignRules.deck) == "table" and campaignRules.deck or {}
  self._baseDrawPerBattle = math.max(1, math.floor(tonumber(deckRules.drawPerBattle) or 5))
  self._combatTuning = SingleCombatTuning.build({
    runState = self._runState,
    nodeType = self._nodeType,
    stageIndex = self._stageIndex
  })
  self._combatStatsByPlayerIndex = type(self._combatTuning.byPlayerIndex) == "table" and self._combatTuning.byPlayerIndex or {}
  self._maxShotPower = self:getMaxShotPowerForPlayer(1)
  self._bossRng = makeRng((tonumber(self._runState and self._runState.rngSeed) or os.time()) + self._stageIndex * 409)
  if self._enableGodRelics then
    GodRelicRuntime.initRunState(self._runState)
  end
  self:initializeBossGimmicks()

  self:initializeBattlefield()
  self:initializeHand()
  self:startTurn(1, true)
  return self
end

function SingleCombatCore:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleCombatCore:createId(prefix)
  self._handEntrySeq = self._handEntrySeq + 1
  return string.format("%s_%d_%d", tostring(prefix or "e"), self._playingTurnIndex, self._handEntrySeq)
end

function SingleCombatCore:getSideCombatStats(playerIndex)
  local targetPlayerIndex = math.max(1, math.floor(tonumber(playerIndex) or 1))
  local stats = self._combatStatsByPlayerIndex and self._combatStatsByPlayerIndex[targetPlayerIndex]
  if type(stats) ~= "table" and type(self._combatStatsByPlayerIndex) == "table" then
    stats = self._combatStatsByPlayerIndex[tostring(targetPlayerIndex)]
  end
  if type(stats) == "table" then
    return stats
  end
  return {
    maxShotPower = Constants.MAX_SHOT_POWER,
    shotSpeedScale = Constants.SHOT_SPEED_SCALE,
    physicsDampingPerSec = Constants.PHYSICS_DAMPING_PER_SEC,
    stoneRadius = Constants.STONE_RADIUS,
    stoneMass = Constants.STONE_MASS or 1.0
  }
end

function SingleCombatCore:getMaxShotPowerForPlayer(playerIndex)
  return math.max(1, tonumber(self:getSideCombatStats(playerIndex).maxShotPower) or Constants.MAX_SHOT_POWER)
end

function SingleCombatCore:getShotSpeedScaleForPlayer(playerIndex)
  return math.max(0.01, tonumber(self:getSideCombatStats(playerIndex).shotSpeedScale) or Constants.SHOT_SPEED_SCALE)
end

function SingleCombatCore:getStoneRadiusForPlayer(playerIndex)
  return math.max(1, tonumber(self:getSideCombatStats(playerIndex).stoneRadius) or Constants.STONE_RADIUS)
end

function SingleCombatCore:getStoneMassForPlayer(playerIndex)
  return math.max(0.01, tonumber(self:getSideCombatStats(playerIndex).stoneMass) or (Constants.STONE_MASS or 1.0))
end

function SingleCombatCore:getStoneDampingPerSecForPlayer(playerIndex)
  return math.max(0, tonumber(self:getSideCombatStats(playerIndex).physicsDampingPerSec) or Constants.PHYSICS_DAMPING_PER_SEC)
end

function SingleCombatCore:getStoneRadius(stone)
  if type(stone) == "number" then
    return self:getStoneRadiusForPlayer(stone)
  end
  if type(stone) ~= "table" then
    stone = self:getPlayingStoneById(stone)
  end
  if type(stone) ~= "table" then
    return Constants.STONE_RADIUS
  end
  return self:getStoneRadiusForPlayer(stone.ownerPlayerIndex)
end

function SingleCombatCore:getStoneMass(stone)
  if type(stone) == "number" then
    return self:getStoneMassForPlayer(stone)
  end
  if type(stone) ~= "table" then
    stone = self:getPlayingStoneById(stone)
  end
  if type(stone) ~= "table" then
    return Constants.STONE_MASS or 1.0
  end
  return self:getStoneMassForPlayer(stone.ownerPlayerIndex)
end

function SingleCombatCore:getStoneDampingPerSec(stone)
  if type(stone) == "number" then
    return self:getStoneDampingPerSecForPlayer(stone)
  end
  if type(stone) ~= "table" then
    stone = self:getPlayingStoneById(stone)
  end
  if type(stone) ~= "table" then
    return Constants.PHYSICS_DAMPING_PER_SEC
  end
  return self:getStoneDampingPerSecForPlayer(stone.ownerPlayerIndex)
end

function SingleCombatCore:getShotSpeedScaleForStone(stone)
  if type(stone) == "number" then
    return self:getShotSpeedScaleForPlayer(stone)
  end
  if type(stone) ~= "table" then
    stone = self:getPlayingStoneById(stone)
  end
  if type(stone) ~= "table" then
    return Constants.SHOT_SPEED_SCALE
  end
  return self:getShotSpeedScaleForPlayer(stone.ownerPlayerIndex)
end

function SingleCombatCore:initializeBattlefield()
  self._playingStoneList = {}
  local centerX = Constants.BOARD_W * 0.5
  local maxStoneRadius = math.max(self:getStoneRadiusForPlayer(1), self:getStoneRadiusForPlayer(2), Constants.STONE_RADIUS)
  local spreadX = math.max(58, maxStoneRadius * 2 + 8)
  local rowGap = math.max(52, maxStoneRadius * 2 + 8)
  local function spawn(owner, startY)
    local counts = { 3, 2, 2 }
    local index = 1
    for row = 1, #counts do
      local c = counts[row]
      local rowStartX = centerX - ((c - 1) * spreadX) * 0.5
      for col = 1, c do
        self._playingStoneList[#self._playingStoneList + 1] = {
          id = string.format("p%d_s%d", owner, index),
          ownerPlayerIndex = owner,
          x = rowStartX + (col - 1) * spreadX,
          y = startY + (row - 1) * rowGap,
          alive = true
        }
        index = index + 1
      end
    end
  end
  spawn(1, Constants.BOARD_H - 110)
  spawn(2, 110)
  GameMechanics.resetStoneVelocities(self)
end

function SingleCombatCore:refreshBossBindLockSet()
  local nextBind = {}
  for stoneId, untilTurn in pairs(self._bossBindUntilTurnByStoneId or {}) do
    local turnNumber = math.floor(tonumber(untilTurn) or 0)
    if turnNumber >= self._playingTurnIndex then
      nextBind[tostring(stoneId)] = turnNumber
      self._lockedStoneIdSet[tostring(stoneId)] = true
    end
  end
  self._bossBindUntilTurnByStoneId = nextBind
end

function SingleCombatCore:initializeBossGimmicks()
  self._bossId = nil
  self._bossGimmickList = {}
  self._bossBindUntilTurnByStoneId = {}
  if self._nodeType ~= "boss" then
    return
  end

  local encounterData = EncountersLoader.load()
  local bossList = type(encounterData.bosses) == "table" and encounterData.bosses or {}
  if #bossList <= 0 then
    return
  end

  local stageMatched = {}
  for _, boss in ipairs(bossList) do
    if math.floor(tonumber(boss.stageIndex) or 1) == self._stageIndex then
      stageMatched[#stageMatched + 1] = boss
    end
  end
  local pickPool = (#stageMatched > 0) and stageMatched or bossList
  local bossIndex = randomInt(self._bossRng, 1, #pickPool)
  local pickedBoss = pickPool[bossIndex]
  self._bossId = tostring(pickedBoss and pickedBoss.bossId or "")
  self._bossGimmickList = {}

  for _, gimmick in ipairs((pickedBoss and pickedBoss.gimmicks) or {}) do
    if type(gimmick) == "table" and type(gimmick.type) == "string" and gimmick.type ~= "" then
      self._bossGimmickList[#self._bossGimmickList + 1] = {
        type = gimmick.type,
        everyTurns = math.max(1, math.floor(tonumber(gimmick.everyTurns) or 1)),
        radius = math.max(1, math.floor(tonumber(gimmick.radius) or 18)),
        durationMs = math.max(1, math.floor(tonumber(gimmick.durationMs) or 600)),
        accel = math.max(0, tonumber(gimmick.accel) or 180),
        durationTurns = math.max(1, math.floor(tonumber(gimmick.durationTurns) or 1))
      }
    end
  end
end

function SingleCombatCore:applyBossAutoRockfall(gimmick)
  local rockRule = CardRules.getRockfallRule()
  local width = math.max(1, tonumber(rockRule.width) or Constants.ROCK_OBSTACLE_WIDTH)
  local height = math.max(1, tonumber(rockRule.height) or Constants.ROCK_OBSTACLE_HEIGHT)
  local margin = math.max(0, tonumber(rockRule.margin) or Constants.ROCK_OBSTACLE_MARGIN)
  local halfW = width * 0.5
  local halfH = height * 0.5

  for _ = 1, 24 do
    local x = randomInt(self._bossRng, math.floor(margin + halfW), math.floor(Constants.BOARD_W - margin - halfW))
    local y = randomInt(self._bossRng, math.floor(margin + halfH), math.floor(Constants.BOARD_H - margin - halfH))
    local canPlace = Abilities.canPlaceRockfallAtCanonical(self, x, y)
    if canPlace then
      self._obstacleList[#self._obstacleList + 1] = {
        id = self:createId("boss_rock"),
        x = x,
        y = y,
        width = width,
        height = height
      }
      return true
    end
  end
  return false
end

function SingleCombatCore:applyBossBlackholePulse(gimmick)
  local durationSec = math.max(0.01, (tonumber(gimmick.durationMs) or 600) / 1000.0)
  local accel = math.max(0, tonumber(gimmick.accel) or 180)
  if accel <= 0 then
    return false
  end
  local centerX = Constants.BOARD_W * 0.5
  local centerY = Constants.BOARD_H * 0.5
  local impulse = accel * durationSec
  local moved = false
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false then
      local dx = centerX - stone.x
      local dy = centerY - stone.y
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 0.0001 then
        local velocity = self:getStoneVelocity(stone.id)
        velocity.vx = velocity.vx + (dx / len) * impulse
        velocity.vy = velocity.vy + (dy / len) * impulse
        moved = true
      end
    end
  end
  if moved then
    GameMechanics.startShotSimulation(self)
  end
  return moved
end

function SingleCombatCore:applyBossBindRandomEnemy(gimmick)
  local candidates = {}
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == 1 then
      candidates[#candidates + 1] = stone
    end
  end
  if #candidates <= 0 then
    return false
  end
  local picked = candidates[randomInt(self._bossRng, 1, #candidates)]
  local durationTurns = math.max(1, math.floor(tonumber(gimmick.durationTurns) or 1))
  local untilTurn = self._playingTurnIndex + durationTurns - 1
  local stoneId = tostring(picked.id)
  local previous = math.floor(tonumber(self._bossBindUntilTurnByStoneId[stoneId]) or 0)
  self._bossBindUntilTurnByStoneId[stoneId] = math.max(previous, untilTurn)
  self:refreshBossBindLockSet()
  return true
end

function SingleCombatCore:applyBossGimmicksOnTurnStart()
  if self._nodeType ~= "boss" or #self._bossGimmickList <= 0 then
    return nil
  end

  local noticeList = {}
  for _, gimmick in ipairs(self._bossGimmickList) do
    local everyTurns = math.max(1, math.floor(tonumber(gimmick.everyTurns) or 1))
    if (self._playingTurnIndex % everyTurns) == 0 then
      if gimmick.type == "auto_rockfall" and self:applyBossAutoRockfall(gimmick) then
        noticeList[#noticeList + 1] = t("single.combat.gimmick.auto_rockfall")
      elseif gimmick.type == "blackhole_pulse" and self:applyBossBlackholePulse(gimmick) then
        noticeList[#noticeList + 1] = t("single.combat.gimmick.blackhole_pulse")
      elseif gimmick.type == "bind_random_enemy" and self:applyBossBindRandomEnemy(gimmick) then
        noticeList[#noticeList + 1] = t("single.combat.gimmick.bind_random_enemy")
      end
    end
  end

  if #noticeList <= 0 then
    return nil
  end
  return table.concat(noticeList, " / ")
end

function SingleCombatCore:initializeHand()
  self._handEntryList = {}
  self._handEntryById = {}
  if type(self._initialHandCardIdList) == "table" and #self._initialHandCardIdList > 0 then
    for _, saveCardId in ipairs(self._initialHandCardIdList) do
      local entryId = self:createId("card")
      local runtimeCardId = CardRegistry.toRuntimeCardId(saveCardId)
      local entry = { entryId = entryId, cardId = runtimeCardId, label = Abilities.getCardLabel(runtimeCardId) }
      self._handEntryList[#self._handEntryList + 1] = entry
      self._handEntryById[entryId] = entry
    end
    self:refreshHandUi()
    return
  end

  local deck = SingleRunState.getRunDeck(self._runState, self._profile)
  if type(deck) ~= "table" then
    deck = getDeck(self._profile, self._runState and self._runState.deckId)
  end
  local runtimeCards = {}
  if deck and type(deck.cards) == "table" then
    for _, cardId in ipairs(deck.cards) do
      runtimeCards[#runtimeCards + 1] = CardRegistry.toRuntimeCardId(cardId)
    end
  end
  if #runtimeCards <= 0 then
    for _, cardId in ipairs(CardRegistry.getStarterCardIds()) do
      runtimeCards[#runtimeCards + 1] = CardRegistry.toRuntimeCardId(cardId)
    end
  end
  if love and love.math and love.math.newRandomGenerator then
    local rng = love.math.newRandomGenerator(os.time())
    for i = #runtimeCards, 2, -1 do
      local j = rng:random(1, i)
      runtimeCards[i], runtimeCards[j] = runtimeCards[j], runtimeCards[i]
    end
  end
  local drawCount = RelicEffects.applyCombatStartModifiers(self._runState, self._baseDrawPerBattle)
  if type(self._runState) == "table" and type(self._runState.tempModifiers) == "table" then
    local drawDelta = math.floor(tonumber(self._runState.tempModifiers.nextCombatDrawDelta) or 0)
    drawCount = math.max(1, drawCount + drawDelta)
    self._runState.tempModifiers.nextCombatDrawDelta = nil
  end
  for i = 1, math.min(drawCount, #runtimeCards) do
    local entryId = self:createId("card")
    local cardId = runtimeCards[i]
    local entry = { entryId = entryId, cardId = cardId, label = Abilities.getCardLabel(cardId) }
    self._handEntryList[#self._handEntryList + 1] = entry
    self._handEntryById[entryId] = entry
  end
  self:refreshHandUi()
end

function SingleCombatCore:removeHandEntry(entry)
  if type(entry) ~= "table" or entry.entryId == nil then
    return
  end
  for i, e in ipairs(self._handEntryList) do
    if e.entryId == entry.entryId then
      table.remove(self._handEntryList, i)
      break
    end
  end
  if type(self._onCardConsumed) == "function" then
    self._onCardConsumed(CardRegistry.fromRuntimeCardId(entry.cardId), entry.cardId)
  end
  self._handEntryById[entry.entryId] = nil
  self:refreshHandUi()
end

function SingleCombatCore:restoreHandEntry(entry)
  if type(entry) ~= "table" then
    return
  end
  local restored = {
    entryId = tostring(entry.entryId or self:createId("card")),
    cardId = tostring(entry.cardId or ""),
    label = tostring(entry.label or Abilities.getCardLabel(entry.cardId))
  }
  if restored.cardId == "" then
    return
  end
  self._handEntryList[#self._handEntryList + 1] = restored
  self._handEntryById[restored.entryId] = restored
  self:refreshHandUi()
end

function SingleCombatCore:startCardUseCutscene(entry, target)
  if type(entry) ~= "table" then
    return false
  end
  if not self._cutsceneManager then
    return false
  end
  local started = self._cutsceneManager:start({
    cardId = entry.cardId,
    ownerPlayerIndex = 1,
    isLocalUser = true,
    skillName = entry.label
  })
  -- 싱글은 서버 동기화 대기가 없으므로 로컬 컷신만 재생한다.
  self._cutsceneManager:setBlockedByServerPaused(false)
  self._pendingCardCutsceneUse = {
    entry = {
      entryId = entry.entryId,
      cardId = entry.cardId,
      label = entry.label
    },
    target = target
  }
  if started then
    self:setStatus(t("match.status.cutscene_playing", {
      cardLabel = tostring(entry.label or entry.cardId)
    }), Constants.COLOR_TEXT_SUB)
  end
  return true
end

function SingleCombatCore:updatePendingCardCutsceneUse()
  if type(self._pendingCardCutsceneUse) ~= "table" then
    return
  end
  if self._cutsceneManager and self._cutsceneManager:isActive() then
    return
  end

  local pending = self._pendingCardCutsceneUse
  self._pendingCardCutsceneUse = nil
  local entry = pending.entry
  local ok, reason = self:applyCardEffect(entry.cardId, pending.target)
  if not ok then
    self:restoreHandEntry(entry)
    self:setStatus(reason or t("single.combat.status.card_cannot_use"), Constants.COLOR_DANGER)
    return
  end
  self:setStatus(t("single.combat.status.card_used", { card = entry.label }), Constants.COLOR_TEXT_SUB)
end

function SingleCombatCore:refreshHandUi()
  local list = {}
  for _, entry in ipairs(self._handEntryList) do
    list[#list + 1] = { id = entry.entryId, label = entry.label }
  end
  self._playingCardHandBar:setCards(list)
end

function SingleCombatCore:startTurn(playerIndex, initial)
  self._activePlayerIndex = playerIndex
  self._maxShotPower = self:getMaxShotPowerForPlayer(playerIndex)
  if not initial then
    self._playingTurnIndex = self._playingTurnIndex + 1
  end
  if self._isTurnTimerDisabled then
    self._turnEndsAtMs = nil
  else
    self._turnEndsAtMs = TimeUtils.nowEpochMs() + Constants.TURN_TIME_LIMIT_SEC * 1000
  end
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  self._playerPiercingChargesLeft = 0
  self._activeShotStoneId = nil
  self._activeShotOwnerPlayerIndex = nil
  self._activeShotPierceConsumed = false
  self._hasUsedCardThisTurn = false
  self._isTurnShotCommitted = false
  self._lockedStoneIdSet = {}
  self:refreshBossBindLockSet()
  self._shockwaveOwnerPlayerIndex = nil
  self._shockwaveSourceStoneId = nil
  self._shockwaveCardScale = 1.0
  self._pendingCardTargetId = nil
  self._pendingCardTargetEntryId = nil
  self._pendingCardTargetCardId = nil
  self._pendingCardCutsceneUse = nil
  if self._cutsceneManager then
    self._cutsceneManager:reset()
  end
  self._pendingShotResolution = nil
  self:cancelAimDrag(true)
  if playerIndex == 2 then
    self._aiThinkRemainSec = 0.20
    self:setStatus(t("single.combat.status.ai_turn"), Constants.COLOR_TEXT_SUB)
  else
    self:applyGodRelicsOnPlayerTurnStart()
    self._aiThinkRemainSec = 0
    self:setStatus(t("single.combat.status.player_turn"), Constants.COLOR_TEXT_SUB)
  end

  local gimmickNotice = self:applyBossGimmicksOnTurnStart()
  if gimmickNotice and gimmickNotice ~= "" then
    self:setStatus(gimmickNotice, Constants.COLOR_TEXT_SUB)
  end
end

function SingleCombatCore:beginAimDrag(worldX, worldY, stone)
  if not stone then
    return false
  end
  self._isAimDragging = true
  self._aimStoneId = stone.id
  self._aimStartWorldX = worldX
  self._aimStartWorldY = worldY
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = worldX
  self._aimLastMouseWorldY = worldY
  self._isAimRelativeMode = InputCaptureGuard.captureRelativeMouse()
  if self._isAimRelativeMode then
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
  end
  return true
end

function SingleCombatCore:getAimCursorWorldPosition()
  local startWorldX = self._aimStartWorldX or 0
  local startWorldY = self._aimStartWorldY or 0
  return startWorldX + self._aimAccumWorldDX, startWorldY + self._aimAccumWorldDY
end

function SingleCombatCore:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local restoreWorldX, restoreWorldY = intersectSegmentWithWorldRect(stoneWorldX, stoneWorldY, aimWorldX, aimWorldY)
  return self._app:worldToScreen(restoreWorldX, restoreWorldY)
end

function SingleCombatCore:updateAimDragInput()
  if not self._isAimDragging then
    return
  end

  if self._isAimRelativeMode then
    local relativeDx, relativeDy, isRelative = InputCaptureGuard.consumeRelativeDelta()
    if isRelative then
      local worldDx, worldDy = self._app:screenDeltaToWorldDelta(relativeDx, relativeDy)
      self._aimAccumWorldDX = self._aimAccumWorldDX + worldDx
      self._aimAccumWorldDY = self._aimAccumWorldDY + worldDy
      return
    end
    self._isAimRelativeMode = false
    InputCaptureGuard.release()
  end

  local mouseWorldX, mouseWorldY = self._app:getMouseWorldPosition()
  if self._aimLastMouseWorldX ~= nil and self._aimLastMouseWorldY ~= nil then
    self._aimAccumWorldDX = self._aimAccumWorldDX + (mouseWorldX - self._aimLastMouseWorldX)
    self._aimAccumWorldDY = self._aimAccumWorldDY + (mouseWorldY - self._aimLastMouseWorldY)
  end
  self._aimLastMouseWorldX = mouseWorldX
  self._aimLastMouseWorldY = mouseWorldY
end

function SingleCombatCore:cancelAimDrag(silent)
  local restoreScreenX = nil
  local restoreScreenY = nil
  if self._isAimDragging then
    self:updateAimDragInput()
    local stone = self:getAliveStoneById(self._aimStoneId)
    if stone then
      local stoneWorldX = self._boardX + stone.x
      local stoneWorldY = self._boardY + stone.y
      restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
    end
  end

  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil

  if not silent then
    self:setStatus("", Constants.COLOR_TEXT_SUB)
  end
end

function SingleCombatCore:commitAimDrag()
  if not self._isAimDragging then
    return
  end

  self:updateAimDragInput()
  local stone = self:getAliveStoneById(self._aimStoneId)
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local restoreScreenX = nil
  local restoreScreenY = nil
  if stone then
    local stoneWorldX = self._boardX + stone.x
    local stoneWorldY = self._boardY + stone.y
    restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  end

  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil

  if not stone then
    self._aimAccumWorldDX = 0
    self._aimAccumWorldDY = 0
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
    return
  end

  local stoneWorldX = self._boardX + stone.x
  local stoneWorldY = self._boardY + stone.y
  local dx = stoneWorldX - aimWorldX
  local dy = stoneWorldY - aimWorldY
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 8 then
    self:setStatus(t("single.combat.status.shot_too_short"), Constants.COLOR_DANGER)
    return
  end
  local maxShotPower = self:getMaxShotPowerForPlayer(1)

  GameMechanics.applyShotImpulse(self, {
    stoneId = stone.id,
    dirX = dx / len,
    dirY = dy / len,
    power = clamp(len * Constants.POWER_PER_PIXEL, 0, maxShotPower),
    shotSpeedScale = self:getShotSpeedScaleForPlayer(1)
  })
  self._pendingShotResolution = {
    ownerPlayerIndex = 1,
    firstAliveBefore = countAlive(self._playingStoneList, 1),
    secondAliveBefore = countAlive(self._playingStoneList, 2)
  }
  self._playingShotUsed = self._playingShotUsed + 1
  self._isTurnShotCommitted = true
end

function SingleCombatCore:isPlayingPhase() return not self._isFinished end
function SingleCombatCore:isMyTurn() return (not self._isFinished) and self._activePlayerIndex == 1 end
function SingleCombatCore:canonicalToLocal(x, y) return x, y end
function SingleCombatCore:localToCanonical(x, y) return x, y end
function SingleCombatCore:sendHostSnapshotIfNeeded(_turn, _reason) end
function SingleCombatCore:isInvincibleOnCurrentTurn(playerIndex) return Abilities.isInvincibleOnCurrentTurn(self, playerIndex) end
function SingleCombatCore:isShockwaveShotStone(stoneId) return Abilities.isShockwaveShotStone(self, stoneId) end
function SingleCombatCore:applyShockwaveFromPoint(x, y) Abilities.applyShockwaveFromPoint(self, x, y) end
function SingleCombatCore:applyInvincibleCollisionResponse(a, b, nx, ny, fv, sv) return Abilities.applyInvincibleCollisionResponse(a, b, nx, ny, fv, sv) end

function SingleCombatCore:getStoneVelocity(stoneId)
  local key = tostring(stoneId or "")
  if not self._stoneVelocityMap[key] then
    self._stoneVelocityMap[key] = { vx = 0, vy = 0 }
  end
  return self._stoneVelocityMap[key]
end

function SingleCombatCore:getPlayingStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId then
      return stone
    end
  end
  return nil
end

function SingleCombatCore:getAliveStoneById(stoneId)
  local stone = self:getPlayingStoneById(stoneId)
  return (stone and stone.alive ~= false) and stone or nil
end

function SingleCombatCore:toBoardLocal(worldX, worldY)
  local lx = worldX - self._boardX
  local ly = worldY - self._boardY
  if lx < 0 or lx > Constants.BOARD_W or ly < 0 or ly > Constants.BOARD_H then
    return nil, nil
  end
  return lx, ly
end

function SingleCombatCore:getCardUpgradeScale(runtimeCardId)
  local saveCardId = CardRegistry.fromRuntimeCardId(runtimeCardId)
  local level = SingleRunState.getUpgradeLevel(self._runState, saveCardId)
  return 1.0 + math.max(0, level) * 0.10
end

function SingleCombatCore:getCurrentHandCount()
  return #self._handEntryList
end

function SingleCombatCore:getGodRelicCount(godRelicId)
  if not self._enableGodRelics then
    return 0
  end
  return GodRelicRuntime.getCount(self._runState, godRelicId)
end

function SingleCombatCore:getAimPreviewBounceCount()
  return math.max(0, self:getGodRelicCount(GodRelicDefs.ID_PRECISION_CONTROL))
end

function SingleCombatCore:addHandEntriesFromSaveCardIdList(saveCardIdList)
  local addedCount = 0
  for _, saveCardId in ipairs(saveCardIdList or {}) do
    local normalized = tostring(saveCardId or "")
    if normalized ~= "" then
      local runtimeCardId = CardRegistry.toRuntimeCardId(normalized)
      local entryId = self:createId("card")
      local entry = { entryId = entryId, cardId = runtimeCardId, label = Abilities.getCardLabel(runtimeCardId) }
      self._handEntryList[#self._handEntryList + 1] = entry
      self._handEntryById[entryId] = entry
      addedCount = addedCount + 1
    end
  end
  if addedCount > 0 then
    self:refreshHandUi()
  end
  return addedCount
end

function SingleCombatCore:applyGodRelicsOnPlayerTurnStart()
  local actionBonus = math.max(0, self:getGodRelicCount(GodRelicDefs.ID_ACTION_POWER))
  self._playingShotBudget = 1 + actionBonus
  self._playerPiercingChargesLeft = math.max(0, self:getGodRelicCount(GodRelicDefs.ID_PIERCING_SHOT))

  local drawPerTurn = math.max(0, self:getGodRelicCount(GodRelicDefs.ID_INFINITE_POWER))
  if drawPerTurn <= 0 then
    return
  end
  if type(self._onTurnDrawRequest) ~= "function" then
    return
  end

  local drawnCardIdList = self._onTurnDrawRequest(drawPerTurn, self:getCurrentHandCount(), SINGLE_HAND_MAX_COUNT)
  if type(drawnCardIdList) ~= "table" or #drawnCardIdList <= 0 then
    return
  end
  self:addHandEntriesFromSaveCardIdList(drawnCardIdList)
end

function SingleCombatCore:canUseHandEntry(entryId)
  local entry = self._handEntryById[tostring(entryId or "")]
  if not entry then
    return false
  end
  if not self:isMyTurn() or self._isShotSimulating or self._playingShotUsed > 0 or self._hasUsedCardThisTurn then
    return false
  end
  if self._pendingCardTargetCardId then
    return false
  end
  return Abilities.isSupportedTurnCard(entry.cardId)
end

function SingleCombatCore:applyCardEffect(cardId, target)
  local upgradeScale = self:getCardUpgradeScale(cardId)
  local effect = nil
  if cardId == "agile" then
    local rule = CardRules.getAgileRule()
    local baseBudget = math.max(1, math.floor(tonumber(rule and rule.shot_budget) or 2))
    local boostedBudget = math.max(baseBudget, math.floor(baseBudget * upgradeScale + 0.5))
    effect = { shotBudget = math.max(self._playingShotBudget, boostedBudget) }
  elseif cardId == "invincible" then
    local rule = CardRules.getInvincibleRule()
    local baseOffset = math.max(1, math.floor(tonumber(rule and rule.protect_after_turn_offset) or 1))
    local offset = math.max(1, math.floor(baseOffset * upgradeScale))
    effect = { invincibleTurnByPlayer = { [1] = self._playingTurnIndex + offset, [2] = self._invincibleTurnByPlayer[2] } }
  elseif cardId == "shockwave" then
    self._shockwaveCardScale = upgradeScale
    effect = { shockwaveOwnerPlayerIndex = 1 }
  elseif cardId == "reinforcement" then
    if not target then return false, t("single.combat.status.card_target_invalid") end
    local ok, reason = Abilities.canPlaceReinforcementAtCanonical(self, target.x, target.y)
    if not ok then return false, reason end
    effect = {
      spawnStone = { id = self:createId("p1_r"), ownerPlayerIndex = 1, x = target.x, y = target.y, alive = true },
      lockedStoneIds = {}
    }
    effect.lockedStoneIds = copyList({})
    for id, locked in pairs(self._lockedStoneIdSet) do
      if locked then effect.lockedStoneIds[#effect.lockedStoneIds + 1] = id end
    end
    effect.lockedStoneIds[#effect.lockedStoneIds + 1] = effect.spawnStone.id
  elseif cardId == "rockfall" then
    if not target then return false, t("single.combat.status.card_target_invalid") end
    local ok, reason = Abilities.canPlaceRockfallAtCanonical(self, target.x, target.y)
    if not ok then return false, reason end
    local rule = CardRules.getRockfallRule()
    local baseWidth = math.max(1, tonumber(rule.width) or Constants.ROCK_OBSTACLE_WIDTH)
    local baseHeight = math.max(1, tonumber(rule.height) or Constants.ROCK_OBSTACLE_HEIGHT)
    effect = {
      obstacle = {
        id = self:createId("rock"),
        x = target.x,
        y = target.y,
        width = math.max(1, math.floor(baseWidth * upgradeScale + 0.5)),
        height = math.max(1, math.floor(baseHeight * upgradeScale + 0.5))
      }
    }
  else
    return false, t("single.combat.status.card_unsupported")
  end
  Abilities.applyServerCardEffect(self, effect)
  self._hasUsedCardThisTurn = true
  GameMechanics.syncStoneVelocityMap(self)
  return true
end

function SingleCombatCore:onCardDeclared(entryId)
  local entry = self._handEntryById[tostring(entryId or "")]
  if not entry then return false end
  if not self:canUseHandEntry(entryId) then return false end
  if Abilities.isPointTargetCard(entry.cardId) then
    self._pendingCardTargetEntryId = entry.entryId
    self._pendingCardTargetCardId = entry.cardId
    self:setStatus(Abilities.getPendingTargetStartStatus(entry.cardId), Constants.COLOR_TEXT_SUB)
    return false
  end
  self:removeHandEntry(entry)
  self:startCardUseCutscene(entry, nil)
  return true
end

function SingleCombatCore:onShotImpulseApplied(stone, _shotPayload)
  local stoneId = type(stone) == "table" and tostring(stone.id or "") or ""
  local owner = type(stone) == "table" and math.floor(tonumber(stone.ownerPlayerIndex) or 0) or 0
  self._activeShotStoneId = stoneId ~= "" and stoneId or nil
  self._activeShotOwnerPlayerIndex = owner > 0 and owner or nil
  self._activeShotPierceConsumed = false
end

function SingleCombatCore:consumePiercingCollision(stone, _collisionKind)
  if type(stone) ~= "table" then
    return false
  end
  if self._activeShotPierceConsumed then
    return false
  end
  if self._activeShotOwnerPlayerIndex ~= 1 then
    return false
  end
  if tostring(stone.id or "") ~= tostring(self._activeShotStoneId or "") then
    return false
  end
  if self._playerPiercingChargesLeft <= 0 then
    return false
  end
  self._playerPiercingChargesLeft = self._playerPiercingChargesLeft - 1
  self._activeShotPierceConsumed = true
  return true
end

function SingleCombatCore:shouldTreatOutAsWall(stone)
  if type(stone) ~= "table" then
    return false
  end
  if tonumber(stone.ownerPlayerIndex) ~= 1 then
    return false
  end
  return self:getGodRelicCount(GodRelicDefs.ID_SAFETY) > 0
end

function SingleCombatCore:commitPendingTarget(worldX, worldY)
  if not self._pendingCardTargetCardId or not self._pendingCardTargetEntryId then
    return false
  end
  local entry = self._handEntryById[self._pendingCardTargetEntryId]
  if not entry then
    return true
  end
  local lx, ly = self:toBoardLocal(worldX, worldY)
  if not lx then
    self:setStatus(Abilities.getPendingTargetOutOfBoardStatus(self._pendingCardTargetCardId), Constants.COLOR_DANGER)
    return true
  end
  local ok, reason = true, nil
  if entry.cardId == "reinforcement" then
    ok, reason = Abilities.canPlaceReinforcementAtCanonical(self, lx, ly)
  elseif entry.cardId == "rockfall" then
    ok, reason = Abilities.canPlaceRockfallAtCanonical(self, lx, ly)
  end
  if not ok then
    self:setStatus(reason or t("single.combat.status.card_target_invalid"), Constants.COLOR_DANGER)
    return true
  end
  -- 실적용은 컷신 종료 후 수행한다. 여기서는 유효성 확인만 하고 타겟을 고정한다.
  self:removeHandEntry(entry)
  self._pendingCardTargetEntryId = nil
  self._pendingCardTargetCardId = nil
  self:startCardUseCutscene(entry, { x = lx, y = ly })
  return true
end

function SingleCombatCore:update(dt, mouseX, mouseY)
  if self._isFinished then return end
  if self._cutsceneManager then
    self._cutsceneManager:update(dt)
  end
  self:updatePendingCardCutsceneUse()
  if self._cutsceneManager and self._cutsceneManager:isInputBlocked() then
    self:updateAimDragInput()
    return
  end
  self:updateAimDragInput()
  self._effectManager:update(dt)
  self._playingCardHandBar:update(dt, mouseX, mouseY, { isPlayingPhase = true, isStoneDragging = self._isAimDragging })
  if (not self._isTurnTimerDisabled) and self._turnEndsAtMs and TimeUtils.nowEpochMs() >= self._turnEndsAtMs and (not self._isShotSimulating) then
    self:startTurn(self._activePlayerIndex == 1 and 2 or 1, false)
  end
  local wasSim = self._isShotSimulating
  GameMechanics.updateShotSimulation(self, dt)
  if wasSim and (not self._isShotSimulating) then
    local firstAliveNow = countAlive(self._playingStoneList, 1)
    local secondAliveNow = countAlive(self._playingStoneList, 2)
    if self._pendingShotResolution and type(self._onShotResolved) == "function" then
      local meta = self._pendingShotResolution
      local enemyOut = 0
      local selfOut = 0
      if meta.ownerPlayerIndex == 1 then
        enemyOut = math.max(0, math.floor((meta.secondAliveBefore or 0) - secondAliveNow))
        selfOut = math.max(0, math.floor((meta.firstAliveBefore or 0) - firstAliveNow))
      else
        enemyOut = math.max(0, math.floor((meta.firstAliveBefore or 0) - firstAliveNow))
        selfOut = math.max(0, math.floor((meta.secondAliveBefore or 0) - secondAliveNow))
      end
      self._onShotResolved({
        ownerPlayerIndex = meta.ownerPlayerIndex,
        enemyOut = enemyOut,
        selfOut = selfOut
      })
    end
    self._pendingShotResolution = nil

    local myAlive = firstAliveNow
    local enemyAlive = secondAliveNow
    if myAlive <= 0 and enemyAlive <= 0 then self:finish("draw") return end
    if enemyAlive <= 0 then self:finish("win") return end
    if myAlive <= 0 then self:finish("lose") return end
    if self._playingShotUsed >= self._playingShotBudget then
      self:startTurn(self._activePlayerIndex == 1 and 2 or 1, false)
    end
  end
  if self._activePlayerIndex == 2 and (not self._isShotSimulating) then
    self._aiThinkRemainSec = self._aiThinkRemainSec - math.max(0, dt)
    if self._aiThinkRemainSec <= 0 then
      local shot = SingleAI.chooseShot({
        nodeType = self._nodeType,
        turnIndex = self._playingTurnIndex,
        aiPlayerIndex = 2,
        stoneList = self._playingStoneList,
        obstacleList = self._obstacleList,
        maxShotPower = self:getMaxShotPowerForPlayer(2),
        combatStatsByPlayerIndex = self._combatStatsByPlayerIndex
      })
      if shot then
        shot.shotSpeedScale = tonumber(shot.shotSpeedScale) or self:getShotSpeedScaleForPlayer(2)
        GameMechanics.applyShotImpulse(self, shot)
        self._pendingShotResolution = {
          ownerPlayerIndex = 2,
          firstAliveBefore = countAlive(self._playingStoneList, 1),
          secondAliveBefore = countAlive(self._playingStoneList, 2)
        }
        self._playingShotUsed = self._playingShotUsed + 1
        self._isTurnShotCommitted = true
      else
        self:startTurn(1, false)
      end
    end
  end
end

function SingleCombatCore:finish(result)
  if self._isFinished then return end
  self:cancelAimDrag(true)
  self._isFinished = true
  self._result = result
  if type(self._onCombatEnd) == "function" then
    self._onCombatEnd(result)
  end
end

function SingleCombatCore:draw(mouseX, mouseY)
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)
  for _, obstacle in ipairs(self._obstacleList) do
    local w = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local h = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.setColor(0.44, 0.42, 0.40, 1.0)
    love.graphics.rectangle("fill", self._boardX + obstacle.x - w * 0.5, self._boardY + obstacle.y - h * 0.5, w, h, 6, 6)
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", self._boardX + obstacle.x - w * 0.5, self._boardY + obstacle.y - h * 0.5, w, h, 6, 6)
  end
  local previousPendingTargetId = self._pendingCardTargetId
  self._pendingCardTargetId = self._pendingCardTargetCardId
  Abilities.drawPendingCardPreview(self, mouseX, mouseY)
  self._pendingCardTargetId = previousPendingTargetId
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false then
      local color = stone.ownerPlayerIndex == 1 and Constants.COLOR_STONE_HOST or Constants.COLOR_STONE_GUEST
      local radius = self:getStoneRadius(stone)
      love.graphics.setColor(color)
      love.graphics.circle("fill", self._boardX + stone.x, self._boardY + stone.y, radius)
      love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
      love.graphics.circle("line", self._boardX + stone.x, self._boardY + stone.y, radius)
    end
  end
  if self._isAimDragging and self._aimStoneId then
    local stone = self:getAliveStoneById(self._aimStoneId)
    if stone then
      local sx = self._boardX + stone.x
      local sy = self._boardY + stone.y
      local ax, ay = self:getAimCursorWorldPosition()
      local dx = sx - ax
      local dy = sy - ay
      local dist = math.sqrt(dx * dx + dy * dy)
      local power = math.min(self:getMaxShotPowerForPlayer(1), dist * Constants.POWER_PER_PIXEL)
      love.graphics.setColor(0.95, 0.92, 0.35, 0.95)
      love.graphics.setLineWidth(2)
      love.graphics.line(sx, sy, ax, ay)
      love.graphics.setLineWidth(1)
      love.graphics.setFont(FontManager.getFont("small"))
      love.graphics.setColor(Constants.COLOR_TEXT)
      love.graphics.printf(t("match.power_label", {
        power = string.format("%.0f", power)
      }), sx - 56, sy - 28, 112, "center")

      local bounceCount = self:getAimPreviewBounceCount()
      if bounceCount > 0 then
        local previewSegments = computeAimPreviewSegments(
          self._boardX,
          self._boardY,
          self:getStoneRadius(stone),
          dx,
          dy,
          bounceCount,
          sx,
          sy
        )
        love.graphics.setColor(0.66, 0.92, 1.0, 0.92)
        love.graphics.setLineWidth(2)
        for _, segment in ipairs(previewSegments) do
          love.graphics.line(segment.x1, segment.y1, segment.x2, segment.y2)
          love.graphics.circle("fill", segment.x2, segment.y2, 2.5)
        end
        love.graphics.setLineWidth(1)
      end
    end
  end
  self._effectManager:draw(self._boardX, self._boardY, function(x, y) return x, y end)
  self._playingCardHandBar:draw()
  if not self._isHudSuppressed then
    love.graphics.setFont(FontManager.getFont("title"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf(t("single.combat.title"), 0, 16, Constants.BASE_WORLD_W, "center")
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    local nodeTitle = t(NODE_TITLE_KEY_BY_TYPE[self._nodeType] or "single.node.mob")
    love.graphics.printf(t("single.combat.node_line", { nodeType = nodeTitle, nodeId = self._nodeId }), 0, 52, Constants.BASE_WORLD_W, "center")
    local remain = self._turnEndsAtMs and TimeUtils.getRemainingSeconds(self._turnEndsAtMs) or 0
    local owner = self._activePlayerIndex == 1 and t("single.combat.turn_owner.player") or t("single.combat.turn_owner.ai")
    if self._isTurnTimerDisabled then
      love.graphics.printf(t("single.combat.info_line_no_timer", {
        turnIndex = tostring(self._playingTurnIndex),
        turnOwner = owner,
        shotUsed = tostring(self._playingShotUsed),
        shotBudget = tostring(self._playingShotBudget)
      }), 0, 636, Constants.BASE_WORLD_W, "center")
    else
      love.graphics.printf(t("single.combat.info_line", {
        turnIndex = tostring(self._playingTurnIndex),
        turnOwner = owner,
        remainSec = tostring(remain),
        shotUsed = tostring(self._playingShotUsed),
        shotBudget = tostring(self._playingShotBudget)
      }), 0, 636, Constants.BASE_WORLD_W, "center")
    end
    love.graphics.setColor(self._statusColor)
    love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
  end
end

function SingleCombatCore:drawTopOverlay(mouseX, mouseY)
  if self._cutsceneManager then
    self._cutsceneManager:draw(mouseX, mouseY)
  end
end

function SingleCombatCore:mousepressed(worldX, worldY, button)
  if self._isFinished then return false end
  if self._cutsceneManager and self._cutsceneManager:mousepressed(worldX, worldY, button) then
    return true
  end
  if button == 2 then
    if self._pendingCardTargetCardId then
      self._pendingCardTargetCardId = nil
      self._pendingCardTargetEntryId = nil
      self._pendingCardTargetId = nil
      self:setStatus(t("single.combat.status.card_target_cancel"), Constants.COLOR_TEXT_SUB)
      return true
    end
    self:cancelAimDrag(true)
    return true
  end
  if button ~= 1 then return false end
  if self._pendingCardTargetCardId and self:commitPendingTarget(worldX, worldY) then return true end
  if self._playingCardHandBar:mousepressed(worldX, worldY, button) then return true end
  if not self:isMyTurn() or self._isShotSimulating or self._playingShotUsed >= self._playingShotBudget then return false end
  local lx, ly = self:toBoardLocal(worldX, worldY)
  if not lx then return false end
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == 1 and self._lockedStoneIdSet[stone.id] ~= true then
      local radius = self:getStoneRadius(stone)
      local dx, dy = stone.x - lx, stone.y - ly
      if dx * dx + dy * dy <= (radius + 4) ^ 2 then
        self:beginAimDrag(worldX, worldY, stone)
        return true
      end
    end
  end
  return false
end

function SingleCombatCore:mousereleased(worldX, worldY, button)
  if self._isFinished or button ~= 1 then return false end
  if self._cutsceneManager and self._cutsceneManager:mousereleased(worldX, worldY, button) then
    return true
  end
  if self._playingCardHandBar:mousereleased(worldX, worldY, button) then return true end
  self:commitAimDrag()
  return true
end

function SingleCombatCore:mousemoved(_worldX, _worldY, _dx, _dy)
end

function SingleCombatCore:wheelmoved(_worldX, _worldY, _dx, _dy) end

function SingleCombatCore:keypressed(key)
  if self._cutsceneManager and self._cutsceneManager:keypressed(key) then
    return true
  end
  if key == "escape" and self._pendingCardTargetCardId then
    self._pendingCardTargetCardId = nil
    self._pendingCardTargetEntryId = nil
    self._pendingCardTargetId = nil
    self:setStatus(t("single.combat.status.card_target_cancel"), Constants.COLOR_TEXT_SUB)
    return true
  end
  if key == "escape" and self._isAimDragging then
    self:cancelAimDrag(true)
    return true
  end
  return false
end

function SingleCombatCore:onAppEvent(event)
  if type(event) ~= "table" then
    return
  end
  if event.type == "focus_lost" then
    self:cancelAimDrag(true)
  end
end

function SingleCombatCore:onSceneWillChange(_event)
  self:cancelAimDrag(true)
  self._pendingCardCutsceneUse = nil
  if self._cutsceneManager then
    self._cutsceneManager:reset()
  end
end

function SingleCombatCore:exit()
  self:cancelAimDrag(true)
  self._pendingCardCutsceneUse = nil
  if self._cutsceneManager then
    self._cutsceneManager:reset()
  end
end

function SingleCombatCore:getCurrentHandCardIdList()
  local list = {}
  for _, entry in ipairs(self._handEntryList or {}) do
    list[#list + 1] = CardRegistry.fromRuntimeCardId(entry.cardId)
  end
  return list
end

function SingleCombatCore:getAliveStoneCount(ownerPlayerIndex)
  return countAlive(self._playingStoneList, ownerPlayerIndex)
end

function SingleCombatCore:getStatusSnapshot()
  return {
    text = tostring(self._statusText or ""),
    color = self._statusColor or Constants.COLOR_TEXT_SUB
  }
end

return SingleCombatCore
