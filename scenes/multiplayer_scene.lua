--[[
파일명: multiplayer_scene.lua
모듈명: MultiplayerScene

역할:
- 멀티플레이어 메뉴 씬.
- 방 생성/방 찾기 분기를 제공한다.

외부에서 사용 가능한 함수:
- MultiplayerScene.new(app)
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")

local MultiplayerScene = {}
MultiplayerScene.__index = MultiplayerScene

local function t(key, vars)
  return I18n.t(key, vars)
end

function MultiplayerScene.new(app)
  local instance = {
    _app = app,
    _backScene = "play",
    _backButton = nil,
    _createButton = nil,
    _searchButton = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, MultiplayerScene)
  instance:rebuildLocalizedUi()
  return instance
end

function MultiplayerScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene)
  end)

  self._createButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280,
    label = t("multiplayer.menu.create_room"),
    onClick = function()
      self._app:createRoom()
      self._statusText = t("multiplayer.status.creating_room")
      self._statusColor = Constants.COLOR_TEXT_SUB
    end
  })

  self._searchButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 280 + Constants.BUTTON_H + Constants.BUTTON_GAP,
    label = t("multiplayer.menu.search_room"),
    onClick = function()
      self._app:goRoomSearch({
        backScene = "multiplayer"
      })
    end
  })
end

function MultiplayerScene:enter(params)
  self._backScene = (params and params.backScene) or "play"
  self._statusText = (params and params.statusText) or ""
  self._statusColor = (params and params.statusColor) or Constants.COLOR_TEXT_SUB
  self:rebuildLocalizedUi()
end

function MultiplayerScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function MultiplayerScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("multiplayer.title"), 0, 120, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("multiplayer.subtitle"), 0, 172, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._createButton:draw(mouseX, mouseY)
  self._searchButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function MultiplayerScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._createButton:isHovered(mouseX, mouseY) then
    self._createButton:onClick()
    return
  end
  if self._searchButton:isHovered(mouseX, mouseY) then
    self._searchButton:onClick()
  end
end

function MultiplayerScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene)
  end
end

function MultiplayerScene:onAppEvent(event)
  if event.type == "ui_status" then
    self._statusText = event.text or ""
    self._statusColor = event.color or Constants.COLOR_TEXT_SUB
  end
end

return MultiplayerScene

