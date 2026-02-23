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
    _battleButton = nil
  }
  setmetatable(instance, SingleMapScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleMapScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
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

  self._app:goScene("single_combat", {
    backScene = "single_map",
    profile = self._profile,
    runState = self._runState,
    nodeType = currentNode.type,
    nodeId = currentNode.nodeId,
    stageIndex = currentNode.stageIndex
  }, Config.TRANSITION_FORWARD)
end

function SingleMapScene:enter(params)
  self._backScene = (params and params.backScene) or "single_campaign"
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil

  if type(self._runState) ~= "table" then
    self._runState = SingleRunManager.newRun("default")
  end

  local deck = getDefaultDeck(self._profile)
  if deck then
    local valid = SingleDeckManager.validateDeck(deck, self._profile.collection)
    if not valid then
      self:setStatus(t("single.map.status.deck_invalid"), Constants.COLOR_DANGER)
    else
      self:setStatus(t("single.map.status.ready"), Constants.COLOR_TEXT_SUB)
    end
  else
    self:setStatus(t("single.map.status.deck_missing"), Constants.COLOR_DANGER)
  end

  self:rebuildLocalizedUi()
end

function SingleMapScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleMapScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local node = SingleRunManager.getCurrentNode(self._runState)
  local nodeIndex = self._runState and self._runState.currentNodeIndex or 1
  local nodeCount = (self._runState and type(self._runState.nodes) == "table") and #self._runState.nodes or 0

  local nodeTitle = t("single.map.node_default")
  if node then
    if type(node.titleKey) == "string" and node.titleKey ~= "" then
      local translated = t(node.titleKey)
      if type(translated) == "string" and not translated:find("^%[%[missing:") then
        nodeTitle = translated
      elseif type(node.fallbackTitleKo) == "string" and node.fallbackTitleKo ~= "" then
        nodeTitle = node.fallbackTitleKo
      elseif type(node.titleKo) == "string" and node.titleKo ~= "" then
        nodeTitle = node.titleKo
      end
    elseif type(node.titleKo) == "string" and node.titleKo ~= "" then
      nodeTitle = node.titleKo
    elseif type(node.nodeId) == "string" and node.nodeId ~= "" then
      nodeTitle = node.nodeId
    end
    if type(node.nodeIndex) == "number" then
      nodeIndex = node.nodeIndex
    end
  end

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

  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(nodeTitle, 0, 196, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
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
