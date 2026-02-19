--[[
파일명: card_animator.lua
모듈명: CardAnimator

역할:
- 카드 선택 페이즈의 연출 타임라인을 담당한다.
- 단계:
  DECK_ENTER -> SHUFFLE -> DEAL_OPP -> DEAL_ME -> REVEAL_LOCAL -> SELECT -> WAIT_LOCK -> CLEANUP -> DONE

외부에서 사용 가능한 함수:
- CardAnimator.new(params)
- animator:begin(myCards, requiredPickCount, opponentCardCount, totalPoolCount)
- animator:update(dt)
- animator:draw()
- animator:isOverlayVisible()
- animator:isSelectionInteractive()
- animator:getCardIdAtPoint(mouseX, mouseY)
- animator:setHoverCardId(cardId)
- animator:setSelectedCardList(selectedCardList)
- animator:setWaitingLock(isWaiting)
- animator:setLockState(isMyLocked, isOpponentLocked)
- animator:startCleanup()
]]

local Constants = require("constants")
local CardView = require("ui.card_view")

local CardAnimator = {}
CardAnimator.__index = CardAnimator

local STAGE = {
  DECK_ENTER = "DECK_ENTER",
  SHUFFLE = "SHUFFLE",
  DEAL_OPP = "DEAL_OPP",
  DEAL_ME = "DEAL_ME",
  REVEAL_LOCAL = "REVEAL_LOCAL",
  SELECT = "SELECT",
  WAIT_LOCK = "WAIT_LOCK",
  CLEANUP = "CLEANUP",
  DONE = "DONE"
}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function lerp(fromValue, toValue, progress)
  return fromValue + (toValue - fromValue) * progress
end

local function easeOutCubic(progress)
  local t = clamp(progress, 0, 1)
  return 1 - ((1 - t) ^ 3)
end

local function easeInOutQuad(progress)
  local t = clamp(progress, 0, 1)
  if t < 0.5 then
    return 2 * t * t
  end
  return 1 - ((-2 * t + 2) ^ 2) * 0.5
end

local function fanX(index, count, centerX, spacing)
  if count <= 1 then
    return centerX
  end
  local leftX = centerX - ((count - 1) * spacing) * 0.5
  return leftX + (index - 1) * spacing
end

local function randomInt(minValue, maxValue)
  if love and love.math and love.math.random then
    return love.math.random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

local function randomBetween(minValue, maxValue)
  local span = maxValue - minValue
  if span <= 0 then
    return minValue
  end
  local randomValue
  if love and love.math and love.math.random then
    randomValue = love.math.random()
  else
    randomValue = math.random()
  end
  return minValue + randomValue * span
end

local function shuffleList(valueList)
  for index = #valueList, 2, -1 do
    local swapIndex = randomInt(1, index)
    valueList[index], valueList[swapIndex] = valueList[swapIndex], valueList[index]
  end
end

local function pickSegmentedPosition(slotIndex, slotCount, minValue, maxValue)
  local span = maxValue - minValue
  if span <= 0 then
    return minValue
  end
  if slotCount <= 1 then
    return minValue + span * 0.5 + randomBetween(-span * 0.08, span * 0.08)
  end

  local segment = span / slotCount
  local center = minValue + segment * (slotIndex - 0.5)
  local jitter = segment * 0.34
  return clamp(center + randomBetween(-jitter, jitter), minValue, maxValue)
end

function CardAnimator.new(params)
  local boardX = params.boardX or 0
  local boardY = params.boardY or 0
  local boardW = params.boardW or Constants.BOARD_W
  local boardH = params.boardH or Constants.BOARD_H

  local instance = {
    _boardX = boardX,
    _boardY = boardY,
    _boardW = boardW,
    _boardH = boardH,

    _cardW = Constants.CARD_W or 118,
    _cardH = Constants.CARD_H or 166,
    _hoverLiftPx = Constants.CARD_HOVER_LIFT_PX or 16,
    _hoverScale = Constants.CARD_HOVER_SCALE or 0.06,
    _glowAlpha = Constants.CARD_GLOW_ALPHA or 0.28,
    _borderThickness = Constants.CARD_BORDER_THICKNESS or 3,
    _localFanSpacing = Constants.CARD_LOCAL_FAN_SPACING or 132,
    _opponentFanSpacing = Constants.CARD_OPPONENT_FAN_SPACING or 86,

    _deckEnterSec = Constants.CARD_DECK_ENTER_SEC or 0.42,
    _shuffleSec = Constants.CARD_SHUFFLE_SEC or 0.46,
    _dealSec = Constants.CARD_DEAL_SEC or 0.30,
    _dealStaggerSec = Constants.CARD_DEAL_STAGGER_SEC or 0.09,
    _flipSec = Constants.CARD_FLIP_SEC or 0.28,
    _flipStaggerSec = Constants.CARD_FLIP_STAGGER_SEC or 0.08,
    _cleanupSec = Constants.CARD_CLEANUP_SEC or 0.62,

    _deckTotalCount = 0,
    _requiredPickCount = 0,
    _myCardList = {},
    _opponentCardList = {},
    _selectedSet = {},
    _hoveredCardId = nil,
    _isMyLocked = false,
    _isOpponentLocked = false,

    _stage = STAGE.DONE,
    _stageElapsedSec = 0,
    _stageDurationSec = 0,
    _isVisible = false,
    _cleanupInitialized = false,
    _cleanupMoveList = {},
    _cleanupFadeList = {},
    _deckEnterSourceList = {}
  }
  return setmetatable(instance, CardAnimator)
end

function CardAnimator:_enterStage(stageName)
  self._stage = stageName
  self._stageElapsedSec = 0
  self._hoveredCardId = nil

  if stageName == STAGE.DECK_ENTER then
    self._stageDurationSec = self._deckEnterSec
    return
  end
  if stageName == STAGE.SHUFFLE then
    self._stageDurationSec = self._shuffleSec
    return
  end
  if stageName == STAGE.DEAL_OPP then
    local opponentCount = #self._opponentCardList
    self._stageDurationSec = math.max(0.2, self._dealSec + math.max(0, opponentCount - 1) * self._dealStaggerSec + 0.04)
    return
  end
  if stageName == STAGE.DEAL_ME then
    local localCount = #self._myCardList
    self._stageDurationSec = math.max(0.2, self._dealSec + math.max(0, localCount - 1) * self._dealStaggerSec + 0.06)
    return
  end
  if stageName == STAGE.REVEAL_LOCAL then
    local localCount = #self._myCardList
    self._stageDurationSec = math.max(0.2, self._flipSec + math.max(0, localCount - 1) * self._flipStaggerSec + 0.04)
    return
  end
  if stageName == STAGE.SELECT or stageName == STAGE.WAIT_LOCK then
    self._stageDurationSec = 0
    return
  end
  if stageName == STAGE.CLEANUP then
    self._stageDurationSec = self._cleanupSec
    self._cleanupInitialized = false
    return
  end
  self._stageDurationSec = 0
end

function CardAnimator:_buildHandTargets()
  local centerX = self._boardX + self._boardW * 0.5
  local opponentY = self._boardY + 118
  local localY = self._boardY + self._boardH - 108

  for index, card in ipairs(self._opponentCardList) do
    card.targetX = fanX(index, #self._opponentCardList, centerX, self._opponentFanSpacing)
    card.targetY = opponentY
    card.x = self._boardX + self._boardW * 0.5
    card.y = self._boardY + self._boardH * 0.5
    card.faceUp = false
    card.flipScaleX = 1.0
  end

  for index, card in ipairs(self._myCardList) do
    card.targetX = fanX(index, #self._myCardList, centerX, self._localFanSpacing)
    card.targetY = localY
    card.x = self._boardX + self._boardW * 0.5
    card.y = self._boardY + self._boardH * 0.5
    card.faceUp = false
    card.flipScaleX = 1.0
  end
end

function CardAnimator:_buildDeckEnterSourceList()
  self._deckEnterSourceList = {}
  local screenW = Constants.BASE_WORLD_W
  local screenH = Constants.BASE_WORLD_H
  local marginX = self._cardW + 120
  local marginY = self._cardH + 120

  local deckCount = math.max(0, self._deckTotalCount)
  if deckCount <= 0 then
    return
  end

  local sideCounts = { 0, 0, 0, 0 }
  local baseCount = math.floor(deckCount / 4)
  local remainCount = deckCount - baseCount * 4
  for side = 1, 4 do
    sideCounts[side] = baseCount
  end

  local remainSides = { 1, 2, 3, 4 }
  shuffleList(remainSides)
  for index = 1, remainCount do
    sideCounts[remainSides[index]] = sideCounts[remainSides[index]] + 1
  end

  local sideOrder = {}
  for side = 1, 4 do
    for _ = 1, sideCounts[side] do
      sideOrder[#sideOrder + 1] = side
    end
  end
  shuffleList(sideOrder)

  local sideUseCount = { 0, 0, 0, 0 }
  for index = 1, deckCount do
    local side = sideOrder[index]
    sideUseCount[side] = sideUseCount[side] + 1
    local sideSlotIndex = sideUseCount[side]
    local sideSlotCount = math.max(1, sideCounts[side])

    local sourceX = 0
    local sourceY = 0
    if side == 1 then
      sourceX = -marginX
      sourceY = pickSegmentedPosition(sideSlotIndex, sideSlotCount, -marginY, screenH + marginY)
    elseif side == 2 then
      sourceX = screenW + marginX
      sourceY = pickSegmentedPosition(sideSlotIndex, sideSlotCount, -marginY, screenH + marginY)
    elseif side == 3 then
      sourceX = pickSegmentedPosition(sideSlotIndex, sideSlotCount, -marginX, screenW + marginX)
      sourceY = -marginY
    else
      sourceX = pickSegmentedPosition(sideSlotIndex, sideSlotCount, -marginX, screenW + marginX)
      sourceY = screenH + marginY
    end
    self._deckEnterSourceList[index] = {
      x = sourceX,
      y = sourceY
    }
  end
end

function CardAnimator:begin(myCards, requiredPickCount, opponentCardCount, totalPoolCount)
  self._requiredPickCount = tonumber(requiredPickCount) or 0
  self._selectedSet = {}
  self._isMyLocked = false
  self._isOpponentLocked = false
  self._cleanupInitialized = false
  self._cleanupMoveList = {}
  self._cleanupFadeList = {}

  self._myCardList = {}
  for index, card in ipairs(myCards or {}) do
    self._myCardList[index] = {
      id = tostring(card.id),
      label = tostring(card.label or card.id),
      backLabel = "?",
      x = 0,
      y = 0,
      targetX = 0,
      targetY = 0,
      faceUp = false,
      flipScaleX = 1.0
    }
  end

  self._opponentCardList = {}
  local clampedOpponentCount = math.max(0, math.floor(tonumber(opponentCardCount) or 0))
  for index = 1, clampedOpponentCount do
    self._opponentCardList[index] = {
      id = "opponent_" .. tostring(index),
      label = "",
      backLabel = "?",
      x = 0,
      y = 0,
      targetX = 0,
      targetY = 0,
      faceUp = false,
      flipScaleX = 1.0
    }
  end

  local defaultDeckCount = #self._myCardList + #self._opponentCardList
  local resolvedDeckCount = math.max(defaultDeckCount, math.floor(tonumber(totalPoolCount) or 0))
  self._deckTotalCount = resolvedDeckCount

  self:_buildHandTargets()
  self:_buildDeckEnterSourceList()
  self._isVisible = true
  self:_enterStage(STAGE.DECK_ENTER)
end

function CardAnimator:isOverlayVisible()
  return self._isVisible and self._stage ~= STAGE.DONE
end

function CardAnimator:isSelectionInteractive()
  return self._stage == STAGE.SELECT and (not self._isMyLocked)
end

function CardAnimator:getStage()
  return self._stage
end

function CardAnimator:setHoverCardId(cardId)
  if not self:isSelectionInteractive() then
    self._hoveredCardId = nil
    return
  end
  self._hoveredCardId = cardId
end

function CardAnimator:setSelectedCardList(selectedCardList)
  self._selectedSet = {}
  for _, cardId in ipairs(selectedCardList or {}) do
    self._selectedSet[tostring(cardId)] = true
  end
end

function CardAnimator:_getCardLiftAndScale(card)
  local isSelected = self._selectedSet[card.id] == true
  local isHovered = (self._hoveredCardId == card.id) and self:isSelectionInteractive()
  if isSelected or isHovered then
    return self._hoverLiftPx, 1.0 + self._hoverScale, isHovered, isSelected
  end
  return 0, 1.0, false, false
end

function CardAnimator:getCardIdAtPoint(mouseX, mouseY)
  if not self:isSelectionInteractive() then
    return nil
  end

  for index = #self._myCardList, 1, -1 do
    local card = self._myCardList[index]
    local liftY, scale = self:_getCardLiftAndScale(card)
    local probeCard = {
      x = card.targetX,
      y = card.targetY - liftY,
      w = self._cardW,
      h = self._cardH,
      scale = scale
    }
    if CardView.hitTest(probeCard, mouseX, mouseY) then
      return card.id
    end
  end
  return nil
end

function CardAnimator:setWaitingLock(isWaiting)
  if isWaiting and self._stage == STAGE.SELECT then
    self:_enterStage(STAGE.WAIT_LOCK)
    return
  end
  if (not isWaiting) and self._stage == STAGE.WAIT_LOCK and (not self._isMyLocked) then
    self:_enterStage(STAGE.SELECT)
  end
end

function CardAnimator:setLockState(isMyLocked, isOpponentLocked)
  self._isMyLocked = isMyLocked == true
  self._isOpponentLocked = isOpponentLocked == true

  if self._isMyLocked and self._stage == STAGE.SELECT then
    self:_enterStage(STAGE.WAIT_LOCK)
  end

  if self._isMyLocked and self._isOpponentLocked then
    self:startCleanup()
  end
end

function CardAnimator:startCleanup()
  if self._stage == STAGE.CLEANUP or self._stage == STAGE.DONE then
    return
  end
  self:_enterStage(STAGE.CLEANUP)
end

function CardAnimator:_updateDealCards(cardList)
  for index, card in ipairs(cardList) do
    local delay = (index - 1) * self._dealStaggerSec
    local progress = clamp((self._stageElapsedSec - delay) / self._dealSec, 0, 1)
    local eased = easeOutCubic(progress)
    card.x = lerp(self._boardX + self._boardW * 0.5, card.targetX, eased)
    card.y = lerp(self._boardY + self._boardH * 0.5, card.targetY, eased)
  end
end

function CardAnimator:_updateRevealCards()
  for index, card in ipairs(self._myCardList) do
    card.x = card.targetX
    card.y = card.targetY
    local delay = (index - 1) * self._flipStaggerSec
    local progress = clamp((self._stageElapsedSec - delay) / self._flipSec, 0, 1)
    local angle = progress * math.pi
    card.flipScaleX = math.max(0.06, math.abs(math.cos(angle)))
    card.faceUp = progress >= 0.5
  end
end

function CardAnimator:_initializeCleanup()
  self._cleanupInitialized = true
  self._cleanupMoveList = {}
  self._cleanupFadeList = {}

  for _, card in ipairs(self._opponentCardList) do
    self._cleanupMoveList[#self._cleanupMoveList + 1] = {
      fromX = card.targetX,
      fromY = card.targetY,
      label = "",
      faceUp = false
    }
  end
  for _, card in ipairs(self._myCardList) do
    if self._selectedSet[card.id] then
      self._cleanupFadeList[#self._cleanupFadeList + 1] = {
        x = card.targetX,
        y = card.targetY,
        label = card.label
      }
    else
      self._cleanupMoveList[#self._cleanupMoveList + 1] = {
        fromX = card.targetX,
        fromY = card.targetY,
        label = card.label,
        faceUp = false
      }
    end
  end
end

function CardAnimator:update(dt)
  if not self:isOverlayVisible() then
    return
  end

  if self._stage == STAGE.SELECT or self._stage == STAGE.WAIT_LOCK then
    return
  end

  self._stageElapsedSec = self._stageElapsedSec + dt

  if self._stage == STAGE.DEAL_OPP then
    self:_updateDealCards(self._opponentCardList)
  elseif self._stage == STAGE.DEAL_ME then
    self:_updateDealCards(self._myCardList)
  elseif self._stage == STAGE.REVEAL_LOCAL then
    self:_updateRevealCards()
  elseif self._stage == STAGE.CLEANUP and (not self._cleanupInitialized) then
    self:_initializeCleanup()
  end

  if self._stageDurationSec <= 0 or self._stageElapsedSec < self._stageDurationSec then
    return
  end

  if self._stage == STAGE.DECK_ENTER then
    self:_enterStage(STAGE.SHUFFLE)
    return
  end
  if self._stage == STAGE.SHUFFLE then
    self:_enterStage(STAGE.DEAL_OPP)
    return
  end
  if self._stage == STAGE.DEAL_OPP then
    for _, card in ipairs(self._opponentCardList) do
      card.x = card.targetX
      card.y = card.targetY
      card.faceUp = false
      card.flipScaleX = 1.0
    end
    self:_enterStage(STAGE.DEAL_ME)
    return
  end
  if self._stage == STAGE.DEAL_ME then
    for _, card in ipairs(self._myCardList) do
      card.x = card.targetX
      card.y = card.targetY
      card.faceUp = false
      card.flipScaleX = 1.0
    end
    self:_enterStage(STAGE.REVEAL_LOCAL)
    return
  end
  if self._stage == STAGE.REVEAL_LOCAL then
    for _, card in ipairs(self._myCardList) do
      card.faceUp = true
      card.flipScaleX = 1.0
      card.x = card.targetX
      card.y = card.targetY
    end
    if self._isMyLocked then
      self:_enterStage(STAGE.WAIT_LOCK)
    else
      self:_enterStage(STAGE.SELECT)
    end
    return
  end
  if self._stage == STAGE.CLEANUP then
    self:_enterStage(STAGE.DONE)
    self._isVisible = false
  end
end

function CardAnimator:_drawDeckStack(count)
  local centerX = self._boardX + self._boardW * 0.5
  local centerY = self._boardY + self._boardH * 0.5
  local drawCount = math.max(0, math.floor(count))
  for index = 1, drawCount do
    CardView.drawCard({
      x = centerX + (index - 1) * 1.6,
      y = centerY + (index - 1) * 1.2,
      w = self._cardW,
      h = self._cardH,
      label = "",
      backLabel = "?",
      isFaceUp = false,
      scale = 1.0,
      alpha = 1.0,
      flipScaleX = 1.0,
      borderThickness = self._borderThickness,
      glowAlpha = self._glowAlpha,
      isHovered = false,
      isSelected = false
    })
  end
end

function CardAnimator:_drawDeckEnter()
  local centerX = self._boardX + self._boardW * 0.5
  local centerY = self._boardY + self._boardH * 0.5
  local deckCount = math.max(0, self._deckTotalCount)
  if deckCount <= 0 then
    return
  end

  local perCardDelay = clamp(self._deckEnterSec / math.max(deckCount + 1, 2), 0.03, 0.12)
  local moveDuration = math.max(0.10, self._deckEnterSec - math.max(0, deckCount - 1) * perCardDelay)
  for index = 1, deckCount do
    local delay = (index - 1) * perCardDelay
    if self._stageElapsedSec >= delay then
      local progress = clamp((self._stageElapsedSec - delay) / moveDuration, 0, 1)
      local eased = easeOutCubic(progress)
      local source = self._deckEnterSourceList[index] or {
        x = -self._cardW - 120,
        y = centerY
      }
      local stackOffsetX = (index - 1) * 1.8 - (deckCount - 1) * 0.9
      local stackOffsetY = (index - 1) * 1.2 - (deckCount - 1) * 0.6
      CardView.drawCard({
        x = lerp(source.x, centerX + stackOffsetX, eased),
        y = lerp(source.y, centerY + stackOffsetY, eased),
        w = self._cardW,
        h = self._cardH,
        label = "",
        backLabel = "?",
        isFaceUp = false,
        scale = 1.0,
        alpha = 1.0,
        flipScaleX = 1.0,
        borderThickness = self._borderThickness,
        glowAlpha = self._glowAlpha,
        isHovered = false,
        isSelected = false
      })
    end
  end
end

function CardAnimator:_drawShuffle()
  local centerX = self._boardX + self._boardW * 0.5
  local centerY = self._boardY + self._boardH * 0.5
  local progress = clamp(self._stageElapsedSec / math.max(0.001, self._shuffleSec), 0, 1)
  for index = 1, self._deckTotalCount do
    local phase = progress * math.pi * 6 + index * 0.8
    local offsetX = math.sin(phase) * (8 + index * 1.2)
    local offsetY = math.cos(phase * 0.9) * (4 + index * 0.7)
    CardView.drawCard({
      x = centerX + offsetX,
      y = centerY + offsetY,
      w = self._cardW,
      h = self._cardH,
      label = "",
      backLabel = "?",
      isFaceUp = false,
      scale = 1.0,
      alpha = 1.0,
      flipScaleX = 1.0,
      borderThickness = self._borderThickness,
      glowAlpha = self._glowAlpha,
      isHovered = false,
      isSelected = false
    })
  end
end

function CardAnimator:_drawOpponentHand()
  for _, card in ipairs(self._opponentCardList) do
    CardView.drawCard({
      x = card.x,
      y = card.y,
      w = self._cardW,
      h = self._cardH,
      label = "",
      backLabel = "?",
      isFaceUp = false,
      scale = 1.0,
      alpha = 1.0,
      flipScaleX = 1.0,
      borderThickness = self._borderThickness,
      glowAlpha = self._glowAlpha,
      isHovered = false,
      isSelected = false
    })
  end
end

function CardAnimator:_drawLocalHand()
  for _, card in ipairs(self._myCardList) do
    local liftY, scale, isHovered, isSelected = self:_getCardLiftAndScale(card)
    CardView.drawCard({
      x = card.x,
      y = card.y - liftY,
      w = self._cardW,
      h = self._cardH,
      label = card.label,
      backLabel = "?",
      isFaceUp = card.faceUp,
      scale = scale,
      alpha = 1.0,
      flipScaleX = card.flipScaleX or 1.0,
      borderThickness = self._borderThickness,
      glowAlpha = self._glowAlpha,
      isHovered = isHovered,
      isSelected = isSelected
    })
  end
end

function CardAnimator:_drawCleanup()
  local progress = clamp(self._stageElapsedSec / math.max(0.001, self._cleanupSec), 0, 1)
  local centerX = self._boardX + self._boardW * 0.5
  local centerY = self._boardY + self._boardH * 0.5
  local splitPoint = 0.55

  for _, card in ipairs(self._cleanupFadeList) do
    local alpha = 1.0 - clamp(progress / splitPoint, 0, 1)
    if alpha > 0 then
      CardView.drawCard({
        x = card.x,
        y = card.y,
        w = self._cardW,
        h = self._cardH,
        label = card.label,
        backLabel = "?",
        isFaceUp = true,
        scale = 1.0,
        alpha = alpha,
        flipScaleX = 1.0,
        borderThickness = self._borderThickness,
        glowAlpha = self._glowAlpha,
        isHovered = false,
        isSelected = false
      })
    end
  end

  for index, card in ipairs(self._cleanupMoveList) do
    local stackX = centerX + (index - 1) * 1.6
    local stackY = centerY + (index - 1) * 1.0
    local drawX = stackX
    local drawY = stackY
    if progress < splitPoint then
      local phaseProgress = easeOutCubic(progress / splitPoint)
      drawX = lerp(card.fromX, stackX, phaseProgress)
      drawY = lerp(card.fromY, stackY, phaseProgress)
    else
      local phaseProgress = easeInOutQuad((progress - splitPoint) / (1 - splitPoint))
      drawX = lerp(stackX, Constants.BASE_WORLD_W + self._cardW + 240, phaseProgress)
      drawY = lerp(stackY, centerY - 36, phaseProgress)
    end

    CardView.drawCard({
      x = drawX,
      y = drawY,
      w = self._cardW,
      h = self._cardH,
      label = card.label,
      backLabel = "?",
      isFaceUp = false,
      scale = 1.0,
      alpha = 1.0,
      flipScaleX = 1.0,
      borderThickness = self._borderThickness,
      glowAlpha = self._glowAlpha,
      isHovered = false,
      isSelected = false
    })
  end
end

function CardAnimator:draw()
  if not self:isOverlayVisible() then
    return
  end

  if self._stage == STAGE.DECK_ENTER then
    self:_drawDeckEnter()
    return
  end
  if self._stage == STAGE.SHUFFLE then
    self:_drawShuffle()
    return
  end
  if self._stage == STAGE.DEAL_OPP then
    self:_drawDeckStack(self._deckTotalCount - #self._opponentCardList)
    self:_drawOpponentHand()
    return
  end
  if self._stage == STAGE.DEAL_ME then
    self:_drawDeckStack(self._deckTotalCount - #self._opponentCardList - #self._myCardList)
    self:_drawOpponentHand()
    self:_drawLocalHand()
    return
  end
  if self._stage == STAGE.REVEAL_LOCAL or self._stage == STAGE.SELECT or self._stage == STAGE.WAIT_LOCK then
    self:_drawOpponentHand()
    self:_drawLocalHand()
    return
  end
  if self._stage == STAGE.CLEANUP then
    self:_drawCleanup()
  end
end

return CardAnimator
