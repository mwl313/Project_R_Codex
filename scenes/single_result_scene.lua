--[[
파일명: single_result_scene.lua
모듈명: SingleResultScene

역할:
- 싱글 런 결과를 표시하고 다음 씬으로 진행한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")

local SingleResultScene = {}
SingleResultScene.__index = SingleResultScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function SingleResultScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _result = "lose",
    _nextSceneName = "single_campaign",
    _nextSceneParams = nil,
    _proceedButton = nil,
    _backButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SingleResultScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleResultScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene("single_campaign", {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end)

  self._proceedButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 448,
    label = t("single.result.button.proceed"),
    onClick = function()
      self._app:goScene(self._nextSceneName, self._nextSceneParams, Config.TRANSITION_FORWARD)
    end
  })
end

function SingleResultScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or nil
  self._result = params and tostring(params.result or "lose") or "lose"

  if self._result == "win" then
    if params and params.nextSceneName then
      self._nextSceneName = params.nextSceneName
      self._nextSceneParams = params.nextSceneParams
    elseif type(self._runState) == "table" and self._runState.finished ~= true then
      self._nextSceneName = "single_map"
      self._nextSceneParams = {
        backScene = "single_campaign",
        profile = self._profile,
        runState = self._runState
      }
    else
      self._nextSceneName = "single_campaign"
      self._nextSceneParams = {
        profile = self._profile
      }
    end
  else
    self._nextSceneName = "single_campaign"
    self._nextSceneParams = {
      profile = self._profile
    }
  end

  self:rebuildLocalizedUi()
end

function SingleResultScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SingleResultScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  local titleKey = self._result == "win" and "single.result.title_win" or "single.result.title_lose"
  local subtitleKey = self._result == "win" and "single.result.subtitle_win" or "single.result.subtitle_lose"

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.result.title"), 0, 138, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(self._result == "win" and Constants.COLOR_BUTTON_SELECTED or Constants.COLOR_DANGER)
  love.graphics.printf(t(titleKey), 0, 206, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t(subtitleKey), 0, 266, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._proceedButton:draw(mouseX, mouseY)
end

function SingleResultScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._proceedButton:isHovered(mouseX, mouseY) then
    self._proceedButton:onClick()
  end
end

function SingleResultScene:keypressed(key)
  if key == "escape" then
    self._app:goScene("single_campaign", {
      profile = self._profile
    }, Config.TRANSITION_BACK)
  end
end

function SingleResultScene:onAppEvent(_event)
end

return SingleResultScene
