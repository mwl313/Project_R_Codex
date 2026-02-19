--[[
파일명: credits_scene.lua
모듈명: CreditsScene

역할:
- 크레딧 씬 Stub 화면.

외부에서 사용 가능한 함수:
- CreditsScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local BackButton = require("ui.back_button")

local CreditsScene = {}
CreditsScene.__index = CreditsScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function CreditsScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, CreditsScene)
  instance:rebuildLocalizedUi()
  return instance
end

function CreditsScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)
end

function CreditsScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()
end

function CreditsScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function CreditsScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("credits.title"), 0, 160, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("stub.message"), 0, 240, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
end

function CreditsScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
  end
end

function CreditsScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function CreditsScene:onAppEvent(_event)
end

return CreditsScene

