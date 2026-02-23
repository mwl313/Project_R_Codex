--[[
파일명: single_combat_scene.lua
모듈명: SingleCombatScene

역할:
- SP-01 전투 플레이스홀더 씬.
- 승리/패배 버튼으로 런 흐름을 테스트한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local SingleRunManager = require("single.single_run_manager")

local SingleCombatScene = {}
SingleCombatScene.__index = SingleCombatScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function SingleCombatScene.new(app)
  local instance = {
    _app = app,
    _backScene = "single_map",
    _profile = nil,
    _runState = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage(),
    _backButton = nil,
    _winButton = nil,
    _loseButton = nil
  }
  setmetatable(instance, SingleCombatScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleCombatScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleCombatScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, {
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_BACK)
  end)

  self._winButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 338,
    label = t("single.combat.button.win_test"),
    onClick = function()
      self:finishCombat("win")
    end
  })

  self._loseButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 338 + Constants.BUTTON_H + Constants.BUTTON_GAP,
    label = t("single.combat.button.lose_test"),
    onClick = function()
      self:finishCombat("lose")
    end
  })
end

function SingleCombatScene:finishCombat(result)
  SingleRunManager.setCombatResult(self._runState, result)
  if result == "lose" then
    self._app:goScene("single_result", {
      profile = self._profile,
      runState = self._runState,
      result = "lose"
    }, Config.TRANSITION_FORWARD)
    return
  end

  local node = SingleRunManager.getCurrentNode(self._runState)
  self._app:goScene("single_reward", {
    profile = self._profile,
    runState = self._runState,
    isBoss = node and node.type == "boss" or false
  }, Config.TRANSITION_FORWARD)
end

function SingleCombatScene:enter(params)
  self._backScene = (params and params.backScene) or "single_map"
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil
  self:rebuildLocalizedUi()
  self:setStatus(t("single.combat.status.placeholder"), Constants.COLOR_TEXT_SUB)
end

function SingleCombatScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleCombatScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.combat.title"), 0, 112, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.combat.subtitle"), 0, 164, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._winButton:draw(mouseX, mouseY)
  self._loseButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleCombatScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._winButton:isHovered(mouseX, mouseY) then
    self._winButton:onClick()
    return
  end
  if self._loseButton:isHovered(mouseX, mouseY) then
    self._loseButton:onClick()
  end
end

function SingleCombatScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, {
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_BACK)
  end
end

function SingleCombatScene:onAppEvent(_event)
end

return SingleCombatScene
