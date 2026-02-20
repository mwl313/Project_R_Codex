--[[
파일명: scene_manager.lua
모듈명: SceneManager

역할:
- 현재 씬 교체 및 이벤트 위임
- 씬 생명주기(enter/exit) 관리

외부에서 사용 가능한 함수:
- SceneManager.new(sceneFactoryTable, app)
- SceneManager:change(sceneName, params, transitionDirection, transitionOpts)
- SceneManager:setScene(sceneName, params, transitionDirection, transitionOpts)
- SceneManager:getCurrentScene()
- SceneManager:isTransitioning()
- SceneManager:update(dt)
- SceneManager:draw()
- SceneManager:dispatch(functionName, ...)

주의:
- 씬 이름은 sceneFactoryTable 키와 일치해야 한다
]]

local SceneManager = {}
SceneManager.__index = SceneManager
local TransitionManager = require("managers.transition_manager")

local INPUT_EVENT_NAME_SET = {
  mousepressed = true,
  mousereleased = true,
  mousemoved = true,
  wheelmoved = true,
  keypressed = true,
  textinput = true,
  textedited = true
}

function SceneManager.new(sceneFactoryTable, app)
  local instance = {
    _sceneFactoryTable = sceneFactoryTable or {},
    _app = app,
    _currentScene = nil,
    _currentSceneName = nil,
    _transitionManager = TransitionManager.new(),
    _pendingScene = nil,
    _pendingSceneName = nil
  }
  return setmetatable(instance, SceneManager)
end

local function createScene(sceneManager, sceneName)
  local sceneFactory = sceneManager._sceneFactoryTable[sceneName]
  if not sceneFactory then
    error("Unknown scene: " .. tostring(sceneName))
  end
  return sceneFactory(sceneManager._app)
end

local function exitScene(scene)
  if scene and scene.exit then
    scene:exit()
  end
end

local function enterScene(scene, params)
  if scene and scene.enter then
    scene:enter(params)
  end
end

function SceneManager:change(sceneName, params, transitionDirection, transitionOpts)
  if self._transitionManager:isActive() then
    local settledScene = self._pendingScene or self._currentScene
    local settledSceneName = self._pendingSceneName or self._currentSceneName
    if settledScene ~= self._currentScene then
      exitScene(self._currentScene)
    end
    self._currentScene = settledScene
    self._currentSceneName = settledSceneName
    self._pendingScene = nil
    self._pendingSceneName = nil
    self._transitionManager:clear()
  end

  if not self._currentScene or not transitionDirection then
    self._transitionManager:clear()
    exitScene(self._currentScene)

    local nextScene = createScene(self, sceneName)
    self._currentScene = nextScene
    self._currentSceneName = sceneName
    self._pendingScene = nil
    self._pendingSceneName = nil
    enterScene(self._currentScene, params)
    return
  end

  local nextScene = createScene(self, sceneName)
  enterScene(nextScene, params)

  self._pendingScene = nextScene
  self._pendingSceneName = sceneName
  local isStarted = self._transitionManager:start(self._currentScene, nextScene, transitionDirection, transitionOpts)
  if not isStarted then
    exitScene(self._currentScene)
    self._currentScene = self._pendingScene
    self._currentSceneName = self._pendingSceneName
    self._pendingScene = nil
    self._pendingSceneName = nil
  end
end

-- 하위 호환: 기존 호출부(setScene)를 유지한다.
function SceneManager:setScene(sceneName, params, transitionDirection, transitionOpts)
  self:change(sceneName, params, transitionDirection, transitionOpts)
end

function SceneManager:isTransitioning()
  return self._transitionManager:isActive()
end

function SceneManager:completeTransitionIfNeeded()
  if not self._pendingScene then
    return
  end

  local fromScene = self._currentScene
  self._currentScene = self._pendingScene
  self._currentSceneName = self._pendingSceneName
  self._pendingScene = nil
  self._pendingSceneName = nil

  exitScene(fromScene)
end

function SceneManager:getCurrentScene()
  return self._currentScene
end

function SceneManager:getCurrentSceneName()
  return self._currentSceneName
end

function SceneManager:update(dt)
  if self._transitionManager:isActive() then
    self._transitionManager:update(dt)
    return
  end

  if self._currentScene and self._currentScene.update then
    self._currentScene:update(dt)
  end
end

function SceneManager:draw()
  if self._transitionManager:isActive() then
    self._transitionManager:draw()
    if self._transitionManager:isDone() then
      self:completeTransitionIfNeeded()
      self._transitionManager:clear()
    end
    return
  end

  if self._currentScene and self._currentScene.draw then
    self._currentScene:draw()
  end
end

function SceneManager:dispatch(functionName, ...)
  if not self._currentScene then
    return
  end

  local targetScene = self._currentScene
  if self._transitionManager:isActive() and INPUT_EVENT_NAME_SET[functionName] and self._pendingScene then
    targetScene = self._pendingScene
  end

  local sceneFunction = targetScene[functionName]
  if (not sceneFunction) and targetScene ~= self._currentScene then
    targetScene = self._currentScene
    sceneFunction = targetScene[functionName]
  end

  if sceneFunction then
    sceneFunction(targetScene, ...)
  end
end

return SceneManager
