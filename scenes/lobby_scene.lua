--[[
파일명: lobby_scene.lua
모듈명: LobbyScene

역할:
- 로비 메뉴 표시 및 입력 처리
- 방 생성/방 찾기 진입

외부에서 사용 가능한 함수:
- LobbyScene.new(app)

주의:
- 미구현 메뉴는 안내 문구만 노출한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local TextInput = require("ui.text_input")

local LobbyScene = {}
LobbyScene.__index = LobbyScene

local function createMenuList(scene)
  local menuLabelList = {
    "싱글플레이어",
    "방 생성",
    "방 찾기",
    "닉네임 변경",
    "가이드",
    "스킨",
    "크레딧",
    "게임 종료"
  }

  local buttonList = {}
  local startX = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5
  local startY = 170

  for index, label in ipairs(menuLabelList) do
    local y = startY + (index - 1) * (Constants.BUTTON_H + Constants.BUTTON_GAP)
    buttonList[#buttonList + 1] = Button.new({
      x = startX,
      y = y,
      label = label,
      onClick = function()
        scene:handleMenuClick(label)
      end
    })
  end

  return buttonList
end

function LobbyScene.new(app)
  local nicknameInput = TextInput.new({
    x = 430,
    y = 120,
    w = 300,
    h = 38,
    placeholder = "닉네임 입력",
    text = app:getNickname()
  })

  local instance = {
    _app = app,
    _buttonList = {},
    _nicknameInput = nicknameInput,
    _applyNicknameButton = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB
  }
  setmetatable(instance, LobbyScene)
  instance._buttonList = createMenuList(instance)
  instance._applyNicknameButton = Button.new({
    x = 740,
    y = 120,
    w = 110,
    h = 38,
    label = "적용",
    onClick = function()
      instance:applyNickname()
    end
  })
  return instance
end

function LobbyScene:enter(params)
  self._statusText = params and params.statusText or ""
  self._statusColor = params and params.statusColor or Constants.COLOR_TEXT_SUB
  self._nicknameInput:setText(self._app:getNickname())
end

function LobbyScene:handleMenuClick(label)
  if label == "싱글플레이어" then
    self:setStatus("싱글플레이어는 후속 단계에서 구현됩니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "방 생성" then
    self._app:createRoom()
    self:setStatus("방 생성 요청 중...", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "방 찾기" then
    self._app:goRoomSearch()
    return
  end
  if label == "닉네임 변경" then
    self._nicknameInput:setFocus(true)
    self:setStatus("상단 입력창에서 닉네임을 수정하고 적용을 누르세요.", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "가이드" then
    self:setStatus("가이드는 Phase 3 이후에 확장됩니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "스킨" then
    self:setStatus("스킨 기능은 Phase 4 이후에 확장됩니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "크레딧" then
    self:setStatus("ProjectR MVP by Team + Codex", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "게임 종료" then
    love.event.quit()
  end
end

function LobbyScene:applyNickname()
  local nickname = self._nicknameInput:getText():gsub("^%s+", ""):gsub("%s+$", "")
  if nickname == "" then
    self:setStatus("닉네임은 비어 있을 수 없습니다.", Constants.COLOR_DANGER)
    return
  end
  self._app:setNickname(nickname)
  self:setStatus("닉네임 적용됨: " .. nickname, Constants.COLOR_TEXT_SUB)
end

function LobbyScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function LobbyScene:update(_dt)
end

function LobbyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("ProjectR Lobby", 0, 72, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("닉네임:", 350, 130, 80, "right")
  self._nicknameInput:draw()
  self._applyNicknameButton:draw(mouseX, mouseY)

  for _, button in ipairs(self._buttonList) do
    button:draw(mouseX, mouseY)
  end

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 650, Constants.BASE_WORLD_W, "center")
end

function LobbyScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._nicknameInput:mousepressed(mouseX, mouseY, button) then
    return
  end
  if self._applyNicknameButton:isHovered(mouseX, mouseY) then
    self._applyNicknameButton:onClick()
    return
  end
  for _, uiButton in ipairs(self._buttonList) do
    if uiButton:isHovered(mouseX, mouseY) then
      uiButton:onClick()
      return
    end
  end
  self._nicknameInput:setFocus(false)
end

function LobbyScene:textinput(text)
  self._nicknameInput:textinput(text)
end

function LobbyScene:textedited(text, start, length)
  self._nicknameInput:textedited(text, start, length)
end

function LobbyScene:keypressed(key)
  if self._nicknameInput:keypressed(key) then
    if key == "return" or key == "kpenter" then
      self:applyNickname()
    end
    return
  end
end

function LobbyScene:onAppEvent(event)
  if event.type == "ui_status" then
    self:setStatus(event.text, event.color)
  end
end

return LobbyScene
