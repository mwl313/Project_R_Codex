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
local EffectManager = require("effects.effect_manager")
local SingleAI = require("single.single_ai")

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

local NODE_TITLE_KEY_BY_TYPE = {
  mob = "single.node.mob",
  elite = "single.node.elite",
  boss = "single.node.boss",
  shop = "single.node.shop",
  rest = "single.node.rest",
  deck_clean = "single.node.deck_clean",
  event = "single.node.event"
}

function SingleCombatCore.new(params)
  local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
  local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5
  local self = setmetatable({
    _app = params.app,
    _profile = params.profile,
    _runState = params.runState,
    _nodeType = tostring(params.nodeType or "mob"),
    _nodeId = tostring(params.nodeId or ""),
    _onCombatEnd = params.onCombatEnd,
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
    _aimStoneId = nil,
    _aimWorldX = nil,
    _aimWorldY = nil,

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
    _pendingCardTargetCardId = nil
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

function SingleCombatCore:initializeBattlefield()
  self._playingStoneList = {}
  local centerX = Constants.BOARD_W * 0.5
  local spreadX = 58
  local rowGap = 52
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

function SingleCombatCore:initializeHand()
  self._handEntryList = {}
  self._handEntryById = {}
  local deck = getDeck(self._profile, self._runState and self._runState.deckId)
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
  for i = 1, math.min(5, #runtimeCards) do
    local entryId = self:createId("card")
    local cardId = runtimeCards[i]
    local entry = { entryId = entryId, cardId = cardId, label = Abilities.getCardLabel(cardId) }
    self._handEntryList[#self._handEntryList + 1] = entry
    self._handEntryById[entryId] = entry
  end
  self:refreshHandUi()
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
  if not initial then
    self._playingTurnIndex = self._playingTurnIndex + 1
  end
  self._turnEndsAtMs = TimeUtils.nowEpochMs() + Constants.TURN_TIME_LIMIT_SEC * 1000
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  self._hasUsedCardThisTurn = false
  self._isTurnShotCommitted = false
  self._lockedStoneIdSet = {}
  self._shockwaveOwnerPlayerIndex = nil
  self._shockwaveSourceStoneId = nil
  self._pendingCardTargetId = nil
  self._pendingCardTargetEntryId = nil
  self._pendingCardTargetCardId = nil
  self._isAimDragging = false
  self._aimStoneId = nil
  if playerIndex == 2 then
    self._aiThinkRemainSec = 0.20
    self:setStatus(t("single.combat.status.ai_turn"), Constants.COLOR_TEXT_SUB)
  else
    self._aiThinkRemainSec = 0
    self:setStatus(t("single.combat.status.player_turn"), Constants.COLOR_TEXT_SUB)
  end
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
  local effect = nil
  if cardId == "agile" then
    local rule = CardRules.getAgileRule()
    effect = { shotBudget = math.max(self._playingShotBudget, math.floor(tonumber(rule and rule.shot_budget) or 2)) }
  elseif cardId == "invincible" then
    local rule = CardRules.getInvincibleRule()
    local offset = math.max(1, math.floor(tonumber(rule and rule.protect_after_turn_offset) or 1))
    effect = { invincibleTurnByPlayer = { [1] = self._playingTurnIndex + offset, [2] = self._invincibleTurnByPlayer[2] } }
  elseif cardId == "shockwave" then
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
    effect = { obstacle = { id = self:createId("rock"), x = target.x, y = target.y, width = rule.width or Constants.ROCK_OBSTACLE_WIDTH, height = rule.height or Constants.ROCK_OBSTACLE_HEIGHT } }
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
  local ok, reason = self:applyCardEffect(entry.cardId, nil)
  if not ok then
    self:setStatus(reason or t("single.combat.status.card_cannot_use"), Constants.COLOR_DANGER)
    return false
  end
  for i, e in ipairs(self._handEntryList) do
    if e.entryId == entry.entryId then
      table.remove(self._handEntryList, i)
      break
    end
  end
  self._handEntryById[entry.entryId] = nil
  self:refreshHandUi()
  self:setStatus(t("single.combat.status.card_used", { card = entry.label }), Constants.COLOR_TEXT_SUB)
  return true
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
  local ok, reason = self:applyCardEffect(entry.cardId, { x = lx, y = ly })
  if not ok then
    self:setStatus(reason or t("single.combat.status.card_target_invalid"), Constants.COLOR_DANGER)
    return true
  end
  for i, e in ipairs(self._handEntryList) do
    if e.entryId == entry.entryId then
      table.remove(self._handEntryList, i)
      break
    end
  end
  self._handEntryById[entry.entryId] = nil
  self._pendingCardTargetEntryId = nil
  self._pendingCardTargetCardId = nil
  self:refreshHandUi()
  self:setStatus(t("single.combat.status.card_used", { card = entry.label }), Constants.COLOR_TEXT_SUB)
  return true
end

function SingleCombatCore:update(dt, mouseX, mouseY)
  if self._isFinished then return end
  self._effectManager:update(dt)
  self._playingCardHandBar:update(dt, mouseX, mouseY, { isPlayingPhase = true, isStoneDragging = self._isAimDragging })
  if self._turnEndsAtMs and TimeUtils.nowEpochMs() >= self._turnEndsAtMs and (not self._isShotSimulating) then
    self:startTurn(self._activePlayerIndex == 1 and 2 or 1, false)
  end
  local wasSim = self._isShotSimulating
  GameMechanics.updateShotSimulation(self, dt)
  if wasSim and (not self._isShotSimulating) then
    local myAlive = countAlive(self._playingStoneList, 1)
    local enemyAlive = countAlive(self._playingStoneList, 2)
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
      local shot = SingleAI.chooseShot({ nodeType = self._nodeType, turnIndex = self._playingTurnIndex, aiPlayerIndex = 2, stoneList = self._playingStoneList, obstacleList = self._obstacleList })
      if shot then
        GameMechanics.applyShotImpulse(self, shot)
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
      love.graphics.setColor(color)
      love.graphics.circle("fill", self._boardX + stone.x, self._boardY + stone.y, Constants.STONE_RADIUS)
      love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
      love.graphics.circle("line", self._boardX + stone.x, self._boardY + stone.y, Constants.STONE_RADIUS)
    end
  end
  if self._isAimDragging and self._aimStoneId then
    local stone = self:getAliveStoneById(self._aimStoneId)
    if stone then
      local sx = self._boardX + stone.x
      local sy = self._boardY + stone.y
      local ax = self._aimWorldX or sx
      local ay = self._aimWorldY or sy
      local dx = sx - ax
      local dy = sy - ay
      local dist = math.sqrt(dx * dx + dy * dy)
      local power = math.min(Constants.MAX_SHOT_POWER, dist * Constants.POWER_PER_PIXEL)
      love.graphics.setColor(0.95, 0.92, 0.35, 0.95)
      love.graphics.setLineWidth(2)
      love.graphics.line(sx, sy, ax, ay)
      love.graphics.setLineWidth(1)
      love.graphics.setFont(FontManager.getFont("small"))
      love.graphics.setColor(Constants.COLOR_TEXT)
      love.graphics.printf(t("match.power_label", {
        power = string.format("%.0f", power)
      }), sx - 56, sy - 28, 112, "center")
    end
  end
  self._effectManager:draw(self._boardX, self._boardY, function(x, y) return x, y end)
  self._playingCardHandBar:draw()
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.combat.title"), 0, 16, Constants.BASE_WORLD_W, "center")
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  local nodeTitle = t(NODE_TITLE_KEY_BY_TYPE[self._nodeType] or "single.node.mob")
  love.graphics.printf(t("single.combat.node_line", { nodeType = nodeTitle, nodeId = self._nodeId }), 0, 52, Constants.BASE_WORLD_W, "center")
  local remain = self._turnEndsAtMs and TimeUtils.getRemainingSeconds(self._turnEndsAtMs) or 0
  local owner = self._activePlayerIndex == 1 and t("single.combat.turn_owner.player") or t("single.combat.turn_owner.ai")
  love.graphics.printf(t("single.combat.info_line", { turnIndex = tostring(self._playingTurnIndex), turnOwner = owner, remainSec = tostring(remain), shotUsed = tostring(self._playingShotUsed), shotBudget = tostring(self._playingShotBudget) }), 0, 636, Constants.BASE_WORLD_W, "center")
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleCombatCore:mousepressed(worldX, worldY, button)
  if self._isFinished then return end
  if button == 2 then
    if self._pendingCardTargetCardId then
      self._pendingCardTargetCardId = nil
      self._pendingCardTargetEntryId = nil
      self._pendingCardTargetId = nil
      self:setStatus(t("single.combat.status.card_target_cancel"), Constants.COLOR_TEXT_SUB)
      return
    end
    self._isAimDragging = false
    self._aimStoneId = nil
    return
  end
  if button ~= 1 then return end
  if self._pendingCardTargetCardId and self:commitPendingTarget(worldX, worldY) then return end
  if self._playingCardHandBar:mousepressed(worldX, worldY, button) then return end
  if not self:isMyTurn() or self._isShotSimulating or self._playingShotUsed >= self._playingShotBudget then return end
  local lx, ly = self:toBoardLocal(worldX, worldY)
  if not lx then return end
  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == 1 and self._lockedStoneIdSet[stone.id] ~= true then
      local dx, dy = stone.x - lx, stone.y - ly
      if dx * dx + dy * dy <= (Constants.STONE_RADIUS + 4) ^ 2 then
        self._isAimDragging = true
        self._aimStoneId = stone.id
        self._aimWorldX = worldX
        self._aimWorldY = worldY
        return
      end
    end
  end
end

function SingleCombatCore:mousereleased(worldX, worldY, button)
  if self._isFinished or button ~= 1 then return end
  if self._playingCardHandBar:mousereleased(worldX, worldY, button) then return end
  if not self._isAimDragging then return end
  local stone = self:getAliveStoneById(self._aimStoneId)
  self._isAimDragging = false
  self._aimStoneId = nil
  if not stone then return end
  local sx = self._boardX + stone.x
  local sy = self._boardY + stone.y
  local dx = sx - worldX
  local dy = sy - worldY
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 8 then
    self:setStatus(t("single.combat.status.shot_too_short"), Constants.COLOR_DANGER)
    return
  end
  GameMechanics.applyShotImpulse(self, { stoneId = stone.id, dirX = dx / len, dirY = dy / len, power = clamp(len * Constants.POWER_PER_PIXEL, 0, Constants.MAX_SHOT_POWER) })
  self._playingShotUsed = self._playingShotUsed + 1
  self._isTurnShotCommitted = true
end

function SingleCombatCore:mousemoved(worldX, worldY, _dx, _dy)
  self._aimWorldX = worldX
  self._aimWorldY = worldY
end

function SingleCombatCore:wheelmoved(_worldX, _worldY, _dx, _dy) end

function SingleCombatCore:keypressed(key)
  if key == "escape" and self._pendingCardTargetCardId then
    self._pendingCardTargetCardId = nil
    self._pendingCardTargetEntryId = nil
    self._pendingCardTargetId = nil
    self:setStatus(t("single.combat.status.card_target_cancel"), Constants.COLOR_TEXT_SUB)
    return true
  end
  return false
end

return SingleCombatCore
