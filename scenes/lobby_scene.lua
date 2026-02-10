--[[
파일명: lobby_scene.lua
모듈명: LobbyScene

역할:
- 로비 메뉴 표시 및 입력 처리
- 방 생성/방 찾기 진입
- 닉네임/환경설정 오버레이 처리

외부에서 사용 가능한 함수:
- LobbyScene.new(app)

주의:
- 오버레이는 씬 전환이 아닌 팝업으로 처리한다
]]

local Constants = require("constants")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local Dropdown = require("ui.dropdown")
local TextInput = require("ui.text_input")

local LobbyScene = {}
LobbyScene.__index = LobbyScene

local function getDisplayModeLabel(displayMode)
  if displayMode == Constants.DISPLAY_MODE_FULLSCREEN then
    return "전체화면(현재 모니터 해상도)"
  end
  return "창모드(1280x720 고정)"
end

local function createMenuList(scene)
  local menuLabelList = {
    "싱글플레이어",
    "방 생성",
    "방 찾기",
    "닉네임 변경",
    "환경설정",
    "가이드",
    "스킨",
    "크레딧",
    "게임 종료"
  }

  local buttonList = {}
  local startX = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5
  local startY = 150

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
  local instance = {
    _app = app,
    _buttonList = {},
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _overlay = nil
  }
  setmetatable(instance, LobbyScene)
  instance._buttonList = createMenuList(instance)
  return instance
end

function LobbyScene:enter(params)
  self._statusText = params and params.statusText or ""
  self._statusColor = params and params.statusColor or Constants.COLOR_TEXT_SUB
end

function LobbyScene:getOverlayRect()
  local panelW = Constants.BASE_WORLD_W * Constants.OVERLAY_PANEL_RATIO
  local panelH = Constants.BASE_WORLD_H * Constants.OVERLAY_PANEL_RATIO
  local panelX = (Constants.BASE_WORLD_W - panelW) * 0.5
  local panelY = (Constants.BASE_WORLD_H - panelH) * 0.5
  return panelX, panelY, panelW, panelH
end

function LobbyScene:openNicknameOverlay()
  local panelX, panelY, panelW, panelH = self:getOverlayRect()
  local nicknameInput = TextInput.new({
    x = panelX + 120,
    y = panelY + 220,
    w = panelW - 240,
    h = 44,
    placeholder = "닉네임 입력",
    text = self._app:getNickname(),
    onEnter = function()
      self:applyNicknameOverlay()
    end
  })
  nicknameInput:setFocus(true)

  self._overlay = {
    kind = "nickname",
    panelX = panelX,
    panelY = panelY,
    panelW = panelW,
    panelH = panelH,
    nicknameInput = nicknameInput,
    saveButton = Button.new({
      x = panelX + panelW * 0.5 - 180,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = "저장",
      onClick = function()
        self:applyNicknameOverlay()
      end
    }),
    cancelButton = Button.new({
      x = panelX + panelW * 0.5 + 20,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = "취소",
      onClick = function()
        self:closeOverlay()
      end
    })
  }
end

function LobbyScene:openSettingsOverlay()
  local panelX, panelY, panelW, panelH = self:getOverlayRect()
  local selectedDisplayMode = self._app:getDisplayMode()

  self._overlay = {
    kind = "settings",
    panelX = panelX,
    panelY = panelY,
    panelW = panelW,
    panelH = panelH,
    selectedDisplayMode = selectedDisplayMode,
    displayModeDropdown = Dropdown.new({
      x = panelX + 100,
      y = panelY + 205,
      w = panelW - 200,
      h = 48,
      selectedValue = selectedDisplayMode,
      optionList = {
        {
          value = Constants.DISPLAY_MODE_WINDOWED,
          label = "창모드 (1280x720)"
        },
        {
          value = Constants.DISPLAY_MODE_FULLSCREEN,
          label = "전체화면 (현재 모니터)"
        }
      },
      onChanged = function(value)
        self._overlay.selectedDisplayMode = value
      end
    }),
    saveButton = Button.new({
      x = panelX + panelW * 0.5 - 180,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = "저장",
      onClick = function()
        self:applySettingsOverlay()
      end
    }),
    cancelButton = Button.new({
      x = panelX + panelW * 0.5 + 20,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = "취소",
      onClick = function()
        self:closeOverlay()
      end
    })
  }
end

function LobbyScene:closeOverlay()
  self._overlay = nil
end

function LobbyScene:applyNicknameOverlay()
  if not self._overlay or self._overlay.kind ~= "nickname" then
    return
  end

  local nickname = self._overlay.nicknameInput:getText():gsub("^%s+", ""):gsub("%s+$", "")
  if nickname == "" then
    self:setStatus("닉네임은 비어 있을 수 없습니다.", Constants.COLOR_DANGER)
    return
  end

  local isSaved, errorText = self._app:savePersistentSettings({
    nickname = nickname
  })
  if not isSaved then
    self:setStatus(errorText, Constants.COLOR_DANGER)
    return
  end

  self:setStatus("닉네임 저장됨: " .. nickname, Constants.COLOR_TEXT_SUB)
  self:closeOverlay()
end

function LobbyScene:applySettingsOverlay()
  if not self._overlay or self._overlay.kind ~= "settings" then
    return
  end

  local selectedDisplayMode = self._overlay.displayModeDropdown:getSelectedValue()
  local isSaved, warningText = self._app:savePersistentSettings({
    displayMode = selectedDisplayMode
  })
  if not isSaved then
    self:setStatus(warningText, Constants.COLOR_DANGER)
    return
  end

  local savedDisplayMode = self._app:getDisplayMode()
  local statusText = "환경설정 저장됨: " .. getDisplayModeLabel(savedDisplayMode)
  if warningText then
    statusText = statusText .. " / " .. warningText
  end
  self:setStatus(statusText, Constants.COLOR_TEXT_SUB)
  self:closeOverlay()
end

function LobbyScene:handleMenuClick(label)
  if label == "싱글플레이어" then
    self._app:goSingleDummy()
    self:setStatus("싱글 더미 테스트 모드로 진입합니다.", Constants.COLOR_TEXT_SUB)
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
    self:openNicknameOverlay()
    self:setStatus("닉네임 오버레이를 열었습니다.", Constants.COLOR_TEXT_SUB)
    return
  end
  if label == "환경설정" then
    self:openSettingsOverlay()
    self:setStatus("환경설정 오버레이를 열었습니다.", Constants.COLOR_TEXT_SUB)
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

function LobbyScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function LobbyScene:update(_dt)
end

function LobbyScene:drawOverlay(mouseX, mouseY)
  if not self._overlay then
    return
  end

  love.graphics.setColor(Constants.COLOR_OVERLAY_DIM)
  love.graphics.rectangle("fill", 0, 0, Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)

  love.graphics.setColor(Constants.COLOR_PANEL)
  love.graphics.rectangle("fill", self._overlay.panelX, self._overlay.panelY, self._overlay.panelW, self._overlay.panelH, 10, 10)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER)
  love.graphics.rectangle("line", self._overlay.panelX, self._overlay.panelY, self._overlay.panelW, self._overlay.panelH, 10, 10)

  if self._overlay.kind == "nickname" then
    love.graphics.setFont(FontManager.getFont("title"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf("닉네임 변경", self._overlay.panelX, self._overlay.panelY + 70, self._overlay.panelW, "center")

    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf("새 닉네임을 입력하고 저장하세요.", self._overlay.panelX, self._overlay.panelY + 150, self._overlay.panelW, "center")

    self._overlay.nicknameInput:draw()
    self._overlay.saveButton:draw(mouseX, mouseY)
    self._overlay.cancelButton:draw(mouseX, mouseY)
    return
  end

  if self._overlay.kind == "settings" then
    love.graphics.setFont(FontManager.getFont("title"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf("환경설정", self._overlay.panelX, self._overlay.panelY + 60, self._overlay.panelW, "center")

    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf("디스플레이 모드", self._overlay.panelX, self._overlay.panelY + 130, self._overlay.panelW, "center")

    self._overlay.displayModeDropdown:draw(mouseX, mouseY)

    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(
      "저장 경로: " .. self._app:getSettingsDebugPath(),
      self._overlay.panelX + 40,
      self._overlay.panelY + self._overlay.panelH - 130,
      self._overlay.panelW - 80,
      "center"
    )

    self._overlay.saveButton:draw(mouseX, mouseY)
    self._overlay.cancelButton:draw(mouseX, mouseY)
  end
end

function LobbyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf("ProjectR Lobby", 0, 62, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf("현재 닉네임: " .. self._app:getNickname(), 0, 106, Constants.BASE_WORLD_W, "center")

  for _, button in ipairs(self._buttonList) do
    button:draw(mouseX, mouseY)
  end

  self:drawOverlay(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function LobbyScene:handleOverlayMousePressed(mouseX, mouseY, button)
  if not self._overlay then
    return false
  end

  if self._overlay.kind == "nickname" then
    if self._overlay.nicknameInput:mousepressed(mouseX, mouseY, button) then
      return true
    end
    if self._overlay.saveButton:isHovered(mouseX, mouseY) then
      self._overlay.saveButton:onClick()
      return true
    end
    if self._overlay.cancelButton:isHovered(mouseX, mouseY) then
      self._overlay.cancelButton:onClick()
      return true
    end
    self._overlay.nicknameInput:setFocus(false)
    return true
  end

  if self._overlay.kind == "settings" then
    if self._overlay.displayModeDropdown:mousepressed(mouseX, mouseY, button) then
      self._overlay.selectedDisplayMode = self._overlay.displayModeDropdown:getSelectedValue()
      return true
    end
    if self._overlay.saveButton:isHovered(mouseX, mouseY) then
      self._overlay.saveButton:onClick()
      return true
    end
    if self._overlay.cancelButton:isHovered(mouseX, mouseY) then
      self._overlay.cancelButton:onClick()
      return true
    end
    return true
  end

  return true
end

function LobbyScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._overlay and self:handleOverlayMousePressed(mouseX, mouseY, button) then
    return
  end

  for _, uiButton in ipairs(self._buttonList) do
    if uiButton:isHovered(mouseX, mouseY) then
      uiButton:onClick()
      return
    end
  end
end

function LobbyScene:textinput(text)
  if self._overlay and self._overlay.kind == "nickname" then
    self._overlay.nicknameInput:textinput(text)
  end
end

function LobbyScene:textedited(text, start, length)
  if self._overlay and self._overlay.kind == "nickname" then
    self._overlay.nicknameInput:textedited(text, start, length)
  end
end

function LobbyScene:keypressed(key)
  if self._overlay then
    if key == "escape" then
      self:closeOverlay()
      return
    end

    if self._overlay.kind == "nickname" and self._overlay.nicknameInput:keypressed(key) then
      return
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
