--[[
파일명: room_search_scene.lua
모듈명: RoomSearchScene

역할:
- 방 코드 입력 및 참가 요청 처리
- 로비 복귀 처리

외부에서 사용 가능한 함수:
- RoomSearchScene.new(app)

주의:
- 룸 코드는 영문 대문자/숫자 16자리 기준으로 입력한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local TextInput = require("ui.text_input")

local RoomSearchScene = {}
RoomSearchScene.__index = RoomSearchScene

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
    placeholder = "16자리 룸 코드를 입력하세요",
    onEnter = function()
      -- Scene instance에서 처리
    end
  })

  local instance = {
    _app = app,
    _roomCodeInput = input,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _joinButton = nil,
    _backButton = nil
  }
  setmetatable(instance, RoomSearchScene)

  instance._joinButton = Button.new({
    x = 380,
    y = 350,
    w = 250,
    h = 48,
    label = "참가",
    onClick = function()
      instance:requestJoin()
    end
  })
  instance._backButton = Button.new({
    x = 650,
    y = 350,
    w = 250,
    h = 48,
    label = "로비로",
    onClick = function()
      instance._app:goLobby()
    end
  })

  instance._roomCodeInput.onEnter = function()
    instance:requestJoin()
  end

  return instance
end

function RoomSearchScene:enter(params)
  self._statusText = params and params.statusText or ""
  self._statusColor = params and params.statusColor or Constants.COLOR_TEXT_SUB
  self._roomCodeInput:setFocus(true)
end

function RoomSearchScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function RoomSearchScene:requestJoin()
  local roomCode = sanitizeRoomCode(self._roomCodeInput:getText())
  self._roomCodeInput:setText(roomCode)
  if #roomCode ~= 16 then
    self:setStatus("룸 코드는 16자리여야 합니다.", Constants.COLOR_DANGER)
    return
  end
  self._app:joinRoom(roomCode)
  self:setStatus("참가 요청 중...", Constants.COLOR_TEXT_SUB)
end

function RoomSearchScene:update(_dt)
end

function RoomSearchScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("방 찾기", 0, 170, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("로컬 서버 기준 룸 코드를 입력하세요", 0, 220, Constants.BASE_WORLD_W, "center")

  self._roomCodeInput:draw()
  self._joinButton:draw(mouseX, mouseY)
  self._backButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 430, Constants.BASE_WORLD_W, "center")
end

function RoomSearchScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._roomCodeInput:mousepressed(mouseX, mouseY, button) then
    return
  end
  if self._joinButton:isHovered(mouseX, mouseY) then
    self._joinButton:onClick()
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
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
    self._app:goLobby()
  end
end

function RoomSearchScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
  end
end

return RoomSearchScene
