--[[
파일명: skin_scene.lua
모듈명: SkinScene

역할:
- 스킨 씬 Stub 화면.

외부에서 사용 가능한 함수:
- SkinScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local BackButton = require("ui.back_button")

local SkinScene = {}
SkinScene.__index = SkinScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function SkinScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, SkinScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SkinScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)
end

function SkinScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()
end

function SkinScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function SkinScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("skin.title"), 0, 160, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("stub.message"), 0, 240, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
end

function SkinScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
  end
end

function SkinScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function SkinScene:onAppEvent(_event)
end

return SkinScene

