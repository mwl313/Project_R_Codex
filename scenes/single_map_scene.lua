--[[
파일명: single_map_scene.lua
모듈명: SingleMapScene

역할:
- 싱글 런 맵(노드 진행) 표시 및 전투 진입을 담당한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local SingleRunManager = require("single.single_run_manager")
local SingleDeckManager = require("single.single_deck_manager")
local SingleRunState = require("single.single_run_state")

local SingleMapScene = {}
SingleMapScene.__index = SingleMapScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function getDefaultDeck(profile)
  if type(profile) ~= "table" or type(profile.decks) ~= "table" then
    return nil
  end
  for _, deck in ipairs(profile.decks) do
    if type(deck) == "table" and tostring(deck.deckId or "") == "default" then
      return deck
    end
  end
  return profile.decks[1]
end

function SingleMapScene.new(app)
  local instance = {
    _app = app,
    _backScene = "single_campaign",
    _profile = nil,
    _runState = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage(),
    _backButton = nil,
    _battleButton = nil,
    _choiceButtonList = {},
    _choiceNodeList = {}
  }
  setmetatable(instance, SingleMapScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleMapScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

local function resolveNodeTitle(node)
  if type(node) ~= "table" then
    return t("single.map.node_default")
  end
  if type(node.titleKey) == "string" and node.titleKey ~= "" then
    local translated = t(node.titleKey)
    if type(translated) == "string" and not translated:find("^%[%[missing:") then
      return translated
    end
  end
  if type(node.fallbackTitleKo) == "string" and node.fallbackTitleKo ~= "" then
    return node.fallbackTitleKo
  end
  if type(node.titleKo) == "string" and node.titleKo ~= "" then
    return node.titleKo
  end
  if type(node.nodeId) == "string" and node.nodeId ~= "" then
    return node.nodeId
  end
  return t("single.map.node_default")
end

local function getChoiceDedupKey(node)
  if type(node) ~= "table" then
    return "unknown"
  end
  if type(node.titleKey) == "string" and node.titleKey ~= "" then
    return "titleKey:" .. node.titleKey
  end
  if type(node.type) == "string" and node.type ~= "" then
    return "type:" .. node.type
  end
  return "title:" .. resolveNodeTitle(node)
end

local function isCombatNodeType(nodeType)
  local normalized = tostring(nodeType or "")
  return normalized == "mob" or normalized == "elite" or normalized == "boss"
end

function SingleMapScene:ensureDepthSelection()
  local depth = SingleRunManager.getCurrentDepth(self._runState)
  local choices = SingleRunManager.getChoices(self._runState)
  local firstNode = choices and choices[1]
  if type(firstNode) ~= "table" then
    return false
  end

  local selectedByDepth = type(self._runState) == "table" and self._runState.selectedByDepth or nil
  if type(selectedByDepth) == "table" and selectedByDepth[depth] then
    local currentNode = SingleRunManager.getCurrentNode(self._runState)
    if currentNode and tostring(currentNode.nodeId or "") == tostring(selectedByDepth[depth]) then
      return true
    end
  end

  local ok = SingleRunManager.selectChoice(self._runState, firstNode.nodeId)
  if ok then
    self:setStatus(t("single.map.status.selected", {
      nodeTitle = resolveNodeTitle(firstNode)
    }), Constants.COLOR_TEXT_SUB)
    return true
  end
  return false
end

function SingleMapScene:rebuildChoiceButtons()
  self._choiceButtonList = {}
  self._choiceNodeList = {}

  local rawChoices = SingleRunManager.getChoices(self._runState)
  local seenByKey = {}
  for _, node in ipairs(rawChoices) do
    local dedupKey = getChoiceDedupKey(node)
    if not seenByKey[dedupKey] then
      seenByKey[dedupKey] = true
      self._choiceNodeList[#self._choiceNodeList + 1] = node
    end
  end

  local count = #self._choiceNodeList
  if count <= 0 then
    self:updateActionButtonLabel()
    return
  end

  local buttonWidth = 210
  local buttonHeight = 72
  local gap = 20
  local totalWidth = count * buttonWidth + (count - 1) * gap
  local startX = (Constants.BASE_WORLD_W - totalWidth) * 0.5
  local startY = 330

  for index, node in ipairs(self._choiceNodeList) do
    local nodeId = node.nodeId
    self._choiceButtonList[index] = Button.new({
      x = startX + (index - 1) * (buttonWidth + gap),
      y = startY,
      w = buttonWidth,
      h = buttonHeight,
      label = resolveNodeTitle(node),
      onClick = function()
        local ok = SingleRunManager.selectChoice(self._runState, nodeId)
        if ok then
          self:setStatus(t("single.map.status.selected", {
            nodeTitle = resolveNodeTitle(node)
          }), Constants.COLOR_TEXT_SUB)
          self:rebuildChoiceButtons()
          return
        end
        self._runState.choiceSets = type(self._runState.choiceSets) == "table" and self._runState.choiceSets or {}
        self._runState.choiceSets[SingleRunManager.getCurrentDepth(self._runState)] = nil
        self:rebuildChoiceButtons()
        if self:ensureDepthSelection() then
          local currentNode = SingleRunManager.getCurrentNode(self._runState)
          self:setStatus(t("single.map.status.selected", {
            nodeTitle = resolveNodeTitle(currentNode)
          }), Constants.COLOR_TEXT_SUB)
        else
          self:setStatus(t("single.map.status.select_invalid"), Constants.COLOR_DANGER)
        end
      end
    })
  end
  self:updateActionButtonLabel()
end

function SingleMapScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end)

  self._battleButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 478,
    label = t("single.map.button.start_combat"),
    onClick = function()
      self:startCombat()
    end
  })

  self:rebuildChoiceButtons()
  self:updateActionButtonLabel()
end

function SingleMapScene:updateActionButtonLabel()
  if not self._battleButton then
    return
  end
  local currentNode = SingleRunManager.getCurrentNode(self._runState)
  if isCombatNodeType(currentNode and currentNode.type) then
    self._battleButton.label = t("single.map.button.start_combat")
  else
    self._battleButton.label = t("single.map.button.enter_node")
  end
end

function SingleMapScene:startCombat()
  local currentNode = SingleRunManager.getCurrentNode(self._runState)
  if not currentNode then
    self._app:goScene("single_result", {
      profile = self._profile,
      runState = self._runState,
      result = "win"
    }, Config.TRANSITION_FORWARD)
    return
  end

  local nodeType = tostring(currentNode.type or "mob")
  local sceneParams = {
    backScene = "single_map",
    profile = self._profile,
    runState = self._runState,
    nodeType = nodeType,
    nodeId = currentNode.nodeId,
    stageIndex = currentNode.stageIndex
  }

  if nodeType == "shop" then
    self._app:goScene("single_shop", sceneParams, Config.TRANSITION_FORWARD)
    return
  end
  if nodeType == "rest" then
    self._app:goScene("single_rest", sceneParams, Config.TRANSITION_FORWARD)
    return
  end
  if nodeType == "deck_clean" then
    self._app:goScene("single_deck_clean", sceneParams, Config.TRANSITION_FORWARD)
    return
  end
  if nodeType == "event" then
    self._app:goScene("single_event", sceneParams, Config.TRANSITION_FORWARD)
    return
  end

  self._app:goScene("single_combat", sceneParams, Config.TRANSITION_FORWARD)
end

function SingleMapScene:enter(params)
  self._backScene = (params and params.backScene) or "single_campaign"
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil

  if type(self._runState) ~= "table" then
    self._runState = SingleRunManager.newRun("default")
  end
  SingleRunState.ensureDefaults(self._runState, self._profile)

  self:rebuildLocalizedUi()
  self:ensureDepthSelection()

  local deck = getDefaultDeck(self._profile)
  if deck then
    local valid = SingleDeckManager.validateDeck(deck, self._profile.collection)
    if not valid then
      self:setStatus(t("single.map.status.deck_invalid"), Constants.COLOR_DANGER)
    else
      local currentNode = SingleRunManager.getCurrentNode(self._runState)
      if currentNode then
        self:setStatus(t("single.map.status.selected", {
          nodeTitle = resolveNodeTitle(currentNode)
        }), Constants.COLOR_TEXT_SUB)
      else
        self:setStatus(t("single.map.status.ready"), Constants.COLOR_TEXT_SUB)
      end
    end
  else
    self:setStatus(t("single.map.status.deck_missing"), Constants.COLOR_DANGER)
  end
end

function SingleMapScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
    self:ensureDepthSelection()
  end
  self:updateActionButtonLabel()
end

function SingleMapScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local node = SingleRunManager.getCurrentNode(self._runState)
  local nodeIndex = SingleRunManager.getCurrentDepth(self._runState)
  local nodeCount = math.max(1, SingleRunManager.getNodeCount(self._runState))
  local nodeTitle = resolveNodeTitle(node)

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.map.title"), 0, 90, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.map.node_line", {
    nodeIndex = tostring(nodeIndex),
    nodeCount = tostring(math.max(1, nodeCount)),
    nodeTitle = nodeTitle
  }), 0, 150, Constants.BASE_WORLD_W, "center")

  love.graphics.printf(t("single.map.gold_line", {
    gold = tostring(math.max(0, math.floor(tonumber(self._runState and self._runState.gold) or 0)))
  }), 0, 178, Constants.BASE_WORLD_W, "center")

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(nodeTitle, 0, 208, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  local selectedDedupKey = getChoiceDedupKey(node)
  for index, choiceButton in ipairs(self._choiceButtonList) do
    local choiceNode = self._choiceNodeList[index]
    choiceButton.isPressed = (choiceNode and getChoiceDedupKey(choiceNode) == selectedDedupKey) or false
    choiceButton:draw(mouseX, mouseY)
  end
  self._battleButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleMapScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  for _, choiceButton in ipairs(self._choiceButtonList) do
    if choiceButton:isHovered(mouseX, mouseY) then
      choiceButton:onClick()
      return
    end
  end
  if self._battleButton:isHovered(mouseX, mouseY) then
    self._battleButton:onClick()
  end
end

function SingleMapScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end
end

function SingleMapScene:onAppEvent(_event)
end

return SingleMapScene
