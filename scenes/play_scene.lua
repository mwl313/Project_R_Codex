--[[
파일명: play_scene.lua
모듈명: PlayScene

역할:
- 플레이 모드 선택 씬.
- 싱글플레이어/멀티플레이어 진입 분기 제공.

외부에서 사용 가능한 함수:
- PlayScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")

local PlayScene = {}
PlayScene.__index = PlayScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function PlayScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _singleButton = nil,
    _multiButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, PlayScene)
  instance:rebuildLocalizedUi()
  return instance
end

function PlayScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)

  self._singleButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280,
    label = t("play.menu.single_player"),
    onClick = function()
      self._app:goSingleDummy({
        backScene = "play"
      }, Config.TRANSITION_FORWARD)
    end
  })

  self._multiButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280 + Constants.BUTTON_H + Constants.BUTTON_GAP,
    label = t("play.menu.multi_player"),
    onClick = function()
      self._app:goMultiplayer({
        backScene = "play"
      }, Config.TRANSITION_FORWARD)
    end
  })
end

function PlayScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()
end

function PlayScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function PlayScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("play.title"), 0, 120, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("play.subtitle"), 0, 172, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._singleButton:draw(mouseX, mouseY)
  self._multiButton:draw(mouseX, mouseY)
end

function PlayScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._singleButton:isHovered(mouseX, mouseY) then
    self._singleButton:onClick()
    return
  end
  if self._multiButton:isHovered(mouseX, mouseY) then
    self._multiButton:onClick()
  end
end

function PlayScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function PlayScene:onAppEvent(_event)
end

return PlayScene

