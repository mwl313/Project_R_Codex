--[[
파일명: card_hand_bar.lua
모듈명: CardHandBar

역할:
- 인게임 하단 카드 핸드 UI(peek/open, hover, drag-drop)를 담당한다.
- 카드 선언(drop in center)과 타겟팅 진입은 콜백으로 위임해 네트워크/룰 로직을 분리한다.

외부에서 사용 가능한 함수:
- CardHandBar.new(params)
- CardHandBar:setCards(cardList)
- CardHandBar:update(dt, mouseX, mouseY, opts)
- CardHandBar:draw()
- CardHandBar:mousepressed(mouseX, mouseY, button)
- CardHandBar:mousereleased(mouseX, mouseY, button)
- CardHandBar:isDraggingCard()
- CardHandBar:cancelCardDrag(shouldAnimate)
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local CardWidget = require("ui.card_widget")
local DropZone = require("ui.drop_zone")

local CardHandBar = {}
CardHandBar.__index = CardHandBar

local function t(key, vars)
  return I18n.t(key, vars)
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

local function lerp(fromValue, toValue, alpha)
  return fromValue + (toValue - fromValue) * alpha
end

local function easeOutCubic(alpha)
  local tValue = clamp(alpha, 0, 1)
  local inv = 1 - tValue
  return 1 - inv * inv * inv
end

local function easeInCubic(alpha)
  local tValue = clamp(alpha, 0, 1)
  return tValue * tValue * tValue
end

local function pointInRect(x, y, rect)
  if not rect then
    return false
  end
  return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function CardHandBar.new(params)
  local centerX = params.boardCenterX or Constants.BASE_WORLD_W * 0.5
  local centerY = params.boardCenterY or Constants.BASE_WORLD_H * 0.5
  local instance = {
    _boardCenterX = centerX,
    _boardCenterY = centerY,
    _canUseCardFn = params.canUseCard,
    _onCardDeclaredFn = params.onCardDeclared,
    _onCardBlockedFn = params.onCardBlocked,
    _isPlayingPhase = false,
    _isStoneDragging = false,
    _cardList = {},
    _peekRect = nil,
    _openRect = nil,
    _openProgress = 0,
    _closeOutsideElapsedSec = 0,
    _hoverCardId = nil,
    _dragCardId = nil,
    _dragWorldX = 0,
    _dragWorldY = 0,
    _dragOffsetX = 0,
    _dragOffsetY = 0,
    _snapbackCloseHoldSec = 0,
    _dropZone = DropZone.new({
      centerX = centerX,
      centerY = centerY,
      size = Constants.CARD_DROP_ZONE_SIZE,
      flashPeriodSec = Constants.CARD_DROP_ZONE_FLASH_PERIOD_SEC,
      alphaMin = Constants.CARD_DROP_ZONE_ALPHA_MIN,
      alphaMax = Constants.CARD_DROP_ZONE_ALPHA_MAX
    }),
    _drawCardTemp = {}
  }
  return setmetatable(instance, CardHandBar)
end

function CardHandBar:setCards(cardList)
  local existingById = {}
  for _, entry in ipairs(self._cardList) do
    existingById[entry.id] = entry
  end

  local nextList = {}
  for index, card in ipairs(cardList or {}) do
    local cardId = tostring(card.id or "")
    if cardId ~= "" then
      local entry = existingById[cardId] or {
        id = cardId,
        w = Constants.CARD_W,
        h = Constants.CARD_H,
        slotX = Constants.BASE_WORLD_W * 0.5,
        slotY = Constants.BASE_WORLD_H + Constants.CARD_H * 0.5,
        drawX = Constants.BASE_WORLD_W * 0.5,
        drawY = Constants.BASE_WORLD_H + Constants.CARD_H * 0.5,
        drawScale = 1.0,
        returnAnim = nil
      }
      entry.label = tostring(card.label or cardId)
      entry.order = index
      nextList[#nextList + 1] = entry
    end
  end
  self._cardList = nextList

  if self._dragCardId and (not self:getCardEntryById(self._dragCardId)) then
    self._dragCardId = nil
  end
  if self._hoverCardId and (not self:getCardEntryById(self._hoverCardId)) then
    self._hoverCardId = nil
  end
end

function CardHandBar:getCardEntryById(cardId)
  for _, entry in ipairs(self._cardList) do
    if entry.id == cardId then
      return entry
    end
  end
  return nil
end

function CardHandBar:isDraggingCard()
  return self._dragCardId ~= nil
end

function CardHandBar:getClosedBaseY()
  return Constants.BASE_WORLD_H + Constants.CARD_H * 0.5 - Constants.CARD_HAND_PEEK_HEIGHT
end

function CardHandBar:getOpenBaseY()
  return self:getClosedBaseY() - Constants.CARD_HAND_OPEN_RISE_PX
end

function CardHandBar:getSlotPosition(index, count)
  local centerIndex = (count + 1) * 0.5
  local offset = index - centerIndex
  local easedOpenProgress = easeInCubic(self._openProgress)
  local openX = Constants.BASE_WORLD_W * 0.5 + offset * Constants.CARD_HAND_OPEN_SPACING
  local closedX = Constants.BASE_WORLD_W * 0.5 + offset * Constants.CARD_HAND_CLOSED_SPACING
  local arcYOffset = math.abs(offset) * Constants.CARD_HAND_OPEN_ARC_PX
  local openY = self:getOpenBaseY() + arcYOffset
  local closedY = self:getClosedBaseY()
  local x = lerp(closedX, openX, easedOpenProgress)
  local y = lerp(closedY, openY, easedOpenProgress)
  return x, y
end

function CardHandBar:updateInteractionRects()
  local count = #self._cardList
  if count <= 0 then
    self._peekRect = nil
    self._openRect = nil
    return
  end

  local openHalfWidth = ((count - 1) * Constants.CARD_HAND_OPEN_SPACING) * 0.5 + Constants.CARD_W * 0.5 + 28
  local openTop = self:getOpenBaseY() - Constants.CARD_H * 0.5 - 22
  self._openRect = {
    x = Constants.BASE_WORLD_W * 0.5 - openHalfWidth,
    y = openTop,
    w = openHalfWidth * 2,
    h = Constants.BASE_WORLD_H - openTop + 4
  }

  local peekHalfWidth = ((count - 1) * Constants.CARD_HAND_CLOSED_SPACING) * 0.5 + Constants.CARD_W * 0.5 + 24
  self._peekRect = {
    x = Constants.BASE_WORLD_W * 0.5 - peekHalfWidth,
    y = Constants.BASE_WORLD_H - Constants.CARD_HAND_PEEK_HEIGHT - 15,
    w = peekHalfWidth * 2,
    h = Constants.CARD_HAND_PEEK_HEIGHT + 5
  }
end

function CardHandBar:startReturnAnimation(entry, fromX, fromY, fromScale)
  entry.returnAnim = {
    fromX = fromX,
    fromY = fromY,
    fromScale = fromScale or 1.0,
    elapsedSec = 0,
    durationSec = Constants.CARD_HAND_RETURN_SEC
  }
end

function CardHandBar:removeCardById(cardId)
  for index, entry in ipairs(self._cardList) do
    if entry.id == cardId then
      table.remove(self._cardList, index)
      return entry
    end
  end
  return nil
end

function CardHandBar:canUseCard(cardId)
  if not self._canUseCardFn then
    return true
  end
  return self._canUseCardFn(cardId) == true
end

function CardHandBar:findTopCardIdAtPoint(mouseX, mouseY)
  for index = #self._cardList, 1, -1 do
    local entry = self._cardList[index]
    if entry.id ~= self._dragCardId then
      local scale = entry.drawScale or 1.0
      local halfW = (entry.w * scale) * 0.5
      local halfH = (entry.h * scale) * 0.5
      if mouseX >= entry.drawX - halfW
        and mouseX <= entry.drawX + halfW
        and mouseY >= entry.drawY - halfH
        and mouseY <= entry.drawY + halfH then
        return entry.id
      end
    end
  end
  return nil
end

function CardHandBar:cancelCardDrag(shouldAnimate)
  if not self._dragCardId then
    return
  end
  local entry = self:getCardEntryById(self._dragCardId)
  if entry then
    if shouldAnimate then
      self:startReturnAnimation(entry, self._dragWorldX, self._dragWorldY, 1 + Constants.CARD_HAND_DRAG_SCALE)
    else
      entry.returnAnim = nil
      entry.drawX = entry.slotX
      entry.drawY = entry.slotY
      entry.drawScale = 1.0
    end
  end
  self._dragCardId = nil
  self._hoverCardId = nil
end

function CardHandBar:update(dt, mouseX, mouseY, opts)
  local deltaSec = math.max(0, dt or 0)
  local wasSnapbackHoldActive = self._snapbackCloseHoldSec > 0
  if self._snapbackCloseHoldSec > 0 then
    self._snapbackCloseHoldSec = math.max(0, self._snapbackCloseHoldSec - deltaSec)
  end
  self._dropZone:update(deltaSec)
  self._dropZone:setCenter(self._boardCenterX, self._boardCenterY)

  self._isPlayingPhase = opts and opts.isPlayingPhase == true or false
  self._isStoneDragging = opts and opts.isStoneDragging == true or false

  self:updateInteractionRects()

  local shouldOpen = false
  if self._isPlayingPhase and #self._cardList > 0 and (not self._isStoneDragging) then
    local isInPeekRect = pointInRect(mouseX, mouseY, self._peekRect)
    local isInOpenRect = pointInRect(mouseX, mouseY, self._openRect)
    local isHandOpen = self._openProgress > 0.001

    local isInsideActiveZone = false
    if self._dragCardId then
      isInsideActiveZone = true
    elseif self._snapbackCloseHoldSec > 0 then
      isInsideActiveZone = true
    elseif isHandOpen then
      -- 열린 상태에서는 openRect(유지 영역) 기준으로 유지한다.
      isInsideActiveZone = isInOpenRect
    else
      -- 닫힌 상태에서는 peekRect(노출 영역)만으로 오픈을 시작한다.
      isInsideActiveZone = isInPeekRect
    end

    if isInsideActiveZone then
      shouldOpen = true
      self._closeOutsideElapsedSec = 0
    else
      if isHandOpen then
        if wasSnapbackHoldActive and self._snapbackCloseHoldSec <= 0 then
          -- 스냅백 유지가 끝난 프레임에는 즉시 닫힘으로 전환한다.
          self._closeOutsideElapsedSec = Constants.CARD_HAND_CLOSE_DELAY_SEC
        else
          self._closeOutsideElapsedSec = self._closeOutsideElapsedSec + deltaSec
        end
        shouldOpen = self._closeOutsideElapsedSec < Constants.CARD_HAND_CLOSE_DELAY_SEC
      else
        self._closeOutsideElapsedSec = 0
        shouldOpen = false
      end
    end
  else
    self._closeOutsideElapsedSec = 0
  end

  if self._isStoneDragging and self._dragCardId then
    self:cancelCardDrag(false)
  end
  if self._isStoneDragging then
    self._snapbackCloseHoldSec = 0
  end

  local transitionDurationSec = shouldOpen and Constants.CARD_HAND_OPEN_SEC or Constants.CARD_HAND_CLOSE_SEC
  local progressStep = transitionDurationSec > 0 and (deltaSec / transitionDurationSec) or 1
  if shouldOpen then
    self._openProgress = clamp(self._openProgress + progressStep, 0, 1)
  else
    self._openProgress = clamp(self._openProgress - progressStep, 0, 1)
  end

  local count = #self._cardList
  for index, entry in ipairs(self._cardList) do
    local slotX, slotY = self:getSlotPosition(index, count)
    entry.slotX = slotX
    entry.slotY = slotY
    if entry.returnAnim then
      local anim = entry.returnAnim
      anim.elapsedSec = anim.elapsedSec + deltaSec
      local alpha = anim.durationSec > 0 and clamp(anim.elapsedSec / anim.durationSec, 0, 1) or 1
      local eased = easeOutCubic(alpha)
      entry.drawX = lerp(anim.fromX, slotX, eased)
      entry.drawY = lerp(anim.fromY, slotY, eased)
      entry.drawScale = lerp(anim.fromScale, 1.0, eased)
      if alpha >= 1 then
        entry.returnAnim = nil
      end
    elseif entry.id ~= self._dragCardId then
      entry.drawX = slotX
      entry.drawY = slotY
      entry.drawScale = 1.0
    end
  end

  if self._dragCardId then
    local dragged = self:getCardEntryById(self._dragCardId)
    if dragged then
      self._dragWorldX = mouseX + self._dragOffsetX
      self._dragWorldY = mouseY + self._dragOffsetY
      dragged.drawX = self._dragWorldX
      dragged.drawY = self._dragWorldY
      dragged.drawScale = 1.0 + Constants.CARD_HAND_DRAG_SCALE
    end
    self._hoverCardId = nil
  elseif self._openProgress >= 0.92 and (not self._isStoneDragging) then
    self._hoverCardId = self:findTopCardIdAtPoint(mouseX, mouseY)
  else
    self._hoverCardId = nil
  end
end

function CardHandBar:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return false
  end
  if not self._isPlayingPhase then
    return false
  end
  if self._dragCardId then
    return true
  end
  if self._isStoneDragging then
    return false
  end

  local isInPeek = pointInRect(mouseX, mouseY, self._peekRect)
  local isInOpen = pointInRect(mouseX, mouseY, self._openRect)
  local isHandOpen = self._openProgress > 0.001
  if self._openProgress < 0.92 then
    if isHandOpen then
      return isInOpen
    end
    return isInPeek
  end

  local targetCardId = self._hoverCardId or self:findTopCardIdAtPoint(mouseX, mouseY)
  if targetCardId then
    if not self:canUseCard(targetCardId) then
      if self._onCardBlockedFn then
        self._onCardBlockedFn(targetCardId)
      end
      return true
    end

    local entry = self:getCardEntryById(targetCardId)
    if entry then
      self._dragCardId = targetCardId
      self._dragOffsetX = entry.drawX - mouseX
      self._dragOffsetY = entry.drawY - mouseY
      self._dragWorldX = entry.drawX
      self._dragWorldY = entry.drawY
      self._hoverCardId = nil
      return true
    end
  end

  if isHandOpen then
    return isInOpen
  end
  return isInPeek
end

function CardHandBar:mousereleased(mouseX, mouseY, button)
  if button ~= 1 then
    return false
  end
  if not self._dragCardId then
    return false
  end

  local draggedCardId = self._dragCardId
  local entry = self:getCardEntryById(draggedCardId)
  self._dragCardId = nil

  local isInsideDropZone = self._dropZone:isPointInside(mouseX, mouseY)
  if isInsideDropZone and self._onCardDeclaredFn then
    local isDeclared = self._onCardDeclaredFn(draggedCardId) == true
    if isDeclared then
      self:removeCardById(draggedCardId)
      self._snapbackCloseHoldSec = 0
      self._hoverCardId = nil
      return true
    end
  end

  if entry then
    self:startReturnAnimation(entry, self._dragWorldX, self._dragWorldY, 1.0 + Constants.CARD_HAND_DRAG_SCALE)
    self._snapbackCloseHoldSec = Constants.CARD_HAND_SNAPBACK_CLOSE_HOLD_SEC
  end
  self._hoverCardId = nil
  return true
end

function CardHandBar:draw()
  if #self._cardList <= 0 and self._openProgress <= 0 and (not self._dragCardId) then
    return
  end

  local baseAlpha = 0.08 + self._openProgress * 0.16
  local easedOpenProgress = easeInCubic(self._openProgress)
  local barHeight = (Constants.CARD_HAND_PEEK_HEIGHT + 5) + easedOpenProgress * (Constants.CARD_H * 0.22)
  local barY = Constants.BASE_WORLD_H - barHeight
  love.graphics.setColor(0.05, 0.06, 0.10, baseAlpha)
  love.graphics.rectangle("fill", 0, barY, Constants.BASE_WORLD_W, barHeight)

  for _, entry in ipairs(self._cardList) do
    if entry.id ~= self._dragCardId then
      local isHovered = entry.id == self._hoverCardId
      local scale = entry.drawScale or 1.0
      local drawX = entry.drawX
      local drawY = entry.drawY
      if isHovered then
        scale = scale + Constants.CARD_HAND_HOVER_SCALE
        drawY = drawY - Constants.CARD_HAND_HOVER_LIFT_PX
      end
      local card = self._drawCardTemp
      card.x = drawX
      card.y = drawY
      card.w = entry.w
      card.h = entry.h
      card.scale = scale
      card.alpha = 1.0
      card.label = entry.label
      card.isFaceUp = true
      card.isHovered = isHovered
      card.isSelected = false
      card.isDragged = false
      card.isDisabled = not self:canUseCard(entry.id)
      CardWidget.draw(card)
    end
  end

  if self._dragCardId then
    local dragged = self:getCardEntryById(self._dragCardId)
    if dragged then
      local dragCard = self._drawCardTemp
      dragCard.x = dragged.drawX
      dragCard.y = dragged.drawY
      dragCard.w = dragged.w
      dragCard.h = dragged.h
      dragCard.scale = dragged.drawScale or (1.0 + Constants.CARD_HAND_DRAG_SCALE)
      dragCard.alpha = 0.98
      dragCard.label = dragged.label
      dragCard.isFaceUp = true
      dragCard.isHovered = false
      dragCard.isSelected = false
      dragCard.isDragged = true
      dragCard.isDisabled = false
      CardWidget.draw(dragCard)
    end

    self._dropZone:setVisible(true)
    self._dropZone:draw()

    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(
      t("match.hand.drop_prompt"),
      self._boardCenterX - 200,
      self._boardCenterY + Constants.CARD_DROP_ZONE_SIZE * 0.5 + 10,
      400,
      "center"
    )
  else
    self._dropZone:setVisible(false)
  end
end

return CardHandBar
