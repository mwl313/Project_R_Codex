--[[
파일명: lobby_scene.lua
모듈명: LobbyScene

역할:
- 로비 메뉴 표시 및 입력 처리
- 플레이/가이드/스킨/크레딧 메뉴 진입
- 닉네임/환경설정 오버레이 처리

외부에서 사용 가능한 함수:
- LobbyScene.new(app)

주의:
- 오버레이는 씬 전환이 아닌 팝업으로 처리한다
]]

local Constants = require("constants")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local Dropdown = require("ui.dropdown")
local TextInput = require("ui.text_input")

local LobbyScene = {}
LobbyScene.__index = LobbyScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function getDisplayModeLabel(displayMode)
  if displayMode == Constants.DISPLAY_MODE_FULLSCREEN then
    return t("lobby.display_mode.fullscreen")
  end
  return t("lobby.display_mode.windowed")
end

local function getLanguageLabel(languageCode)
  if languageCode == "en" then
    return t("lobby.language.option_en")
  end
  if languageCode == "ko" then
    return t("lobby.language.option_ko")
  end
  return tostring(languageCode or "")
end

local function createMenuList(scene)
  local menuEntryList = {
    { id = "play", label = t("lobby.menu.play") },
    { id = "change_nickname", label = t("lobby.menu.change_nickname") },
    { id = "settings", label = t("lobby.menu.settings") },
    { id = "guide", label = t("lobby.menu.guide") },
    { id = "skin", label = t("lobby.menu.skin") },
    { id = "credits", label = t("lobby.menu.credits") },
    { id = "quit", label = t("lobby.menu.quit") }
  }

  local buttonList = {}
  local startX = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5
  local startY = 150

  for index, entry in ipairs(menuEntryList) do
    local y = startY + (index - 1) * (Constants.BUTTON_H + Constants.BUTTON_GAP)
    buttonList[#buttonList + 1] = Button.new({
      x = startX,
      y = y,
      label = entry.label,
      onClick = function()
        scene:handleMenuClick(entry.id)
      end
    })
  end

  return buttonList
end

local function createDisplayModeOptionList()
  return {
    {
      value = Constants.DISPLAY_MODE_WINDOWED,
      label = t("lobby.display_mode.option_windowed")
    },
    {
      value = Constants.DISPLAY_MODE_FULLSCREEN,
      label = t("lobby.display_mode.option_fullscreen")
    }
  }
end

local function createLanguageOptionList()
  return {
    {
      value = "ko",
      label = t("lobby.language.option_ko")
    },
    {
      value = "en",
      label = t("lobby.language.option_en")
    }
  }
end

local function getSettingsDropdownList(overlay)
  return {
    overlay.displayModeDropdown,
    overlay.languageDropdown
  }
end

function LobbyScene.new(app)
  local instance = {
    _app = app,
    _buttonList = {},
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _overlay = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, LobbyScene)
  instance:rebuildLocalizedUi()
  return instance
end

function LobbyScene:enter(params)
  self:rebuildLocalizedUi()
  self._statusText = params and params.statusText or ""
  self._statusColor = params and params.statusColor or Constants.COLOR_TEXT_SUB
end

function LobbyScene:rebuildLocalizedUi()
  self._buttonList = createMenuList(self)
  self._lastLanguage = self._app:getLanguage()

  if not self._overlay then
    return
  end

  if self._overlay.kind == "nickname" then
    self._overlay.nicknameInput.placeholder = t("lobby.overlay.nickname.placeholder")
    self._overlay.saveButton.label = t("common.button.save")
    self._overlay.cancelButton.label = t("common.button.cancel")
    return
  end

  if self._overlay.kind == "settings" then
    self._overlay.displayModeDropdown.optionList = createDisplayModeOptionList()
    self._overlay.languageDropdown.optionList = createLanguageOptionList()
    self._overlay.saveButton.label = t("common.button.save")
    self._overlay.cancelButton.label = t("common.button.cancel")
  end
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
    placeholder = t("lobby.overlay.nickname.placeholder"),
    text = self._app:getNickname(),
    maxChars = Constants.NICKNAME_MAX_LENGTH,
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
      label = t("common.button.save"),
      onClick = function()
        self:applyNicknameOverlay()
      end
    }),
    cancelButton = Button.new({
      x = panelX + panelW * 0.5 + 20,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = t("common.button.cancel"),
      onClick = function()
        self:closeOverlay()
      end
    })
  }
end

function LobbyScene:openSettingsOverlay()
  local panelX, panelY, panelW, panelH = self:getOverlayRect()
  local selectedDisplayMode = self._app:getDisplayMode()
  local selectedLanguage = self._app:getLanguage()
  local labelX = panelX + 110
  local controlX = panelX + 390
  local rowWidth = panelW - 500
  local firstRowY = panelY + 188
  local rowGap = 86

  self._overlay = {
    kind = "settings",
    panelX = panelX,
    panelY = panelY,
    panelW = panelW,
    panelH = panelH,
    selectedDisplayMode = selectedDisplayMode,
    selectedLanguage = selectedLanguage,
    labelX = labelX,
    controlX = controlX,
    rowWidth = rowWidth,
    displayModeRowY = firstRowY,
    languageRowY = firstRowY + rowGap,
    displayModeDropdown = Dropdown.new({
      x = controlX,
      y = firstRowY,
      w = rowWidth,
      h = 46,
      selectedValue = selectedDisplayMode,
      optionList = createDisplayModeOptionList(),
      onChanged = function(value)
        self._overlay.selectedDisplayMode = value
      end
    }),
    languageDropdown = Dropdown.new({
      x = controlX,
      y = firstRowY + rowGap,
      w = rowWidth,
      h = 46,
      selectedValue = selectedLanguage,
      optionList = createLanguageOptionList(),
      onChanged = function(value)
        self._overlay.selectedLanguage = value
      end
    }),
    saveButton = Button.new({
      x = panelX + panelW * 0.5 - 180,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = t("common.button.save"),
      onClick = function()
        self:applySettingsOverlay()
      end
    }),
    cancelButton = Button.new({
      x = panelX + panelW * 0.5 + 20,
      y = panelY + panelH - 90,
      w = 160,
      h = 46,
      label = t("common.button.cancel"),
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
    self:setStatus(t("lobby.status.nickname_empty"), Constants.COLOR_DANGER)
    return
  end

  local isSaved, errorText = self._app:savePersistentSettings({
    nickname = nickname
  })
  if not isSaved then
    self:setStatus(errorText, Constants.COLOR_DANGER)
    return
  end

  self:setStatus(t("lobby.status.nickname_saved", {
    nickname = nickname
  }), Constants.COLOR_TEXT_SUB)
  self:closeOverlay()
end

function LobbyScene:applySettingsOverlay()
  if not self._overlay or self._overlay.kind ~= "settings" then
    return
  end

  local selectedDisplayMode = self._overlay.displayModeDropdown:getSelectedValue()
  local selectedLanguage = self._overlay.languageDropdown:getSelectedValue()
  local isSaved, warningText = self._app:savePersistentSettings({
    displayMode = selectedDisplayMode,
    language = selectedLanguage
  })
  if not isSaved then
    self:setStatus(warningText, Constants.COLOR_DANGER)
    return
  end

  local savedDisplayMode = self._app:getDisplayMode()
  local savedLanguage = self._app:getLanguage()
  self:rebuildLocalizedUi()
  local statusText = t("lobby.status.settings_saved", {
    displayMode = getDisplayModeLabel(savedDisplayMode),
    language = getLanguageLabel(savedLanguage)
  })
  if warningText then
    statusText = t("lobby.status.settings_saved_with_warning", {
      displayMode = getDisplayModeLabel(savedDisplayMode),
      language = getLanguageLabel(savedLanguage),
      warning = warningText
    })
  end
  self:setStatus(statusText, Constants.COLOR_TEXT_SUB)
  self:closeOverlay()
end

function LobbyScene:handleMenuClick(menuId)
  if menuId == "play" then
    self._app:goPlay({
      backScene = "lobby"
    })
    return
  end
  if menuId == "change_nickname" then
    self:openNicknameOverlay()
    self:setStatus(t("lobby.status.opened_nickname_overlay"), Constants.COLOR_TEXT_SUB)
    return
  end
  if menuId == "settings" then
    self:openSettingsOverlay()
    self:setStatus(t("lobby.status.opened_settings_overlay"), Constants.COLOR_TEXT_SUB)
    return
  end
  if menuId == "guide" then
    self._app:goGuide({
      backScene = "lobby"
    })
    return
  end
  if menuId == "skin" then
    self._app:goSkin({
      backScene = "lobby"
    })
    return
  end
  if menuId == "credits" then
    self._app:goCredits({
      backScene = "lobby"
    })
    return
  end
  if menuId == "quit" then
    love.event.quit()
  end
end

function LobbyScene:setStatus(statusText, statusColor)
  self._statusText = statusText or ""
  self._statusColor = statusColor or Constants.COLOR_TEXT_SUB
end

function LobbyScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
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
    love.graphics.printf(t("lobby.overlay.nickname.title"), self._overlay.panelX, self._overlay.panelY + 70, self._overlay.panelW, "center")

    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(t("lobby.overlay.nickname.subtitle"), self._overlay.panelX, self._overlay.panelY + 150, self._overlay.panelW, "center")

    self._overlay.nicknameInput:draw()
    self._overlay.saveButton:draw(mouseX, mouseY)
    self._overlay.cancelButton:draw(mouseX, mouseY)
    return
  end

  if self._overlay.kind == "settings" then
    love.graphics.setFont(FontManager.getFont("title"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    love.graphics.printf(t("lobby.overlay.settings.title"), self._overlay.panelX, self._overlay.panelY + 60, self._overlay.panelW, "center")

    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    local labelWidth = self._overlay.controlX - self._overlay.labelX - 22
    local labelBaselineOffset = 12
    love.graphics.printf(
      t("lobby.overlay.settings.display_mode"),
      self._overlay.labelX,
      self._overlay.displayModeRowY + labelBaselineOffset,
      labelWidth,
      "left"
    )
    love.graphics.printf(
      t("lobby.overlay.settings.language"),
      self._overlay.labelX,
      self._overlay.languageRowY + labelBaselineOffset,
      labelWidth,
      "left"
    )

    self._overlay.displayModeDropdown:draw(mouseX, mouseY, "collapsed")
    self._overlay.languageDropdown:draw(mouseX, mouseY, "collapsed")

    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(
      t("lobby.overlay.settings.save_path", {
        path = self._app:getSettingsDebugPath()
      }),
      self._overlay.panelX + 40,
      self._overlay.panelY + self._overlay.panelH - 130,
      self._overlay.panelW - 80,
      "center"
    )

    self._overlay.saveButton:draw(mouseX, mouseY)
    self._overlay.cancelButton:draw(mouseX, mouseY)
    -- Expanded dropdown list is rendered in a dedicated top layer.
    Dropdown.drawExpandedLayer(getSettingsDropdownList(self._overlay), mouseX, mouseY)
  end
end

function LobbyScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("lobby.title"), 0, 62, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("lobby.current_nickname", {
    nickname = self._app:getNickname()
  }), 0, 106, Constants.BASE_WORLD_W, "center")

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
    local clickedDropdown = Dropdown.handleExclusiveMousePressed(
      getSettingsDropdownList(self._overlay),
      mouseX,
      mouseY,
      button
    )
    if clickedDropdown then
      self._overlay.selectedDisplayMode = self._overlay.displayModeDropdown:getSelectedValue()
      self._overlay.selectedLanguage = self._overlay.languageDropdown:getSelectedValue()
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
