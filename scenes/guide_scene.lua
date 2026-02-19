--[[
파일명: guide_scene.lua
모듈명: GuideScene

역할:
- 가이드 씬 Stub 화면.

외부에서 사용 가능한 함수:
- GuideScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local BackButton = require("ui.back_button")

local GuideScene = {}
GuideScene.__index = GuideScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function GuideScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, GuideScene)
  instance:rebuildLocalizedUi()
  return instance
end

function GuideScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)
end

function GuideScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()
end

function GuideScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function GuideScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("guide.title"), 0, 160, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("stub.message"), 0, 240, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
end

function GuideScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
  end
end

function GuideScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function GuideScene:onAppEvent(_event)
end

return GuideScene

