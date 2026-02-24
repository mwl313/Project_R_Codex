--[[
파일명: single_combat_scene.lua
모듈명: SingleCombatScene

역할:
- SP-02 싱글 실전 전투 씬.
- SingleCombatCore(오프라인 전투 코어)를 래핑해 런 플로우와 연결한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local BackButton = require("ui.back_button")
local SingleRunManager = require("single.single_run_manager")
local SingleCombatCore = require("single.single_combat_core")
local SingleRunState = require("single.single_run_state")
local SingleEconomy = require("single.single_economy")

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
    _nodeType = "mob",
    _nodeId = "",
    _stageIndex = 1,
    _lastLanguage = app:getLanguage(),
    _backButton = nil,
    _core = nil
  }
  setmetatable(instance, SingleCombatScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleCombatScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, {
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_BACK)
  end)
end

function SingleCombatScene:finishCombat(result)
  local normalized = (result == "lose") and "lose" or "win"
  SingleRunManager.setCombatResult(self._runState, normalized)
  if normalized ~= "win" then
    self._app:goScene("single_result", {
      profile = self._profile,
      runState = self._runState,
      result = "lose"
    }, Config.TRANSITION_FORWARD)
    return
  end

  local goldAmount = SingleEconomy.rollCombatGold(self._nodeType)
  SingleRunState.addGold(self._runState, goldAmount)

  self._app:goScene("single_reward", {
    profile = self._profile,
    runState = self._runState,
    nodeType = self._nodeType,
    stageIndex = self._stageIndex,
    isBoss = self._nodeType == "boss"
  }, Config.TRANSITION_FORWARD)
end

function SingleCombatScene:enter(params)
  self._backScene = (params and params.backScene) or "single_map"
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil
  self._nodeType = tostring((params and params.nodeType) or "mob")
  self._nodeId = tostring((params and params.nodeId) or "")
  self._stageIndex = math.max(1, math.floor(tonumber(params and params.stageIndex) or 1))
  SingleRunState.ensureDefaults(self._runState, self._profile)
  self:rebuildLocalizedUi()
  self._core = SingleCombatCore.new({
    app = self._app,
    profile = self._profile,
    runState = self._runState,
    nodeType = self._nodeType,
    nodeId = self._nodeId,
    stageIndex = self._stageIndex,
    onCombatEnd = function(result)
      self:finishCombat(result)
    end
  })
end

function SingleCombatScene:update(dt)
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  if self._core then
    self._core:update(dt, mouseX, mouseY)
  end
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleCombatScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  if self._core then
    self._core:draw(mouseX, mouseY)
  end

  self._backButton:draw(mouseX, mouseY)
end

function SingleCombatScene:mousepressed(mouseX, mouseY, button)
  if self._core then
    self._core:mousepressed(mouseX, mouseY, button)
  end
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
  end
end

function SingleCombatScene:mousereleased(mouseX, mouseY, button)
  if self._core then
    self._core:mousereleased(mouseX, mouseY, button)
  end
end

function SingleCombatScene:mousemoved(mouseX, mouseY, dx, dy)
  if self._core then
    self._core:mousemoved(mouseX, mouseY, dx, dy)
  end
end

function SingleCombatScene:wheelmoved(mouseX, mouseY, dx, dy)
  if self._core then
    self._core:wheelmoved(mouseX, mouseY, dx, dy)
  end
end

function SingleCombatScene:keypressed(key)
  if self._core and self._core:keypressed(key) then
    return
  end
  if key == "escape" then
    self._app:goScene(self._backScene, {
      profile = self._profile,
      runState = self._runState
    }, Config.TRANSITION_BACK)
  end
end

function SingleCombatScene:onAppEvent(_event)
  if self._core then
    self._core:onAppEvent(_event)
  end
end

function SingleCombatScene:onSceneWillChange(event)
  if self._core then
    self._core:onSceneWillChange(event)
  end
end

function SingleCombatScene:exit()
  if self._core then
    self._core:exit()
  end
end

return SingleCombatScene
