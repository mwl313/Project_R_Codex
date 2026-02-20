--[[
파일명: room_search_scene.lua
모듈명: RoomSearchScene

역할:
- 방 코드 입력 및 참가 요청 처리
- 이전 씬 복귀 처리(뒤로 버튼)

외부에서 사용 가능한 함수:
- RoomSearchScene.new(app)

주의:
- 룸 코드는 영문 대문자/숫자 16자리 기준으로 입력한다
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local TextInput = require("ui.text_input")

local RoomSearchScene = {}
RoomSearchScene.__index = RoomSearchScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function sanitizeRoomCode(value)
  local upper = string.upper(value or "")
  upper = upper:gsub("[^A-Z0-9]", "")
  if #upper > 16 then
    upper = upper:sub(1, 16)
  end
  return upper
end

function RoomSearchScene.new(app)
  local input = TextInput.new({
    x = 380,
    y = 280,
    w = 520,
    h = 48,
    placeholder = t("room_search.placeholder"),
    onEnter = function()
      -- Scene instance에서 처리
    end
  })

  local instance = {
    _app = app,
    _roomCodeInput = input,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _backScene = "multiplayer",
    _lastLanguage = app:getLanguage(),
    _pasteButton = nil,
    _joinButton = nil,
    _backButton = nil
  }
  setmetatable(instance, RoomSearchScene)

  instance._pasteButton = Button.new({
    x = 380,
    y = 340,
    w = 520,
    h = 48,
    label = t("room_search.button.paste_clipboard"),
    onClick = function()
      instance:pasteRoomCodeFromClipboard()
    end
  })

  instance._joinButton = Button.new({
    x = 380,
    y = 405,
    w = 520,
    h = 48,
    label = t("common.button.join"),
    onClick = function()
      instance:requestJoin()
    end
  })
  instance._backButton = BackButton.new(t("common.button.back"), function()
    instance._app:goScene(instance._backScene, nil, Config.TRANSITION_BACK)
  end)

  instance._roomCodeInput.onEnter = function()
    instance:requestJoin()
  end

  return instance
end

function RoomSearchScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._roomCodeInput.placeholder = t("room_search.placeholder")
  self._pasteButton.label = t("room_search.button.paste_clipboard")
  self._joinButton.label = t("common.button.join")
  self._backButton.label = t("common.button.back")
end

function RoomSearchScene:enter(params)
  self._backScene = (params and params.backScene) or "multiplayer"
  self._statusText = params and params.statusText or ""
  self._statusColor = params and params.statusColor or Constants.COLOR_TEXT_SUB
  self._roomCodeInput:setFocus(true)
  self:rebuildLocalizedUi()
end

function RoomSearchScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function RoomSearchScene:requestJoin()
  local roomCode = sanitizeRoomCode(self._roomCodeInput:getText())
  self._roomCodeInput:setText(roomCode)
  if #roomCode ~= 16 then
    self:setStatus(t("room_search.status.code_len_invalid"), Constants.COLOR_DANGER)
    return
  end
  self._app:joinRoom(roomCode)
  self:setStatus(t("room_search.status.joining"), Constants.COLOR_TEXT_SUB)
end

function RoomSearchScene:pasteRoomCodeFromClipboard()
  if not love.system or not love.system.getClipboardText then
    self:setStatus(t("room_search.status.clipboard_not_available"), Constants.COLOR_DANGER)
    return
  end

  local isOk, clipOrError = pcall(love.system.getClipboardText)
  if not isOk then
    self:setStatus(t("room_search.status.clipboard_read_failed", {
      error = clipOrError
    }), Constants.COLOR_DANGER)
    return
  end

  local clip = type(clipOrError) == "string" and clipOrError or ""
  clip = clip:gsub("\r\n", ""):gsub("\r", ""):gsub("\n", "")
  clip = sanitizeRoomCode(clip)
  if clip == "" then
    self:setStatus(t("room_search.status.clipboard_invalid_code"), Constants.COLOR_DANGER)
    return
  end

  self._roomCodeInput:setText(clip)
  self._roomCodeInput:setFocus(true)
  self:setStatus(t("room_search.status.clipboard_pasted"), Constants.COLOR_TEXT_SUB)
end

function RoomSearchScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function RoomSearchScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("room_search.title"), 0, 170, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("room_search.subtitle"), 0, 220, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  self._roomCodeInput:draw()
  self._pasteButton:draw(mouseX, mouseY)
  self._joinButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 500, Constants.BASE_WORLD_W, "center")
end

function RoomSearchScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end
  if self._roomCodeInput:mousepressed(mouseX, mouseY, button) then
    return
  end
  if self._pasteButton:isHovered(mouseX, mouseY) then
    self._pasteButton:onClick()
    return
  end
  if self._joinButton:isHovered(mouseX, mouseY) then
    self._joinButton:onClick()
    return
  end

  self._roomCodeInput:setFocus(false)
end

function RoomSearchScene:textinput(text)
  self._roomCodeInput:textinput(text)
  local sanitized = sanitizeRoomCode(self._roomCodeInput:getText())
  self._roomCodeInput:setText(sanitized)
end

function RoomSearchScene:textedited(text, start, length)
  self._roomCodeInput:textedited(text, start, length)
end

function RoomSearchScene:keypressed(key)
  if self._roomCodeInput:keypressed(key) then
    local sanitized = sanitizeRoomCode(self._roomCodeInput:getText())
    self._roomCodeInput:setText(sanitized)
    return
  end
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function RoomSearchScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
  end
end

return RoomSearchScene
