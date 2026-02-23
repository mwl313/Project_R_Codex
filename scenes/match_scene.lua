--[[
파일명: match_scene.lua
모듈명: MatchScene

역할:
- Phase 3 매치 진행 화면(배치/공개/카드선택/턴 플레이 기본)
- 배치 클릭 입력, 제출, 공개 렌더링, 카드 선택 처리

외부에서 사용 가능한 함수:
- MatchScene.new(app)

주의:
- 모든 좌표 입력은 world 좌표 기준으로 처리한다
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local UIDraw = require("ui.ui_draw")
local CardAnimator = require("ui.card_animator")
local CardHandBar = require("ui.card_hand_bar")
local InGameChat = require("ui.in_game_chat")
local CutsceneManager = require("ui.cutscene_manager")
local EffectManager = require("effects.effect_manager")
local Abilities = require("abilities")
local GameMechanics = require("game_mechanics")
local TimeUtils = require("utils.time_utils")
local InputCaptureGuard = require("utils.input_capture_guard")

local MatchScene = {}
MatchScene.__index = MatchScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function getCardSelectPanelRect(boardX, boardY)
  local panelMarginX = 70
  local panelMarginTop = 54
  local panelMarginBottom = 54
  return {
    x = boardX + panelMarginX,
    y = boardY + panelMarginTop,
    w = Constants.BOARD_W - panelMarginX * 2,
    h = Constants.BOARD_H - panelMarginTop - panelMarginBottom
  }
end

local function cloneStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      x = stone.x,
      y = stone.y
    }
  end
  return cloned
end

local function cloneStringList(valueList)
  local cloned = {}
  for _, value in ipairs(valueList or {}) do
    cloned[#cloned + 1] = tostring(value)
  end
  return cloned
end

local function clonePlayingStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      ownerPlayerIndex = stone.ownerPlayerIndex,
      x = stone.x,
      y = stone.y,
      alive = stone.alive ~= false
    }
  end
  return cloned
end

local function cloneObstacleList(obstacleList)
  local cloned = {}
  for _, obstacle in ipairs(obstacleList or {}) do
    cloned[#cloned + 1] = {
      id = obstacle.id,
      x = obstacle.x,
      y = obstacle.y,
      width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH,
      height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    }
  end
  return cloned
end

local function listToSet(valueList)
  local valueSet = {}
  for _, value in ipairs(valueList or {}) do
    valueSet[tostring(value)] = true
  end
  return valueSet
end

local function normalizeInvincibleTurnByPlayer(value)
  return Abilities.normalizeInvincibleTurnByPlayer(value)
end

local function createDefaultRoomState()
  return {
    phase = Constants.PHASE_PLACEMENT_PRIVATE,
    timers = {},
    match = {
      firstPlayerIndex = nil,
      placement = {
        mySubmitted = false,
        opponentSubmitted = false,
        myStones = {},
        revealStones = nil
      },
      cardSelect = {
        myDealtCards = {},
        myPickedCards = {},
        myPickCount = 0,
        myDealtCount = 0,
        opponentDealtCount = 0,
        totalPoolCount = 0,
        myLocked = false,
        opponentLocked = false,
        selectEndsAtMs = nil
      },
      playing = {
        turnIndex = 1,
        activePlayerIndex = 1,
        turnEndsAtMs = nil,
        shotBudget = 1,
        shotUsed = 0,
        hasCardUsedThisTurn = false,
        lockedStoneIds = {},
        obstacles = {},
        invincibleTurnByPlayer = { [1] = nil, [2] = nil },
        shockwaveOwnerPlayerIndex = nil,
        shotCommitted = false,
        awaitingSnapshot = false,
        stones = {}
      }
    },
    result = nil
  }
end

local function containsString(valueList, target)
  for _, value in ipairs(valueList) do
    if value == target then
      return true
    end
  end
  return false
end

local function removeString(valueList, target)
  for index, value in ipairs(valueList) do
    if value == target then
      table.remove(valueList, index)
      return true
    end
  end
  return false
end

local function getCardLabel(cardId)
  return Abilities.getCardLabel(cardId)
end

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function intersectSegmentWithWorldRect(fromX, fromY, toX, toY)
  local minX = 0
  local minY = 0
  local maxX = Constants.BASE_WORLD_W
  local maxY = Constants.BASE_WORLD_H

  if toX >= minX and toX <= maxX and toY >= minY and toY <= maxY then
    return toX, toY
  end

  local dx = toX - fromX
  local dy = toY - fromY
  local bestT = nil
  local bestX = nil
  local bestY = nil

  local function tryHit(t, x, y)
    if t < 0 or t > 1 then
      return
    end
    if x < minX or x > maxX or y < minY or y > maxY then
      return
    end
    if bestT == nil or t < bestT then
      bestT = t
      bestX = x
      bestY = y
    end
  end

  if dx ~= 0 then
    local tLeft = (minX - fromX) / dx
    tryHit(tLeft, minX, fromY + dy * tLeft)
    local tRight = (maxX - fromX) / dx
    tryHit(tRight, maxX, fromY + dy * tRight)
  end
  if dy ~= 0 then
    local tTop = (minY - fromY) / dy
    tryHit(tTop, fromX + dx * tTop, minY)
    local tBottom = (maxY - fromY) / dy
    tryHit(tBottom, fromX + dx * tBottom, maxY)
  end

  if bestX and bestY then
    return bestX, bestY
  end
  return clamp(toX, minX, maxX), clamp(toY, minY, maxY)
end

local SHOT_ERROR_CODE_SET = {
  not_in_phase = true,
  invalid_payload = true,
  turn_mismatch = true,
  not_your_turn = true,
  shot_budget_exceeded = true,
  awaiting_snapshot = true,
  cutscene_active = true,
  invalid_shot_power = true,
  invalid_shot_dir = true,
  timeout = true,
  invalid_shot_stone = true,
  stone_locked_this_turn = true,
  already_shot = true
}

local SHOT_DENY_REASON_KEY_MAP = {
  not_in_phase = "match.shot_deny_reason.not_in_phase",
  invalid_payload = "match.shot_deny_reason.invalid_payload",
  turn_mismatch = "match.shot_deny_reason.turn_mismatch",
  not_your_turn = "match.shot_deny_reason.not_your_turn",
  shot_budget_exceeded = "match.shot_deny_reason.shot_budget_exceeded",
  awaiting_snapshot = "match.shot_deny_reason.awaiting_snapshot",
  cutscene_active = "match.shot_deny_reason.cutscene_active",
  invalid_shot_power = "match.shot_deny_reason.invalid_shot_power",
  invalid_shot_dir = "match.shot_deny_reason.invalid_shot_dir",
  timeout = "match.shot_deny_reason.timeout",
  invalid_shot_stone = "match.shot_deny_reason.invalid_shot_stone",
  stone_locked_this_turn = "match.shot_deny_reason.stone_locked_this_turn",
  already_shot = "match.shot_deny_reason.shot_budget_exceeded"
}

local function cloneVelocityMap(velocityMap)
  local cloned = {}
  for stoneId, velocity in pairs(velocityMap or {}) do
    if type(velocity) == "table" then
      cloned[tostring(stoneId)] = {
        vx = tonumber(velocity.vx) or 0,
        vy = tonumber(velocity.vy) or 0
      }
    end
  end
  return cloned
end

local function buildStoneMapById(stoneList)
  local stoneMap = {}
  for _, stone in ipairs(stoneList or {}) do
    stoneMap[tostring(stone.id)] = stone
  end
  return stoneMap
end

local function easeOutCubic(value)
  local tValue = clamp(value, 0, 1)
  local inverse = 1 - tValue
  return 1 - inverse * inverse * inverse
end

function MatchScene.new(app)
  local boardX = (Constants.BASE_WORLD_W - Constants.BOARD_W) * 0.5
  local boardY = (Constants.BASE_WORLD_H - Constants.BOARD_H) * 0.5

  local instance = {
    _app = app,
    _roomState = createDefaultRoomState(),
    _statusText = t("match.status.syncing"),
    _statusColor = Constants.COLOR_TEXT_SUB,
    _boardX = boardX,
    _boardY = boardY,
    _forcedLocalRole = nil,

    _myStoneList = {},
    _isPlacementSubmitted = false,
    _isSubmitPending = false,
    _revealStoneMap = nil,
    _submitButton = nil,

    _myDealtCardList = {},
    _myPickedCardList = {},
    _selectedCardList = {},
    _myPickCount = 0,
    _myDealtCardCount = 0,
    _opponentDealtCardCount = 0,
    _cardPoolCount = 0,
    _isMyCardLocked = false,
    _isOpponentCardLocked = false,
    _isCardPickPending = false,
    _cardSelectEndsAtMs = nil,
    _cardOptionButtonList = {},
    _cardConfirmButton = nil,
    _cardAnimator = nil,

    _playingStoneList = {},
    _playingTurnIndex = 1,
    _activePlayerIndex = 1,
    _turnEndsAtMs = nil,
    _playingShotBudget = 1,
    _playingShotUsed = 0,
    _hasUsedCardThisTurn = false,
    _lockedStoneIdSet = {},
    _obstacleList = {},
    _invincibleTurnByPlayer = { [1] = nil, [2] = nil },
    _shockwaveOwnerPlayerIndex = nil,
    _shockwaveSourceStoneId = nil,
    _isPlayingShotCommitted = false,
    _isPlayingAwaitingSnapshot = false,
    _isTurnShotPending = false,
    _isCardUsePending = false,
    _pendingCardTargetId = nil,
    _isSurrenderPending = false,
    _isAimDragging = false,
    _isAimRelativeMode = false,
    _aimStoneId = nil,
    _aimStartWorldX = nil,
    _aimStartWorldY = nil,
    _aimAccumWorldDX = 0,
    _aimAccumWorldDY = 0,
    _aimLastMouseWorldX = nil,
    _aimLastMouseWorldY = nil,
    _lastAutoSnapshotTurnIndex = nil,
    _stoneVelocityMap = {},
    _simAccumulatorSec = 0,
    _simElapsedSec = 0,
    _isShotSimulating = false,
    _shouldSendSnapshotAfterSim = false,
    _predictiveShotSeq = 0,
    _predictivePendingShotMap = {},
    _predictivePendingShotIdList = {},
    _predictiveGhostStoneIdSet = {},
    _predictiveRollbackState = nil,
    _predictiveRollbackInputLockSec = 0,
    _shotToast = nil,
    _playingCardButtonList = {},
    _playingCardHandBar = nil,
    _inGameChat = nil,
    _cutsceneManager = nil,
    _serverCutsceneState = {
      active = false,
      cutsceneId = nil,
      ownerPlayerIndex = nil,
      cardId = nil,
      skillName = nil,
      cutsceneDurationMs = nil,
      pausedRemainingMs = nil
    },
    _cutsceneFrozenRemainSec = nil,
    _optimisticConsumedCardIdSet = {},
    _pendingDeclaredTargetCardId = nil,
    _surrenderButton = nil,
    _resultRematchButton = nil,
    _resultLobbyButton = nil,
    _isResultVotePending = false,
    _myResultVote = nil,
    _opponentResultVote = nil
  }
  setmetatable(instance, MatchScene)
  instance._effectManager = EffectManager.new()

  instance._submitButton = Button.new({
    x = Constants.BASE_WORLD_W - 260,
    y = 666,
    w = 200,
    h = 42,
    label = t("match.button.submit_placement"),
    onClick = function()
      instance:submitPlacement()
    end
  })

  instance._cardConfirmButton = Button.new({
    x = 0,
    y = 0,
    w = 220,
    h = 42,
    label = t("match.button.confirm_selection"),
    onClick = function()
      instance:submitCardPick()
    end
  })

  instance._surrenderButton = Button.new({
    x = Constants.BASE_WORLD_W - 250,
    y = 16,
    w = 220,
    h = 40,
    label = t("match.button.surrender"),
    color = Constants.COLOR_DANGER,
    hoverColor = { 0.80, 0.28, 0.30, 1.0 },
    onClick = function()
      instance:requestSurrender()
    end
  })

  instance._resultRematchButton = Button.new({
    x = 0,
    y = 0,
    w = 190,
    h = 44,
    label = t("match.button.rematch"),
    onClick = function()
      instance:requestResultVote("rematch")
    end
  })

  instance._resultLobbyButton = Button.new({
    x = 0,
    y = 0,
    w = 190,
    h = 44,
    label = t("match.button.menu"),
    color = Constants.COLOR_DANGER,
    hoverColor = { 0.80, 0.28, 0.30, 1.0 },
    onClick = function()
      instance:requestResultVote("to_lobby")
    end
  })
  instance._playingCardHandBar = CardHandBar.new({
    boardCenterX = boardX + Constants.BOARD_W * 0.5,
    boardCenterY = boardY + Constants.BOARD_H * 0.5,
    canUseCard = function(cardId)
      return instance:canUseCardInTurn(cardId)
    end,
    onCardDeclared = function(cardId)
      return instance:handleHandCardDeclared(cardId)
    end,
    onCardBlocked = function(_cardId)
      instance:handleHandCardBlocked()
    end
  })
  instance._inGameChat = InGameChat.new(app)
  instance._cutsceneManager = CutsceneManager.new()

  return instance
end

function MatchScene:enter(params)
  self._roomState = createDefaultRoomState()
  self._forcedLocalRole = params and params.localRole or nil

  self._myStoneList = {}
  self._isPlacementSubmitted = false
  self._isSubmitPending = false
  self._revealStoneMap = nil

  self._myDealtCardList = {}
  self._myPickedCardList = {}
  self._selectedCardList = {}
  self._myPickCount = 0
  self._myDealtCardCount = 0
  self._opponentDealtCardCount = 0
  self._cardPoolCount = 0
  self._isMyCardLocked = false
  self._isOpponentCardLocked = false
  self._isCardPickPending = false
  self._cardSelectEndsAtMs = nil
  self._cardOptionButtonList = {}
  self._cardAnimator = nil

  self._playingStoneList = {}
  self._playingTurnIndex = 1
  self._activePlayerIndex = 1
  self._turnEndsAtMs = nil
  self._playingShotBudget = 1
  self._playingShotUsed = 0
  self._hasUsedCardThisTurn = false
  self._lockedStoneIdSet = {}
  self._obstacleList = {}
  self._invincibleTurnByPlayer = { [1] = nil, [2] = nil }
  self._shockwaveOwnerPlayerIndex = nil
  self._shockwaveSourceStoneId = nil
  self._isPlayingShotCommitted = false
  self._isPlayingAwaitingSnapshot = false
  self._isTurnShotPending = false
  self._isCardUsePending = false
  self._pendingCardTargetId = nil
  self._isSurrenderPending = false
  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  self._lastAutoSnapshotTurnIndex = nil
  self._stoneVelocityMap = {}
  self._simAccumulatorSec = 0
  self._simElapsedSec = 0
  self._isShotSimulating = false
  self._shouldSendSnapshotAfterSim = false
  self._predictiveShotSeq = 0
  self:clearPredictiveState()
  self._shotToast = nil
  self._playingCardButtonList = {}
  self._optimisticConsumedCardIdSet = {}
  self._pendingDeclaredTargetCardId = nil
  self._isResultVotePending = false
  self._myResultVote = nil
  self._opponentResultVote = nil
  self._serverCutsceneState = {
    active = false,
    cutsceneId = nil,
    ownerPlayerIndex = nil,
    cardId = nil,
    skillName = nil,
    cutsceneDurationMs = nil,
    pausedRemainingMs = nil
  }
  self._cutsceneFrozenRemainSec = nil
  if self._inGameChat then
    self._inGameChat:reset()
  end
  if self._cutsceneManager then
    self._cutsceneManager:reset()
  end
  if self._effectManager then
    self._effectManager:clear()
  end

  if params and type(params.roomState) == "table" then
    self:applyRoomState(params.roomState)
  end
  self:refreshPlayingCardHand()
end

function MatchScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function MatchScene:isServerCutsceneActive()
  return self._serverCutsceneState and self._serverCutsceneState.active == true
end

function MatchScene:isCutsceneInputBlocked()
  if self._cutsceneManager and self._cutsceneManager:isInputBlocked() then
    return true
  end
  return self:isServerCutsceneActive()
end

function MatchScene:resolveCutsceneSkillName(cardId, fallbackSkillName)
  if cardId and cardId ~= "" then
    return getCardLabel(cardId)
  end
  return tostring(fallbackSkillName or t("common.unknown"))
end

function MatchScene:startSkillCutscene(params)
  if not self._cutsceneManager then
    return
  end
  local payload = params or {}
  local ownerPlayerIndex = payload.ownerPlayerIndex == 1 and 1 or 2
  local cardId = tostring(payload.cardId or "")
  local cutsceneId = tostring(payload.cutsceneId or "")
  local skillName = self:resolveCutsceneSkillName(cardId, payload.skillName)
  local isLocalUser = ownerPlayerIndex == self:getMyPlayerIndex()
  local wasStarted = self._cutsceneManager:start({
    cutsceneId = cutsceneId ~= "" and cutsceneId or nil,
    cardId = cardId,
    ownerPlayerIndex = ownerPlayerIndex,
    isLocalUser = isLocalUser,
    skillName = skillName,
    cutsceneDurationMs = payload.cutsceneDurationMs
  })
  self._cutsceneManager:setBlockedByServerPaused(true)
  self._serverCutsceneState = {
    active = true,
    cutsceneId = cutsceneId,
    ownerPlayerIndex = ownerPlayerIndex,
    cardId = cardId,
    skillName = tostring(payload.skillName or cardId),
    cutsceneDurationMs = tonumber(payload.cutsceneDurationMs),
    pausedRemainingMs = tonumber(payload.pausedRemainingMs)
  }
  if type(payload.pausedRemainingMs) == "number" then
    self._cutsceneFrozenRemainSec = math.max(0, math.ceil(payload.pausedRemainingMs / 1000))
  elseif self._turnEndsAtMs then
    self._cutsceneFrozenRemainSec = TimeUtils.getRemainingSeconds(self._turnEndsAtMs)
  end
  self._pendingCardTargetId = nil
  self:cancelAimDrag(true)
  if self._playingCardHandBar then
    self._playingCardHandBar:cancelCardDrag(false)
  end
  self:cutsceneLog("START", string.format("id=%s card=%s owner=%s", tostring(cutsceneId), tostring(cardId), tostring(ownerPlayerIndex)))
  if wasStarted then
    self:setStatus(t("match.status.cutscene_playing", {
      cardLabel = skillName
    }), Constants.COLOR_TEXT_SUB)
  end
end

function MatchScene:stopSkillCutscene()
  if self._cutsceneManager then
    self._cutsceneManager:setBlockedByServerPaused(false)
  end
  self:cutsceneLog("END", tostring(self._serverCutsceneState and self._serverCutsceneState.cutsceneId or ""))
  self._serverCutsceneState = {
    active = false,
    cutsceneId = nil,
    ownerPlayerIndex = nil,
    cardId = nil,
    skillName = nil,
    cutsceneDurationMs = nil,
    pausedRemainingMs = nil
  }
  self._cutsceneFrozenRemainSec = nil
end

function MatchScene:syncCutsceneStateFromRoomState()
  local playing = self._roomState and self._roomState.match and self._roomState.match.playing or nil
  local cutscene = playing and playing.cutscene or nil
  if type(cutscene) == "table" and cutscene.active == true then
    local incomingCutsceneId = tostring(cutscene.cutsceneId or "")
    local currentCutsceneId = self._serverCutsceneState and tostring(self._serverCutsceneState.cutsceneId or "") or ""
    local shouldRestart = incomingCutsceneId ~= "" and incomingCutsceneId ~= currentCutsceneId
    local ownerPlayerIndex = cutscene.ownerPlayerIndex == 1 and 1 or 2
    local cardId = tostring(cutscene.cardId or "")
    if shouldRestart or (not self:isServerCutsceneActive()) then
      self:startSkillCutscene({
        cutsceneId = incomingCutsceneId,
        ownerPlayerIndex = ownerPlayerIndex,
        cardId = cardId,
        skillName = cutscene.skillName,
        cutsceneDurationMs = cutscene.durationMs,
        pausedRemainingMs = cutscene.pausedRemainingMs
      })
    else
      self._serverCutsceneState.active = true
      self._serverCutsceneState.pausedRemainingMs = tonumber(cutscene.pausedRemainingMs)
      if self._cutsceneManager then
        self._cutsceneManager:setBlockedByServerPaused(true)
      end
    end
    if type(cutscene.pausedRemainingMs) == "number" then
      self._cutsceneFrozenRemainSec = math.max(0, math.ceil(cutscene.pausedRemainingMs / 1000))
    end
    return
  end
  self:stopSkillCutscene()
end

function MatchScene:cutsceneLog(tag, detail)
  if Constants.CUTSCENE_DEBUG_LOG ~= true then
    return
  end
  print(string.format("[CUTSCENE][MATCH][%s] %s", tostring(tag), tostring(detail or "")))
end

function MatchScene:predictiveLog(tag, detail)
  if Constants.PREDICTIVE_SHOT_DEBUG_LOG ~= true then
    return
  end
  print(string.format("[PREDICTIVE_SHOT][%s] %s", tostring(tag), tostring(detail or "")))
end

function MatchScene:isShotErrorCode(code)
  return SHOT_ERROR_CODE_SET[tostring(code)] == true
end

function MatchScene:getShotDenyToastText(reasonCode)
  local reasonKey = SHOT_DENY_REASON_KEY_MAP[tostring(reasonCode)]
  if reasonKey then
    return t(reasonKey)
  end
  return t("match.status.server_error", {
    code = tostring(reasonCode or t("common.unknown"))
  })
end

function MatchScene:showShotToast(text, color, durationSec)
  if type(text) ~= "string" or text == "" then
    return
  end
  local toastDuration = durationSec or Constants.PREDICTIVE_SHOT_TOAST_SEC
  self._shotToast = {
    text = text,
    color = color or Constants.COLOR_DANGER,
    remainingSec = toastDuration,
    totalSec = toastDuration
  }
end

function MatchScene:updateShotToast(dt)
  if not self._shotToast then
    return
  end
  self._shotToast.remainingSec = self._shotToast.remainingSec - dt
  if self._shotToast.remainingSec <= 0 then
    self._shotToast = nil
  end
end

function MatchScene:drawShotToast()
  if not self._shotToast then
    return
  end

  local toast = self._shotToast
  local fadeRatio = 1
  if toast.totalSec > 0 then
    local nearEndSec = math.min(0.24, toast.totalSec)
    if toast.remainingSec < nearEndSec then
      fadeRatio = clamp(toast.remainingSec / nearEndSec, 0, 1)
    end
  end

  local panelW = 540
  local panelH = 38
  local panelX = (Constants.BASE_WORLD_W - panelW) * 0.5
  local panelY = self._boardY + Constants.BOARD_H + 18
  love.graphics.setColor(0.04, 0.05, 0.08, 0.82 * fadeRatio)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)

  local toastColor = toast.color or Constants.COLOR_DANGER
  love.graphics.setColor(toastColor[1], toastColor[2], toastColor[3], (toastColor[4] or 1.0) * fadeRatio)
  love.graphics.setLineWidth(1.2)
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT[1], Constants.COLOR_TEXT[2], Constants.COLOR_TEXT[3], fadeRatio)
  love.graphics.printf(toast.text, panelX + 14, panelY + 10, panelW - 28, "center")
end

function MatchScene:isPredictiveRollbackLocked()
  return (self._predictiveRollbackInputLockSec or 0) > 0
end

function MatchScene:hasPendingPredictiveShot()
  return next(self._predictivePendingShotMap or {}) ~= nil
end

function MatchScene:refreshPredictiveGhostStone(stoneId)
  local stoneKey = tostring(stoneId or "")
  if stoneKey == "" then
    return
  end
  for _, pendingShotId in ipairs(self._predictivePendingShotIdList) do
    local pendingShot = self._predictivePendingShotMap[pendingShotId]
    if pendingShot and tostring(pendingShot.stoneId) == stoneKey then
      self._predictiveGhostStoneIdSet[stoneKey] = true
      return
    end
  end
  if self._predictiveRollbackState and tostring(self._predictiveRollbackState.stoneId) == stoneKey then
    self._predictiveGhostStoneIdSet[stoneKey] = true
    return
  end
  self._predictiveGhostStoneIdSet[stoneKey] = nil
end

function MatchScene:removePredictiveShotById(localShotId, keepGhost)
  local pendingShot = self._predictivePendingShotMap[localShotId]
  if not pendingShot then
    return nil
  end
  self._predictivePendingShotMap[localShotId] = nil
  for index, candidateId in ipairs(self._predictivePendingShotIdList) do
    if candidateId == localShotId then
      table.remove(self._predictivePendingShotIdList, index)
      break
    end
  end
  if not keepGhost then
    self:refreshPredictiveGhostStone(pendingShot.stoneId)
  end
  self._isTurnShotPending = self:hasPendingPredictiveShot()
  return pendingShot
end

function MatchScene:clearPredictiveState()
  self._predictivePendingShotMap = {}
  self._predictivePendingShotIdList = {}
  self._predictiveGhostStoneIdSet = {}
  self._predictiveRollbackState = nil
  self._predictiveRollbackInputLockSec = 0
  self._isTurnShotPending = false
end

function MatchScene:capturePredictivePreShotState()
  return {
    playingStoneList = clonePlayingStoneList(self._playingStoneList),
    stoneVelocityMap = cloneVelocityMap(self._stoneVelocityMap),
    playingShotUsed = self._playingShotUsed,
    playingShotBudget = self._playingShotBudget,
    isPlayingShotCommitted = self._isPlayingShotCommitted,
    isPlayingAwaitingSnapshot = self._isPlayingAwaitingSnapshot,
    shockwaveSourceStoneId = self._shockwaveSourceStoneId
  }
end

function MatchScene:createPredictiveShot(shotPayload)
  self._predictiveShotSeq = self._predictiveShotSeq + 1
  local localShotId = self._predictiveShotSeq
  local pendingShot = {
    localShotId = localShotId,
    turnIndex = shotPayload.turnIndex,
    shooterPlayerIndex = self:getMyPlayerIndex(),
    stoneId = shotPayload.stoneId,
    dirX = shotPayload.dirX,
    dirY = shotPayload.dirY,
    power = shotPayload.power,
    startedAtMs = TimeUtils.nowEpochMs(),
    preStateSnapshot = self:capturePredictivePreShotState()
  }
  self._predictivePendingShotMap[localShotId] = pendingShot
  self._predictivePendingShotIdList[#self._predictivePendingShotIdList + 1] = localShotId
  self._predictiveGhostStoneIdSet[tostring(shotPayload.stoneId)] = true
  self._isTurnShotPending = true
  return pendingShot
end

function MatchScene:getLatestPendingPredictiveShot()
  local listLength = #self._predictivePendingShotIdList
  if listLength <= 0 then
    return nil
  end
  local localShotId = self._predictivePendingShotIdList[listLength]
  return self._predictivePendingShotMap[localShotId]
end

function MatchScene:findPredictiveShotIdByAcceptedPayload(payload)
  local payloadStoneId = tostring(payload.stoneId or "")
  local payloadTurnIndex = tonumber(payload.turnIndex)
  local payloadPlayerIndex = tonumber(payload.playerIndex)
  local payloadPower = tonumber(payload.power)
  local payloadDirX = tonumber(payload.dirX)
  local payloadDirY = tonumber(payload.dirY)
  for _, localShotId in ipairs(self._predictivePendingShotIdList) do
    local pendingShot = self._predictivePendingShotMap[localShotId]
    if pendingShot then
      local turnMatch = payloadTurnIndex == nil or pendingShot.turnIndex == payloadTurnIndex
      local stoneMatch = payloadStoneId == "" or tostring(pendingShot.stoneId) == payloadStoneId
      local playerMatch = payloadPlayerIndex == nil or pendingShot.shooterPlayerIndex == payloadPlayerIndex
      local powerMatch = payloadPower == nil or math.abs((pendingShot.power or 0) - payloadPower) <= 0.0001
      local dirMatch = true
      if payloadDirX ~= nil and payloadDirY ~= nil then
        dirMatch = math.abs((pendingShot.dirX or 0) - payloadDirX) <= 0.0001
          and math.abs((pendingShot.dirY or 0) - payloadDirY) <= 0.0001
      end
      if turnMatch and stoneMatch and playerMatch and powerMatch and dirMatch then
        return localShotId
      end
    end
  end
  return nil
end

function MatchScene:confirmPredictiveShotByAcceptedPayload(payload)
  local localShotId = self:findPredictiveShotIdByAcceptedPayload(payload)
  if not localShotId then
    return nil
  end
  local pendingShot = self:removePredictiveShotById(localShotId, false)
  if pendingShot then
    self:predictiveLog("ACCEPT", "localShotId=" .. tostring(localShotId))
  end
  return pendingShot
end

function MatchScene:isPredictiveGhostStone(stoneId)
  return self._predictiveGhostStoneIdSet[tostring(stoneId or "")] == true
end

function MatchScene:beginPredictiveRollback(pendingShot, reasonCode)
  if not pendingShot or type(pendingShot.preStateSnapshot) ~= "table" then
    return
  end

  self._shouldSendSnapshotAfterSim = false
  self:stopShotSimulation()
  self:cancelAimDrag(true)

  local currentStoneList = clonePlayingStoneList(self._playingStoneList)
  self._predictiveRollbackState = {
    elapsedSec = 0,
    durationSec = math.max(0.01, Constants.PREDICTIVE_SHOT_ROLLBACK_SEC),
    fromStoneMap = buildStoneMapById(currentStoneList),
    targetSnapshot = pendingShot.preStateSnapshot,
    stoneId = pendingShot.stoneId
  }
  self._predictiveRollbackInputLockSec = math.max(self._predictiveRollbackInputLockSec or 0, Constants.PREDICTIVE_SHOT_INPUT_LOCK_SEC)
  self._isTurnShotPending = false
  self._isPlayingShotCommitted = false
  self._isPlayingAwaitingSnapshot = false
  self._predictiveGhostStoneIdSet[tostring(pendingShot.stoneId)] = true
  self:showShotToast(self:getShotDenyToastText(reasonCode), Constants.COLOR_DANGER, Constants.PREDICTIVE_SHOT_TOAST_SEC)
  self:predictiveLog("DENY", "localShotId=" .. tostring(pendingShot.localShotId) .. ", code=" .. tostring(reasonCode))
end

function MatchScene:updatePredictiveRollback(dt)
  local rollbackState = self._predictiveRollbackState
  if not rollbackState then
    return
  end
  local targetSnapshot = rollbackState.targetSnapshot
  if type(targetSnapshot) ~= "table" or type(targetSnapshot.playingStoneList) ~= "table" then
    self._predictiveRollbackState = nil
    return
  end

  rollbackState.elapsedSec = rollbackState.elapsedSec + dt
  local progress = clamp(rollbackState.elapsedSec / rollbackState.durationSec, 0, 1)
  local easedProgress = easeOutCubic(progress)
  local nextStoneList = {}
  for _, targetStone in ipairs(targetSnapshot.playingStoneList) do
    local fromStone = rollbackState.fromStoneMap[tostring(targetStone.id)] or targetStone
    nextStoneList[#nextStoneList + 1] = {
      id = targetStone.id,
      ownerPlayerIndex = targetStone.ownerPlayerIndex,
      alive = targetStone.alive ~= false,
      x = fromStone.x + (targetStone.x - fromStone.x) * easedProgress,
      y = fromStone.y + (targetStone.y - fromStone.y) * easedProgress
    }
  end
  self._playingStoneList = nextStoneList
  self:syncStoneVelocityMap()
  for _, velocity in pairs(self._stoneVelocityMap) do
    velocity.vx = 0
    velocity.vy = 0
  end

  if progress < 1 then
    return
  end

  self._playingStoneList = clonePlayingStoneList(targetSnapshot.playingStoneList)
  self._stoneVelocityMap = cloneVelocityMap(targetSnapshot.stoneVelocityMap)
  self._playingShotUsed = targetSnapshot.playingShotUsed or self._playingShotUsed
  self._playingShotBudget = targetSnapshot.playingShotBudget or self._playingShotBudget
  self._isPlayingShotCommitted = targetSnapshot.isPlayingShotCommitted == true
  self._isPlayingAwaitingSnapshot = targetSnapshot.isPlayingAwaitingSnapshot == true
  self._shockwaveSourceStoneId = targetSnapshot.shockwaveSourceStoneId
  self._predictiveRollbackState = nil
  self._isTurnShotPending = self:hasPendingPredictiveShot()
  self:refreshPredictiveGhostStone(rollbackState.stoneId)
  self:predictiveLog("ROLLBACK_DONE", "stoneId=" .. tostring(rollbackState.stoneId))
end

function MatchScene:validateLocalShotAttempt(stone, dirCanonicalX, dirCanonicalY, power)
  if not self:isPlayingPhase() then
    return "not_in_phase"
  end
  if type(self._playingTurnIndex) ~= "number" then
    return "turn_mismatch"
  end
  if not self:isMyTurn() then
    return "not_your_turn"
  end
  if self._isPlayingAwaitingSnapshot then
    return "awaiting_snapshot"
  end
  if self._playingShotUsed >= self._playingShotBudget then
    return "shot_budget_exceeded"
  end
  if self._turnEndsAtMs and TimeUtils.nowEpochMs() > self._turnEndsAtMs then
    return "timeout"
  end
  if not stone or stone.alive == false or stone.ownerPlayerIndex ~= self:getMyPlayerIndex() then
    return "invalid_shot_stone"
  end
  if self._lockedStoneIdSet[stone.id] then
    return "stone_locked_this_turn"
  end

  local directionLength = math.sqrt((dirCanonicalX or 0) * (dirCanonicalX or 0) + (dirCanonicalY or 0) * (dirCanonicalY or 0))
  if not directionLength or directionLength <= 0 or directionLength ~= directionLength then
    return "invalid_shot_dir"
  end
  if type(power) ~= "number" or power ~= power or power < 0 or power > Constants.MAX_SHOT_POWER then
    return "invalid_shot_power"
  end
  return nil
end

function MatchScene:getMyRole()
  if self._forcedLocalRole == "host" or self._forcedLocalRole == "guest" then
    return self._forcedLocalRole
  end
  local session = self._app:getSession()
  return session and session.role or nil
end

function MatchScene:getMyPlayerIndex()
  local role = self:getMyRole()
  if role == "host" then
    return 1
  end
  if role == "guest" then
    return 2
  end
  return nil
end

function MatchScene:isPlacementPhase()
  return self._roomState.phase == Constants.PHASE_PLACEMENT_PRIVATE
end

function MatchScene:isCardSelectPhase()
  return self._roomState.phase == Constants.PHASE_CARD_SELECT
end

function MatchScene:isPlayingPhase()
  return self._roomState.phase == Constants.PHASE_PLAYING
end

function MatchScene:isInGameChatAvailable()
  local phase = self._roomState.phase
  return phase == Constants.PHASE_PLAYING or phase == Constants.PHASE_RESULT
end

function MatchScene:isMyTurn()
  return self:isPlayingPhase() and self:getMyPlayerIndex() == self._activePlayerIndex
end

function MatchScene:isShotInputEnabled()
  if self:isCutsceneInputBlocked() then
    return false
  end
  return self:isMyTurn()
    and (not self._isPlayingShotCommitted)
    and (not self._isPlayingAwaitingSnapshot)
    and (not self._isTurnShotPending)
    and (not self:hasPendingPredictiveShot())
    and (not self._predictiveRollbackState)
    and (not self:isPredictiveRollbackLocked())
    and (not self._isCardUsePending)
    and (not self._pendingCardTargetId)
end

function MatchScene:isRevealVisiblePhase()
  local phase = self._roomState.phase
  return phase == Constants.PHASE_PLACEMENT_REVEAL or phase == Constants.PHASE_CARD_SELECT or phase == Constants.PHASE_PLAYING or phase == Constants.PHASE_RESULT
end

function MatchScene:canonicalToLocal(canonicalX, canonicalY)
  local role = self:getMyRole()
  if role == "guest" then
    return canonicalX, Constants.BOARD_H - canonicalY
  end
  return canonicalX, canonicalY
end

function MatchScene:localToCanonical(localX, localY)
  local role = self:getMyRole()
  if role == "guest" then
    return localX, Constants.BOARD_H - localY
  end
  return localX, localY
end

function MatchScene:toBoardLocal(worldX, worldY)
  local localX = worldX - self._boardX
  local localY = worldY - self._boardY
  if localX < 0 or localY < 0 or localX > Constants.BOARD_W or localY > Constants.BOARD_H then
    return nil, nil
  end
  return localX, localY
end

function MatchScene:toBoardLocalNoClamp(worldX, worldY)
  return worldX - self._boardX, worldY - self._boardY
end

function MatchScene:canPlaceAtCanonical(canonicalX, canonicalY)
  local minX = Constants.STONE_RADIUS
  local maxX = Constants.BOARD_W - Constants.STONE_RADIUS
  local minY = Constants.STONE_RADIUS
  local maxY = Constants.BOARD_H - Constants.STONE_RADIUS
  if canonicalX < minX or canonicalX > maxX or canonicalY < minY or canonicalY > maxY then
    return false, t("match.validate.out_of_board")
  end

  local centerY = Constants.BOARD_H * 0.5
  local role = self:getMyRole()
  if role == "host" and canonicalY < centerY + Constants.NO_PLACE_BUFFER then
    return false, t("match.validate.must_place_own_zone")
  end
  if role == "guest" and canonicalY > centerY - Constants.NO_PLACE_BUFFER then
    return false, t("match.validate.must_place_own_zone")
  end

  for _, stone in ipairs(self._myStoneList) do
    local dx = stone.x - canonicalX
    local dy = stone.y - canonicalY
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < Constants.MIN_PLACE_DISTANCE then
      return false, t("match.validate.too_close_existing")
    end
  end

  return true, nil
end

function MatchScene:getAliveStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId and stone.alive ~= false then
      return stone
    end
  end
  return nil
end

function MatchScene:findAimStoneAt(worldX, worldY)
  local myPlayerIndex = self:getMyPlayerIndex()
  if not myPlayerIndex then
    return nil
  end

  for _, stone in ipairs(self._playingStoneList) do
    if stone.alive ~= false and stone.ownerPlayerIndex == myPlayerIndex and (not self._lockedStoneIdSet[stone.id]) then
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      local stoneWorldX = self._boardX + localX
      local stoneWorldY = self._boardY + localY
      local dx = worldX - stoneWorldX
      local dy = worldY - stoneWorldY
      if math.sqrt(dx * dx + dy * dy) <= Constants.STONE_RADIUS + 6 then
        return stone
      end
    end
  end
  return nil
end

function MatchScene:getPlayingStoneById(stoneId)
  for _, stone in ipairs(self._playingStoneList) do
    if stone.id == stoneId then
      return stone
    end
  end
  return nil
end

function MatchScene:getStoneVelocity(stoneId)
  local velocity = self._stoneVelocityMap[stoneId]
  if not velocity then
    velocity = { vx = 0, vy = 0 }
    self._stoneVelocityMap[stoneId] = velocity
  end
  return velocity
end

function MatchScene:isInvincibleOnCurrentTurn(playerIndex)
  return Abilities.isInvincibleOnCurrentTurn(self, playerIndex)
end

function MatchScene:isShockwaveShotStone(stoneId)
  return Abilities.isShockwaveShotStone(self, stoneId)
end

function MatchScene:applyShockwaveFromPoint(centerX, centerY)
  Abilities.applyShockwaveFromPoint(self, centerX, centerY)
end

function MatchScene:applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
  return Abilities.applyInvincibleCollisionResponse(firstInvincible, secondInvincible, normalX, normalY, firstVelocity, secondVelocity)
end

function MatchScene:resetStoneVelocities()
  GameMechanics.resetStoneVelocities(self)
end

function MatchScene:resolveObstacleCollision(stone, obstacle)
  return GameMechanics.resolveObstacleCollision(self, stone, obstacle)
end

function MatchScene:syncStoneVelocityMap()
  GameMechanics.syncStoneVelocityMap(self)
end

function MatchScene:startShotSimulation()
  GameMechanics.startShotSimulation(self)
end

function MatchScene:stopShotSimulation()
  GameMechanics.stopShotSimulation(self)
end

function MatchScene:applyShotImpulse(shotPayload)
  GameMechanics.applyShotImpulse(self, shotPayload)
end

function MatchScene:resolveStoneCollision(firstStone, secondStone)
  return GameMechanics.resolveStoneCollision(self, firstStone, secondStone)
end

function MatchScene:simulateShotStep(stepSec)
  GameMechanics.simulateShotStep(self, stepSec)
end

function MatchScene:hasAnyStoneInMotion()
  return GameMechanics.hasAnyStoneInMotion(self)
end

function MatchScene:updateShotSimulation(dt)
  GameMechanics.updateShotSimulation(self, dt)
end

function MatchScene:addPlacementByWorld(worldX, worldY)
  if not self:isPlacementPhase() then
    return
  end
  if self._isPlacementSubmitted or self._isSubmitPending then
    self:setStatus(t("match.status.placement_already_submitted"), Constants.COLOR_TEXT_SUB)
    return
  end
  if #self._myStoneList >= Constants.STONE_COUNT_PER_PLAYER then
    self:setStatus(t("match.status.placement_count_full"), Constants.COLOR_DANGER)
    return
  end

  local boardLocalX, boardLocalY = self:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    return
  end

  local canonicalX, canonicalY = self:localToCanonical(boardLocalX, boardLocalY)
  local canPlace, reasonText = self:canPlaceAtCanonical(canonicalX, canonicalY)
  if not canPlace then
    self:setStatus(reasonText, Constants.COLOR_DANGER)
    return
  end

  local playerIndex = self:getMyPlayerIndex() or 0
  local stoneId = string.format("p%d_s%d", playerIndex, #self._myStoneList + 1)
  self._myStoneList[#self._myStoneList + 1] = {
    id = stoneId,
    x = canonicalX,
    y = canonicalY
  }
  self:setStatus(t("match.status.placement_progress", {
    count = #self._myStoneList,
    max = Constants.STONE_COUNT_PER_PLAYER
  }), Constants.COLOR_TEXT_SUB)
end

function MatchScene:submitPlacement()
  if not self:isPlacementPhase() then
    return
  end
  if self._isPlacementSubmitted or self._isSubmitPending then
    return
  end
  if #self._myStoneList ~= Constants.STONE_COUNT_PER_PLAYER then
    self:setStatus(t("match.status.placement_need_all"), Constants.COLOR_DANGER)
    return
  end

  self._app:sendEnvelope("client.match.placement.submit", {
    stones = cloneStoneList(self._myStoneList)
  })
  self._isSubmitPending = true
  self:setStatus(t("match.status.placement_submitted_waiting"), Constants.COLOR_TEXT_SUB)
end

function MatchScene:rebuildCardOptionButtons()
  self._cardOptionButtonList = {}
  self:ensureCardAnimator()
end

function MatchScene:getOpponentDealtCardCount()
  if type(self._opponentDealtCardCount) == "number" and self._opponentDealtCardCount >= 0 then
    return self._opponentDealtCardCount
  end

  local myDealCount = #self._myDealtCardList
  local totalPoolCount = tonumber(self._cardPoolCount) or 0
  if totalPoolCount > 0 then
    return math.max(0, math.floor(totalPoolCount) - myDealCount)
  end

  if myDealCount == 2 then
    return 3
  end
  if myDealCount == 3 then
    return 2
  end
  return math.max(0, myDealCount)
end

function MatchScene:getCardPoolCount()
  if type(self._cardPoolCount) == "number" and self._cardPoolCount > 0 then
    return self._cardPoolCount
  end
  local myDealCount = #self._myDealtCardList
  local opponentDealCount = self:getOpponentDealtCardCount()
  return math.max(myDealCount + opponentDealCount, 0)
end

function MatchScene:syncCardAnimatorSelection()
  if self._cardAnimator then
    self._cardAnimator:setSelectedCardList(self._selectedCardList)
  end
end

function MatchScene:syncCardAnimatorLockState()
  if not self._cardAnimator then
    return
  end

  self._cardAnimator:setLockState(self._isMyCardLocked, self._isOpponentCardLocked)
  if self._isCardPickPending then
    self._cardAnimator:setWaitingLock(true)
  end
  if self._isMyCardLocked and self._isOpponentCardLocked then
    self._cardAnimator:startCleanup()
  end
end

function MatchScene:ensureCardAnimator()
  if self._cardAnimator then
    self:syncCardAnimatorSelection()
    self:syncCardAnimatorLockState()
    return
  end
  if not self:isCardSelectPhase() then
    return
  end
  if self._isMyCardLocked and self._isOpponentCardLocked then
    return
  end
  if #self._myDealtCardList <= 0 then
    return
  end

  local myCardDisplayList = {}
  for _, cardId in ipairs(self._myDealtCardList) do
    myCardDisplayList[#myCardDisplayList + 1] = {
      id = cardId,
      label = getCardLabel(cardId)
    }
  end
  local opponentDealCount = self:getOpponentDealtCardCount()

  self._cardAnimator = CardAnimator.new({
    boardX = self._boardX,
    boardY = self._boardY,
    boardW = Constants.BOARD_W,
    boardH = Constants.BOARD_H
  })
  self._cardAnimator:begin(myCardDisplayList, self._myPickCount, opponentDealCount, self:getCardPoolCount())
  self:syncCardAnimatorSelection()
  self:syncCardAnimatorLockState()
end

function MatchScene:toggleCardSelection(cardId)
  if not self:isCardSelectPhase() then
    return
  end
  if self._isMyCardLocked or self._isCardPickPending then
    return
  end

  if removeString(self._selectedCardList, cardId) then
    self:syncCardAnimatorSelection()
    return
  end

  if #self._selectedCardList >= self._myPickCount then
    self:setStatus(t("match.status.card_pick_max", {
      count = self._myPickCount
    }), Constants.COLOR_DANGER)
    return
  end

  self._selectedCardList[#self._selectedCardList + 1] = cardId
  self:syncCardAnimatorSelection()
end

function MatchScene:submitCardPick()
  if not self:isCardSelectPhase() then
    return
  end
  if self._isMyCardLocked or self._isCardPickPending then
    return
  end

  if #self._selectedCardList ~= self._myPickCount then
    self:setStatus(t("match.status.card_pick_need_exact", {
      count = self._myPickCount
    }), Constants.COLOR_DANGER)
    return
  end

  self._app:sendEnvelope("client.match.cards.pick", {
    picks = cloneStringList(self._selectedCardList)
  })
  self._isCardPickPending = true
  if self._cardAnimator then
    self._cardAnimator:setWaitingLock(true)
  end
  self:setStatus(t("match.status.card_pick_submit"), Constants.COLOR_TEXT_SUB)
end

function MatchScene:getPlayingCardPanelRect()
  local panelW = 300
  local panelH = 140
  return {
    x = self._boardX - panelW - 18,
    y = self._boardY + 12,
    w = panelW,
    h = panelH
  }
end

function MatchScene:getResultPanelRect()
  local panelW = 460
  local panelH = 280
  return {
    x = (Constants.BASE_WORLD_W - panelW) * 0.5,
    y = (Constants.BASE_WORLD_H - panelH) * 0.5,
    w = panelW,
    h = panelH
  }
end

function MatchScene:canUseCardInTurn(cardId)
  if self:isCutsceneInputBlocked() then
    return false
  end
  if not self:isPlayingPhase() then
    return false
  end
  if not self:isMyTurn() then
    return false
  end
  if self._isCardUsePending or self._isPlayingAwaitingSnapshot then
    return false
  end
  if self._hasUsedCardThisTurn then
    return false
  end
  if self._playingShotUsed > 0 then
    return false
  end
  if self._pendingCardTargetId then
    return false
  end
  return Abilities.isSupportedTurnCard(cardId)
end

function MatchScene:refreshPlayingCardHand()
  if not self._playingCardHandBar then
    return
  end

  local cardDisplayList = {}
  for _, cardId in ipairs(self._myPickedCardList) do
    if not self._optimisticConsumedCardIdSet[cardId] then
      cardDisplayList[#cardDisplayList + 1] = {
        id = cardId,
        label = getCardLabel(cardId)
      }
    end
  end
  self._playingCardHandBar:setCards(cardDisplayList)
end

function MatchScene:restoreOptimisticConsumedCard(cardId)
  if not cardId then
    return
  end
  if not self._optimisticConsumedCardIdSet[cardId] then
    return
  end
  self._optimisticConsumedCardIdSet[cardId] = nil
  if self._pendingDeclaredTargetCardId == cardId then
    self._pendingDeclaredTargetCardId = nil
  end
  self:refreshPlayingCardHand()
end

function MatchScene:handleHandCardBlocked()
  if self._hasUsedCardThisTurn then
    self:setStatus(t("match.status.card_already_used_turn"), Constants.COLOR_TEXT_SUB)
    return
  end
  self:setStatus(t("match.status.cannot_use_card_now"), Constants.COLOR_DANGER)
end

function MatchScene:handleHandCardDeclared(cardId)
  local isAccepted = self:requestTurnCardUse(cardId)
  if not isAccepted then
    return false
  end

  self._optimisticConsumedCardIdSet[cardId] = true
  if Abilities.isPointTargetCard(cardId) then
    self._pendingDeclaredTargetCardId = cardId
  else
    self._pendingDeclaredTargetCardId = nil
  end
  self:refreshPlayingCardHand()
  return true
end

function MatchScene:rebuildPlayingCardButtons()
  self._playingCardButtonList = {}
  self:refreshPlayingCardHand()
end

function MatchScene:requestTurnCardUse(cardId)
  if not self:canUseCardInTurn(cardId) then
    self:setStatus(t("match.status.cannot_use_card_now"), Constants.COLOR_DANGER)
    return false
  end

  if Abilities.isPointTargetCard(cardId) then
    self._pendingCardTargetId = cardId
    self:cancelAimDrag(true)
    self:setStatus(Abilities.getPendingTargetStartStatus(cardId), Constants.COLOR_TEXT_SUB)
    return true
  end

  local payload = {
    turnIndex = self._playingTurnIndex,
    cardId = cardId
  }

  self._app:sendEnvelope("client.match.turn.cardUse", payload)
  self._isCardUsePending = true
  self:setStatus(t("match.status.card_use_submit"), Constants.COLOR_TEXT_SUB)
  return true
end

function MatchScene:cancelPendingCardTarget()
  if not self._pendingCardTargetId then
    return
  end
  local cancelledCardId = self._pendingCardTargetId
  self._pendingCardTargetId = nil
  if self._pendingDeclaredTargetCardId == cancelledCardId then
    self:restoreOptimisticConsumedCard(cancelledCardId)
  end
  self:setStatus(t("match.status.card_target_cancel"), Constants.COLOR_TEXT_SUB)
end

function MatchScene:canPlaceRockfallAtCanonical(canonicalX, canonicalY)
  return Abilities.canPlaceRockfallAtCanonical(self, canonicalX, canonicalY)
end

function MatchScene:canPlaceReinforcementAtCanonical(canonicalX, canonicalY)
  return Abilities.canPlaceReinforcementAtCanonical(self, canonicalX, canonicalY)
end

function MatchScene:commitPendingCardTargetByWorld(worldX, worldY)
  if self:isCutsceneInputBlocked() then
    return true
  end
  if not Abilities.isPointTargetCard(self._pendingCardTargetId) then
    return false
  end
  local pendingCardId = self._pendingCardTargetId
  if not self:isMyTurn() or self._hasUsedCardThisTurn or self._playingShotUsed > 0 then
    self._pendingCardTargetId = nil
    if self._pendingDeclaredTargetCardId == pendingCardId then
      self:restoreOptimisticConsumedCard(pendingCardId)
    end
    self:setStatus(t("match.status.cannot_use_card_now"), Constants.COLOR_DANGER)
    return true
  end

  local boardLocalX, boardLocalY = self:toBoardLocal(worldX, worldY)
  if not boardLocalX then
    self:setStatus(Abilities.getPendingTargetOutOfBoardStatus(pendingCardId), Constants.COLOR_DANGER)
    return true
  end

  local canonicalX, canonicalY = self:localToCanonical(boardLocalX, boardLocalY)
  local canPlace, reason = Abilities.validatePendingTargetAtCanonical(self, pendingCardId, canonicalX, canonicalY)
  if not canPlace then
    self:setStatus(reason or t("match.status.card_target_cannot_place"), Constants.COLOR_DANGER)
    return true
  end

  self._app:sendEnvelope("client.match.turn.cardUse", {
    turnIndex = self._playingTurnIndex,
    cardId = pendingCardId,
    target = {
      x = canonicalX,
      y = canonicalY
    }
  })
  self._pendingCardTargetId = nil
  if self._pendingDeclaredTargetCardId == pendingCardId then
    self._pendingDeclaredTargetCardId = nil
  end
  self._isCardUsePending = true
  self:setStatus(Abilities.getPendingTargetRequestStatus(pendingCardId), Constants.COLOR_TEXT_SUB)
  return true
end

function MatchScene:requestSurrender()
  if not self:isPlayingPhase() then
    self:setStatus(t("match.status.cannot_surrender_now"), Constants.COLOR_DANGER)
    return
  end
  if self._isSurrenderPending then
    return
  end
  self._pendingCardTargetId = nil
  self:cancelAimDrag(true)
  if self._playingCardHandBar then
    self._playingCardHandBar:cancelCardDrag(false)
  end
  self._app:sendEnvelope("client.match.surrender", {})
  self._isSurrenderPending = true
  self:setStatus(t("match.status.surrender_submit"), Constants.COLOR_DANGER)
end

function MatchScene:requestResultVote(action)
  if self._roomState.phase ~= Constants.PHASE_RESULT then
    self:setStatus(t("match.status.cannot_vote_now"), Constants.COLOR_DANGER)
    return
  end
  if action ~= "rematch" and action ~= "to_lobby" then
    return
  end
  if self._isResultVotePending then
    return
  end

  self._app:sendEnvelope("client.match.rematch.vote", {
    action = action
  })
  self._isResultVotePending = true
  if action == "rematch" then
    self:setStatus(t("match.status.vote_rematch_submit"), Constants.COLOR_TEXT_SUB)
  else
    self:setStatus(t("match.status.vote_lobby_submit"), Constants.COLOR_TEXT_SUB)
  end
end

function MatchScene:beginAimDrag(worldX, worldY)
  if not self:isShotInputEnabled() then
    return
  end

  local stone = self:findAimStoneAt(worldX, worldY)
  if not stone then
    return
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
  self:setStatus(t("match.status.aiming"), Constants.COLOR_TEXT_SUB)
end

function MatchScene:getAimCursorWorldPosition()
  local startWorldX = self._aimStartWorldX or 0
  local startWorldY = self._aimStartWorldY or 0
  return startWorldX + self._aimAccumWorldDX, startWorldY + self._aimAccumWorldDY
end

function MatchScene:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local restoreWorldX, restoreWorldY = intersectSegmentWithWorldRect(stoneWorldX, stoneWorldY, aimWorldX, aimWorldY)
  return self._app:worldToScreen(restoreWorldX, restoreWorldY)
end

function MatchScene:cancelAimDrag(silent)
  local restoreScreenX = nil
  local restoreScreenY = nil
  if self._isAimDragging then
    self:updateAimDragInput()
    local stone = self:getAliveStoneById(self._aimStoneId)
    if stone then
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      local stoneWorldX = self._boardX + localX
      local stoneWorldY = self._boardY + localY
      restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
    end
  end

  if (not self._isAimDragging) and (not self._aimStoneId) then
    InputCaptureGuard.release(restoreScreenX, restoreScreenY)
    self._isAimRelativeMode = false
    self._aimStartWorldX = nil
    self._aimStartWorldY = nil
    self._aimAccumWorldDX = 0
    self._aimAccumWorldDY = 0
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
    return
  end
  local shouldShowStatus = not silent
  self._isAimDragging = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  self._isAimRelativeMode = false
  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
  if shouldShowStatus then
    self:setStatus(t("match.status.shot_cancelled"), Constants.COLOR_TEXT_SUB)
  end
end

function MatchScene:updateAimDragInput()
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

function MatchScene:commitAimDrag(_worldX, _worldY)
  if not self._isAimDragging then
    return
  end
  if not self:isShotInputEnabled() then
    self:cancelAimDrag(true)
    return
  end

  self:updateAimDragInput()

  local stone = self:getAliveStoneById(self._aimStoneId)
  local restoreScreenX = nil
  local restoreScreenY = nil
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  if stone then
    local localX, localY = self:canonicalToLocal(stone.x, stone.y)
    local stoneWorldX = self._boardX + localX
    local stoneWorldY = self._boardY + localY
    restoreScreenX, restoreScreenY = self:resolveAimRestoreScreenPosition(stoneWorldX, stoneWorldY)
  end
  self._isAimDragging = false
  self._isAimRelativeMode = false
  self._aimStoneId = nil
  self._aimStartWorldX = nil
  self._aimStartWorldY = nil
  InputCaptureGuard.release(restoreScreenX, restoreScreenY)
  if not stone then
    self._aimAccumWorldDX = 0
    self._aimAccumWorldDY = 0
    self._aimLastMouseWorldX = nil
    self._aimLastMouseWorldY = nil
    self:setStatus(t("match.status.shot_stone_missing"), Constants.COLOR_DANGER)
    return
  end

  local stoneLocalX, stoneLocalY = self:canonicalToLocal(stone.x, stone.y)
  local stoneWorldX = self._boardX + stoneLocalX
  local stoneWorldY = self._boardY + stoneLocalY
  local dirLocalX = stoneWorldX - aimWorldX
  local dirLocalY = stoneWorldY - aimWorldY
  self._aimAccumWorldDX = 0
  self._aimAccumWorldDY = 0
  self._aimLastMouseWorldX = nil
  self._aimLastMouseWorldY = nil
  local dragLength = math.sqrt(dirLocalX * dirLocalX + dirLocalY * dirLocalY)
  if dragLength < 1 then
    self:setStatus(t("match.status.shot_drag_too_short"), Constants.COLOR_DANGER)
    return
  end

  local dirCanonicalX = dirLocalX
  local dirCanonicalY = dirLocalY
  if self:getMyRole() == "guest" then
    dirCanonicalY = -dirCanonicalY
  end

  local canonicalLen = math.sqrt(dirCanonicalX * dirCanonicalX + dirCanonicalY * dirCanonicalY)
  if canonicalLen <= 0 then
    self:setStatus(t("match.status.shot_dir_calc_failed"), Constants.COLOR_DANGER)
    return
  end

  local power = math.min(Constants.MAX_SHOT_POWER, dragLength * Constants.POWER_PER_PIXEL)
  local normalizedDirX = dirCanonicalX / canonicalLen
  local normalizedDirY = dirCanonicalY / canonicalLen
  local localRejectCode = self:validateLocalShotAttempt(stone, normalizedDirX, normalizedDirY, power)
  if localRejectCode then
    local toastText = self:getShotDenyToastText(localRejectCode)
    self:showShotToast(toastText, Constants.COLOR_DANGER, Constants.PREDICTIVE_SHOT_TOAST_SEC)
    self:setStatus(toastText, Constants.COLOR_DANGER)
    return
  end

  local shotPayload = {
    turnIndex = self._playingTurnIndex,
    stoneId = stone.id,
    dirX = normalizedDirX,
    dirY = normalizedDirY,
    power = power
  }

  local pendingShot = self:createPredictiveShot(shotPayload)
  self:applyShotImpulse(shotPayload)
  self._app:sendEnvelope("client.match.turn.shot", shotPayload)
  self:predictiveLog("LOCAL_START", "localShotId=" .. tostring(pendingShot.localShotId) .. ", stoneId=" .. tostring(stone.id))
  self:setStatus(t("match.status.shot_submit"), Constants.COLOR_TEXT_SUB)
end

function MatchScene:sendHostSnapshotIfNeeded(turnIndex, reason)
  local session = self._app:getSession()
  if not session or session.role ~= "host" then
    return
  end
  if not turnIndex or turnIndex ~= self._playingTurnIndex then
    return
  end
  if self._lastAutoSnapshotTurnIndex == turnIndex then
    return
  end
  if self._isShotSimulating then
    self._shouldSendSnapshotAfterSim = true
    return
  end

  self._lastAutoSnapshotTurnIndex = turnIndex
  self._app:sendEnvelope("client.match.turn.snapshot", {
    turnIndex = turnIndex,
    stones = clonePlayingStoneList(self._playingStoneList)
  })
  self:setStatus(t("match.status.snapshot_submit", {
    reason = tostring(reason or t("match.status.snapshot_reason_auto"))
  }), Constants.COLOR_TEXT_SUB)
end

function MatchScene:applyRoomState(payload)
  if payload.phase == Constants.PHASE_WAITING then
    self._app:goWaitingRoom({
      roomState = payload,
      statusText = t("match.status.back_to_waiting_after_result"),
      statusColor = Constants.COLOR_TEXT_SUB
    }, Config.TRANSITION_BACK)
    return
  end

  self._roomState = payload

  if type(payload.result) == "table" then
    self._myResultVote = payload.result.myVote
    self._opponentResultVote = payload.result.opponentVote
    if self._myResultVote then
      self._isResultVotePending = false
    end
  else
    self._myResultVote = nil
    self._opponentResultVote = nil
  end

  local placement = payload.match and payload.match.placement or nil
  if type(placement) == "table" then
    if type(placement.mySubmitted) == "boolean" then
      self._isPlacementSubmitted = placement.mySubmitted
      if self._isPlacementSubmitted then
        self._isSubmitPending = false
      end
    end

    if type(placement.myStones) == "table" then
      self._myStoneList = cloneStoneList(placement.myStones)
    end

    local revealStones = placement.revealStones
    if type(revealStones) == "table" and type(revealStones.host) == "table" and type(revealStones.guest) == "table" then
      self._revealStoneMap = {
        host = cloneStoneList(revealStones.host),
        guest = cloneStoneList(revealStones.guest)
      }
    end
  end

  local cardSelect = payload.match and payload.match.cardSelect or nil
  if type(cardSelect) == "table" then
    if type(cardSelect.myDealtCards) == "table" then
      self._myDealtCardList = cloneStringList(cardSelect.myDealtCards)
    end
    if type(cardSelect.myPickedCards) == "table" then
      self._myPickedCardList = cloneStringList(cardSelect.myPickedCards)
    end
    if type(cardSelect.myPickCount) == "number" then
      self._myPickCount = cardSelect.myPickCount
    end
    if type(cardSelect.myDealtCount) == "number" then
      self._myDealtCardCount = math.max(0, math.floor(cardSelect.myDealtCount))
    else
      self._myDealtCardCount = #self._myDealtCardList
    end
    if type(cardSelect.opponentDealtCount) == "number" then
      self._opponentDealtCardCount = math.max(0, math.floor(cardSelect.opponentDealtCount))
    end
    if type(cardSelect.totalPoolCount) == "number" then
      self._cardPoolCount = math.max(0, math.floor(cardSelect.totalPoolCount))
    end
    if type(cardSelect.myLocked) == "boolean" then
      self._isMyCardLocked = cardSelect.myLocked
      if self._isMyCardLocked then
        self._selectedCardList = cloneStringList(self._myPickedCardList)
        self._isCardPickPending = false
      end
    end
    if type(cardSelect.opponentLocked) == "boolean" then
      self._isOpponentCardLocked = cardSelect.opponentLocked
    end
    if type(cardSelect.selectEndsAtMs) == "number" then
      self._cardSelectEndsAtMs = cardSelect.selectEndsAtMs
    else
      self._cardSelectEndsAtMs = nil
    end

    if not self._isMyCardLocked then
      local filtered = {}
      for _, cardId in ipairs(self._selectedCardList) do
        if containsString(self._myDealtCardList, cardId) then
          filtered[#filtered + 1] = cardId
        end
      end
      self._selectedCardList = filtered
      while #self._selectedCardList > self._myPickCount do
        table.remove(self._selectedCardList)
      end
    end

    if self._myDealtCardCount <= 0 then
      self._myDealtCardCount = #self._myDealtCardList
    end
    if self._opponentDealtCardCount <= 0 and self._cardPoolCount > 0 then
      self._opponentDealtCardCount = math.max(0, self._cardPoolCount - self._myDealtCardCount)
    end

    self:rebuildCardOptionButtons()
    self:syncCardAnimatorSelection()
    self:syncCardAnimatorLockState()
  end

  local playing = payload.match and payload.match.playing or nil
  if type(playing) == "table" then
    local turnIndexFromPayload = type(playing.turnIndex) == "number" and playing.turnIndex or nil
    local canOverwriteStoneList = true
    if self._isShotSimulating and turnIndexFromPayload and turnIndexFromPayload == self._playingTurnIndex then
      canOverwriteStoneList = false
    end

    if type(playing.turnIndex) == "number" then
      self._playingTurnIndex = playing.turnIndex
    end
    if type(playing.activePlayerIndex) == "number" then
      self._activePlayerIndex = playing.activePlayerIndex
    end
    if type(playing.turnEndsAtMs) == "number" then
      self._turnEndsAtMs = playing.turnEndsAtMs
    else
      self._turnEndsAtMs = nil
    end
    if type(playing.shotBudget) == "number" then
      self._playingShotBudget = playing.shotBudget
    end
    if type(playing.shotUsed) == "number" then
      self._playingShotUsed = playing.shotUsed
      if playing.shotUsed <= 0 then
        self._shockwaveSourceStoneId = nil
      end
    end
    if type(playing.hasCardUsedThisTurn) == "boolean" then
      self._hasUsedCardThisTurn = playing.hasCardUsedThisTurn
      if playing.hasCardUsedThisTurn then
        self._isCardUsePending = false
      end
    end
    if type(playing.lockedStoneIds) == "table" then
      self._lockedStoneIdSet = listToSet(playing.lockedStoneIds)
    else
      self._lockedStoneIdSet = {}
    end
    if type(playing.obstacles) == "table" then
      self._obstacleList = cloneObstacleList(playing.obstacles)
    else
      self._obstacleList = {}
    end
    self._invincibleTurnByPlayer = normalizeInvincibleTurnByPlayer(playing.invincibleTurnByPlayer)
    if playing.shockwaveOwnerPlayerIndex == 1 or playing.shockwaveOwnerPlayerIndex == 2 then
      self._shockwaveOwnerPlayerIndex = playing.shockwaveOwnerPlayerIndex
    else
      self._shockwaveOwnerPlayerIndex = nil
    end
    if type(playing.shotCommitted) == "boolean" then
      self._isPlayingShotCommitted = playing.shotCommitted
      if playing.shotCommitted then
        self:clearPredictiveState()
      end
    end
    if type(playing.awaitingSnapshot) == "boolean" then
      self._isPlayingAwaitingSnapshot = playing.awaitingSnapshot
      if playing.awaitingSnapshot then
        self:clearPredictiveState()
        self:cancelAimDrag(true)
      end
    end
    if canOverwriteStoneList and type(playing.stones) == "table" then
      self._playingStoneList = clonePlayingStoneList(playing.stones)
      self:syncStoneVelocityMap()
    end
    if self._pendingCardTargetId and (not self:isMyTurn() or self._hasUsedCardThisTurn or self._playingShotUsed > 0 or self._isCardUsePending) then
      if self._pendingDeclaredTargetCardId == self._pendingCardTargetId then
        self:restoreOptimisticConsumedCard(self._pendingCardTargetId)
      end
      self._pendingCardTargetId = nil
    end
    self:rebuildPlayingCardButtons()
  end
  self:syncCutsceneStateFromRoomState()

  if payload.phase ~= Constants.PHASE_PLAYING then
    self:clearPredictiveState()
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self:resetStoneVelocities()
    self._shockwaveOwnerPlayerIndex = nil
    self._shockwaveSourceStoneId = nil
    self._lockedStoneIdSet = {}
    self._pendingCardTargetId = nil
    self._pendingDeclaredTargetCardId = nil
    self._isSurrenderPending = false
    self:cancelAimDrag(true)
    if self._playingCardHandBar then
      self._playingCardHandBar:cancelCardDrag(false)
    end
    self._optimisticConsumedCardIdSet = {}
    self:refreshPlayingCardHand()
    if self._effectManager then
      self._effectManager:clear()
    end
  end
  if payload.phase ~= Constants.PHASE_RESULT then
    self._isResultVotePending = false
    self._myResultVote = nil
    self._opponentResultVote = nil
  end

  if payload.phase == Constants.PHASE_CARD_SELECT then
    self:ensureCardAnimator()
  elseif payload.phase == Constants.PHASE_PLAYING then
    if self._cardAnimator and (not self._cardAnimator:isOverlayVisible()) then
      self._cardAnimator = nil
    end
  else
    self._cardAnimator = nil
  end

  if payload.phase == Constants.PHASE_PLACEMENT_PRIVATE then
    self:setStatus(t("match.status.placement_phase_guide"), Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLACEMENT_REVEAL then
    self:setStatus(t("match.status.reveal_phase"), Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_CARD_SELECT then
    self:setStatus(t("match.status.card_select_phase"), Constants.COLOR_TEXT_SUB)
  elseif payload.phase == Constants.PHASE_PLAYING then
    if self:isServerCutsceneActive() then
      local cardLabel = self:resolveCutsceneSkillName(self._serverCutsceneState.cardId, self._serverCutsceneState.skillName)
      self:setStatus(t("match.status.cutscene_playing", {
        cardLabel = cardLabel
      }), Constants.COLOR_TEXT_SUB)
    elseif self._pendingCardTargetId then
      self:setStatus(Abilities.getPendingTargetStartStatus(self._pendingCardTargetId), Constants.COLOR_TEXT_SUB)
    elseif self:isMyTurn() then
      self:setStatus(t("match.status.my_turn_guide"), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("match.status.opponent_turn_guide"), Constants.COLOR_TEXT_SUB)
    end
    if self._isPlayingAwaitingSnapshot then
      self:sendHostSnapshotIfNeeded(self._playingTurnIndex, "state_sync")
    end
  elseif payload.phase == Constants.PHASE_RESULT then
    local myVoteLabelMap = {
      rematch = t("match.result.vote_rematch"),
      to_lobby = t("match.result.vote_lobby")
    }
    local myVoteLabel = self._myResultVote and (myVoteLabelMap[self._myResultVote] or tostring(self._myResultVote)) or t("match.result.vote_none")
    self:setStatus(t("match.status.result_vote_status", {
      vote = myVoteLabel
    }), Constants.COLOR_DANGER)
  end
end

function MatchScene:update(dt)
  self:updateAimDragInput()
  if self._predictiveRollbackInputLockSec > 0 then
    self._predictiveRollbackInputLockSec = math.max(0, self._predictiveRollbackInputLockSec - dt)
  end
  self:updatePredictiveRollback(dt)
  self:updateShotToast(dt)
  if self._cutsceneManager then
    self._cutsceneManager:update(dt)
  end

  if self:isCardSelectPhase() and (not self._cardAnimator) then
    self:ensureCardAnimator()
  end
  if self._cardAnimator then
    self._cardAnimator:update(dt)
    if not self._cardAnimator:isOverlayVisible() then
      self._cardAnimator = nil
    end
  end

  if self._effectManager then
    self._effectManager:update(dt)
  end
  if self:isPlayingPhase() then
    self:updateShotSimulation(dt)
  end

  if self._playingCardHandBar then
    local mouseX, mouseY = self._app:getMouseWorldPosition()
    self._playingCardHandBar:update(dt, mouseX, mouseY, {
      isPlayingPhase = self:isPlayingPhase(),
      isStoneDragging = self._isAimDragging
    })
  end
  if self._inGameChat and self:isInGameChatAvailable() then
    self._inGameChat:update(dt)
  elseif self._inGameChat then
    self._inGameChat:closeImmediate()
  end
end

function MatchScene:drawBoardFrame()
  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  local centerWorldY = self._boardY + Constants.BOARD_H * 0.5
  local stripY = centerWorldY - Constants.NO_PLACE_BUFFER
  local stripH = Constants.NO_PLACE_BUFFER * 2

  if self._roomState.phase ~= Constants.PHASE_PLAYING and self._roomState.phase ~= Constants.PHASE_RESULT then
    love.graphics.setColor(0.65, 0.18, 0.22, 0.20)
    love.graphics.rectangle("fill", self._boardX, stripY, Constants.BOARD_W, stripH)
  end

  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.line(self._boardX, centerWorldY, self._boardX + Constants.BOARD_W, centerWorldY)

  if self:isPlacementPhase() then
    love.graphics.setColor(0.20, 0.45, 0.27, 0.16)
    love.graphics.rectangle(
      "fill",
      self._boardX,
      self._boardY + Constants.BOARD_H * 0.5 + Constants.NO_PLACE_BUFFER,
      Constants.BOARD_W,
      Constants.BOARD_H * 0.5 - Constants.NO_PLACE_BUFFER
    )
  end
end

function MatchScene:drawStoneList(stoneList, color)
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false then
      local isGhostStone = self:isPredictiveGhostStone(stone.id)
      local alpha = isGhostStone and Constants.PREDICTIVE_SHOT_GHOST_ALPHA or 1.0
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      love.graphics.setColor(color[1], color[2], color[3], alpha)
      love.graphics.circle("fill", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
    end
  end

  local pulseTime = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  for _, stone in ipairs(stoneList or {}) do
    if stone.alive ~= false then
      local isGhostStone = self:isPredictiveGhostStone(stone.id)
      local alpha = isGhostStone and 0.80 or 1.0
      local localX, localY = self:canonicalToLocal(stone.x, stone.y)
      love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], alpha)
      love.graphics.circle("line", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS)
      if isGhostStone then
        local pulse = math.sin(pulseTime * 10.0) * 1.6
        love.graphics.setColor(0.96, 0.92, 0.35, 0.75)
        love.graphics.setLineWidth(1.2)
        love.graphics.circle("line", self._boardX + localX, self._boardY + localY, Constants.STONE_RADIUS + 3 + pulse)
        love.graphics.setLineWidth(1)
      end
    end
  end
end

function MatchScene:drawObstacleList(obstacleList)
  love.graphics.setColor(0.44, 0.42, 0.40, 1.0)
  for _, obstacle in ipairs(obstacleList or {}) do
    local localX, localY = self:canonicalToLocal(obstacle.x, obstacle.y)
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.rectangle("fill", self._boardX + localX - width * 0.5, self._boardY + localY - height * 0.5, width, height, 6, 6)
  end

  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  for _, obstacle in ipairs(obstacleList or {}) do
    local localX, localY = self:canonicalToLocal(obstacle.x, obstacle.y)
    local width = obstacle.width or Constants.ROCK_OBSTACLE_WIDTH
    local height = obstacle.height or Constants.ROCK_OBSTACLE_HEIGHT
    love.graphics.rectangle("line", self._boardX + localX - width * 0.5, self._boardY + localY - height * 0.5, width, height, 6, 6)
  end
end

function MatchScene:drawPlacementInfo()
  local placement = self._roomState.match and self._roomState.match.placement or nil
  local mySubmitted = placement and placement.mySubmitted and t("match.info.placement_my_done") or t("match.info.placement_my_doing")
  local opponentSubmitted = placement and placement.opponentSubmitted and t("match.info.placement_opponent_done") or t("match.info.placement_opponent_waiting")
  local timerText = ""
  local phaseEndsAtMs = self._roomState.timers and self._roomState.timers.phaseEndsAtMs or nil
  if phaseEndsAtMs and self._roomState.phase == Constants.PHASE_PLACEMENT_REVEAL then
    local remainSec = TimeUtils.getRemainingSeconds(phaseEndsAtMs)
    timerText = t("match.info.reveal_remaining", {
      sec = remainSec
    })
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(
    t("match.info.placement_line", {
      myState = mySubmitted,
      count = #self._myStoneList,
      max = Constants.STONE_COUNT_PER_PLAYER,
      opponentState = opponentSubmitted,
      timerText = timerText
    }),
    0,
    636,
    Constants.BASE_WORLD_W,
    "center"
  )
end

function MatchScene:drawPlayingInfo()
  local remainSec = 0
  if self._turnEndsAtMs then
    remainSec = TimeUtils.getRemainingSeconds(self._turnEndsAtMs)
  elseif self:isServerCutsceneActive() and type(self._cutsceneFrozenRemainSec) == "number" then
    remainSec = self._cutsceneFrozenRemainSec
  end

  local turnOwnerText = self._activePlayerIndex == self:getMyPlayerIndex() and t("match.info.turn_owner_me") or t("match.info.turn_owner_other")
  local stateText = t("match.info.state_aim")
  if self:isServerCutsceneActive() then
    stateText = t("match.info.state_cutscene_paused")
  elseif self._isPlayingAwaitingSnapshot then
    stateText = t("match.info.state_wait_snapshot")
  elseif self._pendingCardTargetId then
    stateText = t("match.info.state_pick_card_target")
  elseif self._isCardUsePending then
    stateText = t("match.info.state_card_pending")
  elseif self._isPlayingShotCommitted then
    stateText = t("match.info.state_shot_done")
    if self._isShotSimulating then
      stateText = t("match.info.state_simulating")
    end
  elseif self._isTurnShotPending then
    stateText = t("match.info.state_shot_pending")
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(
    t("match.info.turn_line", {
      turnIndex = self._playingTurnIndex,
      turnOwner = turnOwnerText,
      remainSec = remainSec,
      shotUsed = self._playingShotUsed,
      shotBudget = self._playingShotBudget,
      hasCardUsed = self._hasUsedCardThisTurn and t("common.yes") or t("common.no"),
      stateText = stateText
    }),
    0,
    636,
    Constants.BASE_WORLD_W,
    "center"
  )
end

function MatchScene:drawPlayingCardPanel(mouseX, mouseY)
  if not self:isPlayingPhase() then
    return
  end

  local rect = self:getPlayingCardPanelRect()
  UIDraw.drawPanel(rect, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.turn_card_title"), rect.x, rect.y + 8, rect.w, "center")

  for _, entry in ipairs(self._playingCardButtonList) do
    local canUse = self:canUseCardInTurn(entry.cardId)
    entry.button.isEnabled = canUse
    entry.button.color = canUse and Constants.COLOR_BUTTON or Constants.COLOR_BUTTON_DISABLED
    entry.button:draw(mouseX, mouseY)
  end

  if self._pendingCardTargetId then
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    local hintText = Abilities.getPendingTargetHint(self._pendingCardTargetId)
    love.graphics.printf(hintText, rect.x, rect.y + rect.h - 18, rect.w, "center")
  end
end

function MatchScene:drawAimGuide(mouseX, mouseY)
  if not self._isAimDragging then
    return
  end
  local stone = self:getAliveStoneById(self._aimStoneId)
  if not stone then
    return
  end

  local localX, localY = self:canonicalToLocal(stone.x, stone.y)
  local stoneWorldX = self._boardX + localX
  local stoneWorldY = self._boardY + localY
  local aimWorldX, aimWorldY = self:getAimCursorWorldPosition()
  local dirX = stoneWorldX - aimWorldX
  local dirY = stoneWorldY - aimWorldY
  local distance = math.sqrt(dirX * dirX + dirY * dirY)
  local power = math.min(Constants.MAX_SHOT_POWER, distance * Constants.POWER_PER_PIXEL)

  love.graphics.setColor(0.95, 0.92, 0.35, 0.95)
  love.graphics.setLineWidth(2)
  love.graphics.line(stoneWorldX, stoneWorldY, aimWorldX, aimWorldY)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.power_label", {
    power = string.format("%.0f", power)
  }), stoneWorldX - 50, stoneWorldY - 30, 100, "center")
end

function MatchScene:drawSelectedStoneHighlight()
  if not self._isAimDragging then
    return
  end

  local stone = self:getAliveStoneById(self._aimStoneId)
  if not stone then
    return
  end

  local localX, localY = self:canonicalToLocal(stone.x, stone.y)
  local stoneWorldX = self._boardX + localX
  local stoneWorldY = self._boardY + localY
  local timeSec = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  local pulse = math.sin(timeSec * 7.0) * 2.2
  local baseRadius = Constants.STONE_RADIUS + 4

  love.graphics.setColor(0.96, 0.88, 0.35, 0.12)
  love.graphics.circle("fill", stoneWorldX, stoneWorldY, baseRadius + 5 + pulse)

  love.graphics.setColor(0.98, 0.95, 0.65, 0.90)
  love.graphics.setLineWidth(2.6)
  love.graphics.circle("line", stoneWorldX, stoneWorldY, baseRadius + pulse)

  love.graphics.setColor(0.98, 0.95, 0.65, 0.45)
  love.graphics.setLineWidth(1.6)
  love.graphics.circle("line", stoneWorldX, stoneWorldY, baseRadius + 6 + pulse * 0.7)

  love.graphics.setLineWidth(1)
end

function MatchScene:drawPendingCardPreview(mouseX, mouseY)
  Abilities.drawPendingCardPreview(self, mouseX, mouseY)
end

function MatchScene:drawCardSelectPanel(mouseX, mouseY)
  local rect = getCardSelectPanelRect(self._boardX, self._boardY)
  local panelX = rect.x
  local panelY = rect.y
  local panelW = rect.w
  local panelH = rect.h

  love.graphics.setColor(Constants.COLOR_OVERLAY_DIM)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  self:ensureCardAnimator()
  local cardStage = self._cardAnimator and self._cardAnimator:getStage() or nil
  if self._cardAnimator and self._cardAnimator:isSelectionInteractive() then
    self._cardAnimator:setHoverCardId(self._cardAnimator:getCardIdAtPoint(mouseX, mouseY))
  elseif self._cardAnimator then
    self._cardAnimator:setHoverCardId(nil)
  end

  if self._cardAnimator then
    self._cardAnimator:draw()
  end

  local remainSec = 0
  if self._cardSelectEndsAtMs then
    remainSec = TimeUtils.getRemainingSeconds(self._cardSelectEndsAtMs)
  end

  local messagePanelW = math.min(panelW - 70, 460)
  local messagePanelH = 88
  local messagePanelX = (Constants.BASE_WORLD_W - messagePanelW) * 0.5
  local messagePanelY = (Constants.BASE_WORLD_H - messagePanelH) * 0.5
  UIDraw.drawPanel({
    x = messagePanelX,
    y = messagePanelY,
    w = messagePanelW,
    h = messagePanelH
  }, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)

  local titleText = t("match.card_select_title")
  if cardStage == "SELECT" or cardStage == "WAIT_LOCK" or cardStage == "CLEANUP" then
    titleText = t("match.card_select_prompt", {
      pickCount = self._myPickCount
    })
  end
  if self._isMyCardLocked or self._isCardPickPending then
    titleText = t("match.card_select_waiting")
  end

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(titleText, messagePanelX + 12, messagePanelY + 18, messagePanelW - 24, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("match.info.card_select_remaining_only", {
    remainSec = remainSec
  }), messagePanelX + 12, messagePanelY + 50, messagePanelW - 24, "center")

  local shouldShowConfirm = cardStage == "SELECT" or cardStage == "WAIT_LOCK"
  if shouldShowConfirm then
    local targetX = self._boardX + Constants.BOARD_W + 20
    self._cardConfirmButton.x = math.min(Constants.BASE_WORLD_W - self._cardConfirmButton.w - 16, targetX)
    self._cardConfirmButton.y = (Constants.BASE_WORLD_H - self._cardConfirmButton.h) * 0.5
    self._cardConfirmButton.isEnabled = (not self._isMyCardLocked)
      and (not self._isCardPickPending)
      and (#self._selectedCardList == self._myPickCount)
      and self._cardAnimator
      and self._cardAnimator:isSelectionInteractive()
    self._cardConfirmButton:draw(mouseX, mouseY)
  end

end

function MatchScene:drawResultPanel(mouseX, mouseY)
  local rect = self:getResultPanelRect()
  local payload = self._roomState.result or {}
  local winnerPlayerIndex = payload.winnerPlayerIndex
  local reason = payload.reason or t("common.unknown")

  local resultTitle = t("match.result.title_draw")
  if winnerPlayerIndex == self:getMyPlayerIndex() then
    resultTitle = t("match.result.title_win")
  elseif winnerPlayerIndex == nil then
    resultTitle = t("match.result.title_draw")
  else
    resultTitle = t("match.result.title_lose")
  end

  local reasonLabelMap = {
    stone_zero = t("match.result.reason_stone_zero"),
    draw = t("match.result.reason_draw"),
    player_left = t("match.result.reason_player_left"),
    surrender = t("match.result.reason_surrender"),
    snapshot_timeout = t("match.result.reason_snapshot_timeout")
  }
  local reasonLabel = reasonLabelMap[reason] or tostring(reason)
  local voteLabelMap = {
    rematch = t("match.result.vote_rematch"),
    to_lobby = t("match.result.vote_lobby")
  }
  local myVoteText = self._myResultVote and (voteLabelMap[self._myResultVote] or tostring(self._myResultVote)) or t("match.result.vote_none")
  local opponentVoteText = self._opponentResultVote and (voteLabelMap[self._opponentResultVote] or tostring(self._opponentResultVote)) or t("match.result.vote_none")

  love.graphics.setColor(Constants.COLOR_OVERLAY_DIM)
  love.graphics.rectangle("fill", self._boardX, self._boardY, Constants.BOARD_W, Constants.BOARD_H, 8, 8)

  UIDraw.drawPanel(rect, Constants.COLOR_PANEL, Constants.COLOR_PANEL_BORDER, nil)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.result.title", {
    title = resultTitle
  }), rect.x, rect.y + 18, rect.w, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("match.result.reason", {
    reason = reasonLabel
  }), rect.x, rect.y + 76, rect.w, "center")
  love.graphics.printf(t("match.result.vote", {
    myVote = myVoteText,
    opponentVote = opponentVoteText
  }), rect.x, rect.y + 112, rect.w, "center")

  local buttonY = rect.y + rect.h - 82
  self._resultRematchButton.x = rect.x + 30
  self._resultRematchButton.y = buttonY
  self._resultLobbyButton.x = rect.x + rect.w - self._resultLobbyButton.w - 30
  self._resultLobbyButton.y = buttonY

  self._resultRematchButton.isEnabled = not self._isResultVotePending
  self._resultLobbyButton.isEnabled = not self._isResultVotePending
  self._resultRematchButton.color = self._myResultVote == "rematch" and Constants.COLOR_BUTTON_SELECTED or Constants.COLOR_BUTTON
  self._resultLobbyButton.color = self._myResultVote == "to_lobby" and { 0.75, 0.28, 0.30, 1.0 } or Constants.COLOR_DANGER

  self._resultRematchButton:draw(mouseX, mouseY)
  self._resultLobbyButton:draw(mouseX, mouseY)
end

function MatchScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("match.title"), 0, 16, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("match.phase_label", {
    phase = tostring(self._roomState.phase)
  }), 0, 48, Constants.BASE_WORLD_W, "center")

  self:drawBoardFrame()

  if self._roomState.phase == Constants.PHASE_PLAYING or self._roomState.phase == Constants.PHASE_RESULT then
    local hostStoneList = {}
    local guestStoneList = {}
    for _, stone in ipairs(self._playingStoneList) do
      if stone.ownerPlayerIndex == 1 then
        hostStoneList[#hostStoneList + 1] = stone
      else
        guestStoneList[#guestStoneList + 1] = stone
      end
    end
    self:drawObstacleList(self._obstacleList)
    self:drawStoneList(hostStoneList, Constants.COLOR_STONE_HOST)
    self:drawStoneList(guestStoneList, Constants.COLOR_STONE_GUEST)
  elseif self:isRevealVisiblePhase() and self._revealStoneMap then
    self:drawStoneList(self._revealStoneMap.host, Constants.COLOR_STONE_HOST)
    self:drawStoneList(self._revealStoneMap.guest, Constants.COLOR_STONE_GUEST)
  else
    local role = self:getMyRole()
    local color = role == "guest" and Constants.COLOR_STONE_GUEST or Constants.COLOR_STONE_HOST
    self:drawStoneList(self._myStoneList, color)
  end

  self:drawPendingCardPreview(mouseX, mouseY)
  self:drawSelectedStoneHighlight()
  self:drawAimGuide(mouseX, mouseY)
  if self._effectManager then
    self._effectManager:draw(self._boardX, self._boardY, function(canonicalX, canonicalY)
      return self:canonicalToLocal(canonicalX, canonicalY)
    end)
  end

  if self:isPlacementPhase() then
    local canSubmit = (not self._isPlacementSubmitted) and (not self._isSubmitPending) and #self._myStoneList == Constants.STONE_COUNT_PER_PLAYER
    self._submitButton.isEnabled = canSubmit
    self._submitButton:draw(mouseX, mouseY)
  end

  if self._roomState.phase == Constants.PHASE_CARD_SELECT then
    self:drawCardSelectPanel(mouseX, mouseY)
  elseif self._roomState.phase == Constants.PHASE_PLAYING then
    self:drawPlayingInfo()
    if self._playingCardHandBar then
      self._playingCardHandBar:draw()
    end
    self._surrenderButton.isEnabled = not self._isSurrenderPending
    self._surrenderButton:draw(mouseX, mouseY)
  elseif self._roomState.phase == Constants.PHASE_RESULT then
    self:drawResultPanel(mouseX, mouseY)
  else
    self:drawPlacementInfo()
  end

  if self._roomState.phase ~= Constants.PHASE_CARD_SELECT and self._cardAnimator and self._cardAnimator:isOverlayVisible() then
    self:drawCardSelectPanel(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
  self:drawShotToast()

  if self._inGameChat and self:isInGameChatAvailable() then
    self._inGameChat:draw(mouseX, mouseY)
  end
  if self._cutsceneManager then
    self._cutsceneManager:draw(mouseX, mouseY)
  end
end

function MatchScene:mousepressed(mouseX, mouseY, button)
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:mousepressed(mouseX, mouseY, button) then
    return
  end
  if self._cutsceneManager and self._cutsceneManager:mousepressed(mouseX, mouseY, button) then
    return
  end
  if self:isCutsceneInputBlocked() then
    return
  end

  if self._roomState.phase ~= Constants.PHASE_CARD_SELECT and self._cardAnimator and self._cardAnimator:isOverlayVisible() then
    return
  end

  if self:isPlayingPhase() and button == 2 then
    if self._playingCardHandBar and self._playingCardHandBar:isDraggingCard() then
      self._playingCardHandBar:cancelCardDrag(true)
      return
    end
    if self._pendingCardTargetId then
      self:cancelPendingCardTarget()
    else
      self:cancelAimDrag()
    end
    return
  end

  if button ~= 1 then
    return
  end

  if self:isCardSelectPhase() then
    self:ensureCardAnimator()
    if self._cardAnimator and self._cardAnimator:isSelectionInteractive() then
      local clickedCardId = self._cardAnimator:getCardIdAtPoint(mouseX, mouseY)
      if clickedCardId then
        self:toggleCardSelection(clickedCardId)
        return
      end
    end
    if self._cardConfirmButton:isHovered(mouseX, mouseY) and self._cardConfirmButton.isEnabled then
      self._cardConfirmButton:onClick()
      return
    end
    return
  end

  if self:isPlayingPhase() then
    if self._predictiveRollbackState or self:isPredictiveRollbackLocked() then
      return
    end
    if self._surrenderButton:isHovered(mouseX, mouseY) and self._surrenderButton.isEnabled then
      self._surrenderButton:onClick()
      return
    end
    if self._pendingCardTargetId then
      self:commitPendingCardTargetByWorld(mouseX, mouseY)
      return
    end
    if self._playingCardHandBar and self._playingCardHandBar:mousepressed(mouseX, mouseY, button) then
      return
    end
    self:beginAimDrag(mouseX, mouseY)
    return
  end

  if self._roomState.phase == Constants.PHASE_RESULT then
    if self._resultRematchButton:isHovered(mouseX, mouseY) and self._resultRematchButton.isEnabled then
      self._resultRematchButton:onClick()
      return
    end
    if self._resultLobbyButton:isHovered(mouseX, mouseY) and self._resultLobbyButton.isEnabled then
      self._resultLobbyButton:onClick()
      return
    end
    return
  end

  if self._submitButton:isHovered(mouseX, mouseY) and self._submitButton.isEnabled then
    self._submitButton:onClick()
    return
  end

  if self:isPlacementPhase() then
    self:addPlacementByWorld(mouseX, mouseY)
  end
end

function MatchScene:mousereleased(mouseX, mouseY, button)
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:mousereleased(mouseX, mouseY, button) then
    return
  end
  if self._cutsceneManager and self._cutsceneManager:mousereleased(mouseX, mouseY, button) then
    return
  end
  if self:isCutsceneInputBlocked() then
    return
  end

  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:isInputBlocking() then
    return
  end

  if self._roomState.phase ~= Constants.PHASE_CARD_SELECT and self._cardAnimator and self._cardAnimator:isOverlayVisible() then
    return
  end
  if button ~= 1 then
    return
  end
  if self:isPlayingPhase() and (self._predictiveRollbackState or self:isPredictiveRollbackLocked()) then
    return
  end
  if self:isPlayingPhase() and self._playingCardHandBar and self._playingCardHandBar:mousereleased(mouseX, mouseY, button) then
    return
  end
  if self:isPlayingPhase() and self._isAimDragging then
    self:commitAimDrag(mouseX, mouseY)
  end
end

function MatchScene:mousemoved(mouseX, mouseY, dx, dy)
  if self:isCutsceneInputBlocked() then
    return
  end
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:mousemoved(mouseX, mouseY, dx, dy) then
    return
  end
end

function MatchScene:wheelmoved(mouseX, mouseY, dx, dy)
  if self:isCutsceneInputBlocked() then
    return
  end
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:wheelmoved(mouseX, mouseY, dx, dy) then
    return
  end
end

function MatchScene:textinput(text)
  if self:isCutsceneInputBlocked() then
    return
  end
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:textinput(text) then
    return
  end
end

function MatchScene:textedited(text, start, length)
  if self:isCutsceneInputBlocked() then
    return
  end
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:textedited(text, start, length) then
    return
  end
end

function MatchScene:keypressed(key)
  if self._cutsceneManager and self._cutsceneManager:keypressed(key) then
    return
  end
  if self:isCutsceneInputBlocked() then
    return
  end
  if self._inGameChat and self:isInGameChatAvailable() and self._inGameChat:keypressed(key) then
    return
  end
  if self:isPlayingPhase() and (self._predictiveRollbackState or self:isPredictiveRollbackLocked()) then
    return
  end

  if self._roomState.phase ~= Constants.PHASE_CARD_SELECT and self._cardAnimator and self._cardAnimator:isOverlayVisible() then
    return
  end
  if key == "escape" and self._playingCardHandBar and self._playingCardHandBar:isDraggingCard() then
    self._playingCardHandBar:cancelCardDrag(true)
    return
  end
  if key == "escape" and self._pendingCardTargetId then
    self:cancelPendingCardTarget()
    return
  end
  if key == "escape" and self._isAimDragging then
    self:cancelAimDrag()
    return
  end
  if key == "escape" and self._roomState.phase == Constants.PHASE_RESULT then
    self:requestResultVote("to_lobby")
    return
  end
end

function MatchScene:onServerEnvelope(envelope)
  if envelope.type == "room.state" and type(envelope.payload) == "table" then
    self:applyRoomState(envelope.payload)
    return
  end

  if envelope.type == "match.turnOrder" then
    local payload = envelope.payload or {}
    self:setStatus(t("match.status.turn_order", {
      playerIndex = tostring(payload.firstPlayerIndex or "?")
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.phaseChanged" then
    local payload = envelope.payload or {}
    self:setStatus(t("match.status.phase_changed", {
      from = tostring(payload.from),
      to = tostring(payload.to)
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.placement.revealStart" then
    local payload = envelope.payload or {}
    if type(payload.stones) == "table" then
      local hostStones = type(payload.stones.host) == "table" and payload.stones.host or {}
      local guestStones = type(payload.stones.guest) == "table" and payload.stones.guest or {}
      self._revealStoneMap = {
        host = cloneStoneList(hostStones),
        guest = cloneStoneList(guestStones)
      }
    end
    self:setStatus(t("match.status.reveal_started"), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.cards.dealt" then
    local payload = envelope.payload or {}
    if type(payload.pickCount) == "number" then
      self._myPickCount = payload.pickCount
    end
    if type(payload.dealtCards) == "table" then
      self._myDealtCardList = cloneStringList(payload.dealtCards)
      self._myDealtCardCount = #self._myDealtCardList
      self:rebuildCardOptionButtons()
    end
    if type(payload.myDealtCount) == "number" then
      self._myDealtCardCount = math.max(0, math.floor(payload.myDealtCount))
    end
    if type(payload.opponentDealtCount) == "number" then
      self._opponentDealtCardCount = math.max(0, math.floor(payload.opponentDealtCount))
    end
    if type(payload.totalPoolCount) == "number" then
      self._cardPoolCount = math.max(0, math.floor(payload.totalPoolCount))
    end
    if type(payload.selectEndsAtMs) == "number" then
      self._cardSelectEndsAtMs = payload.selectEndsAtMs
    end
    self:syncCardAnimatorSelection()
    self:syncCardAnimatorLockState()
    self:setStatus(t("match.status.cards_dealt"), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.cards.locked" then
    local payload = envelope.payload or {}
    local myPlayerIndex = self:getMyPlayerIndex()
    if payload.playerIndex == myPlayerIndex then
      self._isMyCardLocked = true
      self._isCardPickPending = false
      if type(payload.pickedCards) == "table" then
        self._myPickedCardList = cloneStringList(payload.pickedCards)
        self._optimisticConsumedCardIdSet = {}
        self._pendingDeclaredTargetCardId = nil
        self._selectedCardList = cloneStringList(payload.pickedCards)
        self:syncCardAnimatorSelection()
        self:rebuildPlayingCardButtons()
      end
      self:syncCardAnimatorLockState()
      self:setStatus(t("match.status.my_cards_locked"), Constants.COLOR_TEXT_SUB)
    else
      self._isOpponentCardLocked = true
      self:syncCardAnimatorLockState()
      self:setStatus(t("match.status.opponent_cards_locked"), Constants.COLOR_TEXT_SUB)
    end
    if self._isMyCardLocked and self._isOpponentCardLocked then
      self:syncCardAnimatorLockState()
    end
    return
  end

  if envelope.type == "match.turn.start" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.activePlayerIndex) == "number" then
      self._activePlayerIndex = payload.activePlayerIndex
    end
    if type(payload.turnEndsAtMs) == "number" then
      self._turnEndsAtMs = payload.turnEndsAtMs
    else
      self._turnEndsAtMs = nil
    end
    if type(payload.shotBudget) == "number" then
      self._playingShotBudget = payload.shotBudget
    else
      self._playingShotBudget = 1
    end
    if type(payload.shotUsed) == "number" then
      self._playingShotUsed = payload.shotUsed
    else
      self._playingShotUsed = 0
    end
    self._shockwaveSourceStoneId = nil
    self._shockwaveOwnerPlayerIndex = nil
    if type(payload.hasCardUsedThisTurn) == "boolean" then
      self._hasUsedCardThisTurn = payload.hasCardUsedThisTurn
    else
      self._hasUsedCardThisTurn = false
    end
    self:clearPredictiveState()
    self._isPlayingShotCommitted = false
    self._isPlayingAwaitingSnapshot = false
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self._pendingDeclaredTargetCardId = nil
    self._optimisticConsumedCardIdSet = {}
    self._isSurrenderPending = false
    self:cancelAimDrag(true)
    if self._playingCardHandBar then
      self._playingCardHandBar:cancelCardDrag(false)
    end
    if self._effectManager then
      self._effectManager:clear()
    end
    self._lastAutoSnapshotTurnIndex = nil
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self:resetStoneVelocities()
    self:rebuildPlayingCardButtons()
    if self:isMyTurn() then
      self:setStatus(t("match.status.my_turn_start"), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("match.status.opponent_turn_start"), Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.cardCue" then
    local payload = envelope.payload or {}
    self:setStatus(t("match.status.card_cue", {
      playerIndex = tostring(payload.playerIndex or "?"),
      cardLabel = tostring(getCardLabel(payload.cardId))
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.card.cutsceneStart" then
    local payload = envelope.payload or {}
    self:startSkillCutscene({
      cutsceneId = payload.cutsceneId,
      ownerPlayerIndex = payload.ownerPlayerIndex,
      cardId = payload.cardId,
      skillName = payload.skillName,
      cutsceneDurationMs = payload.cutsceneDurationMs,
      pausedRemainingMs = payload.pausedRemainingMs
    })
    return
  end

  if envelope.type == "match.card.cutsceneEnd" then
    self:stopSkillCutscene()
    return
  end

  if envelope.type == "match.turn.cardApplied" then
    local payload = envelope.payload or {}
    local myPlayerIndex = self:getMyPlayerIndex()
    if payload.playerIndex == myPlayerIndex then
      self._isCardUsePending = false
      self._hasUsedCardThisTurn = true
      if type(payload.cardId) == "string" then
        self._optimisticConsumedCardIdSet[payload.cardId] = nil
        if self._pendingDeclaredTargetCardId == payload.cardId then
          self._pendingDeclaredTargetCardId = nil
        end
        removeString(self._myPickedCardList, payload.cardId)
      end
      Abilities.applyServerCardEffect(self, payload.effect)
      self:rebuildPlayingCardButtons()
    else
      Abilities.applyServerCardEffect(self, payload.effect)
    end
    self:setStatus(t("match.status.card_applied", {
      cardLabel = tostring(getCardLabel(payload.cardId))
    }), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.turn.shotAccepted" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.shotUsed) == "number" then
      self._playingShotUsed = payload.shotUsed
    end
    if type(payload.shotBudget) == "number" then
      self._playingShotBudget = payload.shotBudget
    end
    local confirmedPredictiveShot = self:confirmPredictiveShotByAcceptedPayload(payload)
    if not confirmedPredictiveShot then
      self:applyShotImpulse(payload)
    end
    self._isPlayingShotCommitted = self._playingShotUsed >= self._playingShotBudget
    self._isTurnShotPending = self:hasPendingPredictiveShot()
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self._pendingDeclaredTargetCardId = nil
    self:cancelAimDrag(true)
    if self._playingShotUsed >= self._playingShotBudget then
      self:setStatus(t("match.status.shot_accepted_wait_snapshot"), Constants.COLOR_TEXT_SUB)
    else
      self:setStatus(t("match.status.shot_accepted_extra"), Constants.COLOR_TEXT_SUB)
    end
    return
  end

  if envelope.type == "match.turn.snapshotRequested" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    self._isPlayingAwaitingSnapshot = true
    self._turnEndsAtMs = nil
    self:clearPredictiveState()
    self._isCardUsePending = false
    self._pendingDeclaredTargetCardId = nil
    self:cancelAimDrag(true)
    self:setStatus(t("match.status.snapshot_requested"), Constants.COLOR_TEXT_SUB)
    self:sendHostSnapshotIfNeeded(payload.turnIndex, payload.reason)
    return
  end

  if envelope.type == "match.turn.snapshotApplied" then
    local payload = envelope.payload or {}
    if type(payload.turnIndex) == "number" then
      self._playingTurnIndex = payload.turnIndex
    end
    if type(payload.stones) == "table" then
      self._playingStoneList = clonePlayingStoneList(payload.stones)
      self:resetStoneVelocities()
    end
    self._shouldSendSnapshotAfterSim = false
    self:stopShotSimulation()
    self._isPlayingAwaitingSnapshot = false
    self._isPlayingShotCommitted = false
    self._shockwaveSourceStoneId = nil
    if self._effectManager then
      self._effectManager:clear()
    end
    self:clearPredictiveState()
    self._isCardUsePending = false
    self._pendingCardTargetId = nil
    self._pendingDeclaredTargetCardId = nil
    self:setStatus(t("match.status.snapshot_applied"), Constants.COLOR_TEXT_SUB)
    return
  end

  if envelope.type == "match.result" then
    local payload = envelope.payload or {}
    self._isSurrenderPending = false
    self._pendingCardTargetId = nil
    self._pendingDeclaredTargetCardId = nil
    self._isResultVotePending = false
    self:setStatus(t("match.status.result_winner", {
      winner = tostring(payload.winnerPlayerIndex or "?")
    }), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "error.generic" then
    local payload = envelope.payload or {}
    if self._isSurrenderPending then
      self._isSurrenderPending = false
    end
    if self._isResultVotePending then
      self._isResultVotePending = false
    end
    if payload.code == "invalid_placement" or payload.code == "already_submitted" then
      self._isSubmitPending = false
    end
    if payload.code == "invalid_card_pick" or payload.code == "already_locked" then
      self._isCardPickPending = false
      if self._cardAnimator then
        self._cardAnimator:setWaitingLock(false)
      end
    end
    if payload.code == "card_already_used" or payload.code == "card_use_window_closed" or payload.code == "card_not_owned" or payload.code == "card_not_implemented" or payload.code == "invalid_card_id" or payload.code == "invalid_card_target" or payload.code == "cutscene_active" then
      self._isCardUsePending = false
      if self._pendingDeclaredTargetCardId and self._pendingCardTargetId == self._pendingDeclaredTargetCardId then
        self._pendingCardTargetId = nil
      end
      self._pendingDeclaredTargetCardId = nil
      self._optimisticConsumedCardIdSet = {}
      self:refreshPlayingCardHand()
    end
    if self:isShotErrorCode(payload.code) then
      local pendingShot = self:getLatestPendingPredictiveShot()
      if pendingShot then
        local removedShot = self:removePredictiveShotById(pendingShot.localShotId, true)
        self:beginPredictiveRollback(removedShot, payload.code)
      else
        self._isTurnShotPending = false
        self._isPlayingShotCommitted = false
        self:cancelAimDrag(true)
        self._shouldSendSnapshotAfterSim = false
        self:stopShotSimulation()
        self:resetStoneVelocities()
        local fallbackToastText = self:getShotDenyToastText(payload.code)
        self:showShotToast(fallbackToastText, Constants.COLOR_DANGER, Constants.PREDICTIVE_SHOT_TOAST_SEC)
      end
      self:setStatus(self:getShotDenyToastText(payload.code), Constants.COLOR_DANGER)
      return
    end
    self:setStatus(t("match.status.server_error", {
      code = tostring(payload.code or t("common.unknown"))
    }), Constants.COLOR_DANGER)
    return
  end

  if envelope.type == "room.closed" then
    self._app:goMultiplayer({
      backScene = "play",
      statusText = t("match.status.room_closed"),
      statusColor = Constants.COLOR_DANGER
    }, Config.TRANSITION_BACK)
  end
end

function MatchScene:onSceneWillChange(_event)
  self:clearPredictiveState()
  self:cancelAimDrag(true)
  if self._inGameChat then
    self._inGameChat:closeImmediate()
  end
  if self._playingCardHandBar then
    self._playingCardHandBar:cancelCardDrag(false)
  end
end

function MatchScene:exit()
  self:clearPredictiveState()
  self:cancelAimDrag(true)
  if self._inGameChat then
    self._inGameChat:closeImmediate()
  end
  if self._playingCardHandBar then
    self._playingCardHandBar:cancelCardDrag(false)
  end
end

function MatchScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
    return
  end

  if event.type == "server_envelope" then
    if self._inGameChat then
      self._inGameChat:onServerEnvelope(event.envelope)
    end
    self:onServerEnvelope(event.envelope)
    return
  end

  if event.type == "server_close" then
    self:setStatus(t("match.status.server_close", {
      reason = tostring(event.reason)
    }), Constants.COLOR_DANGER)
    return
  end

  if event.type == "server_error" then
    self:setStatus(t("match.status.server_error_event", {
      message = tostring(event.message)
    }), Constants.COLOR_DANGER)
    return
  end

  if event.type == "focus_lost" then
    self:cancelAimDrag(true)
    if self._inGameChat then
      self._inGameChat:onFocusLost()
    end
    if self._playingCardHandBar then
      self._playingCardHandBar:cancelCardDrag(false)
    end
  end
end

return MatchScene
