--[[
파일명: character_select_scene.lua
모듈명: CharacterSelectScene

역할:
- 초능력 알까기 캐릭터 선택 씬.
- 4종 캐릭터 카드(초상 영역+이름+초능력 설명)를 표시하고
- 클릭 시 선택한 캐릭터 ID를 다음 씬으로 전달한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local BackButton = require("ui.back_button")
local Abilities = require("abilities")

local CharacterSelectScene = {}
CharacterSelectScene.__index = CharacterSelectScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local CARD_W = 240
local CARD_H = 320
local CARD_GAP = 24
local CARD_RADIUS = 12

local function getCharColor(charId)
  if charId == "night_lord" then
    return Constants.COLOR_CHAR_NIGHT_LORD
  elseif charId == "arch_mage" then
    return Constants.COLOR_CHAR_ARCH_MAGE
  elseif charId == "paladin" then
    return Constants.COLOR_CHAR_PALADIN
  elseif charId == "aran" then
    return Constants.COLOR_CHAR_ARAN
  end
  return Constants.COLOR_PANEL_BORDER
end

function CharacterSelectScene.new(app)
  local instance = {
    _app = app,
    _backScene = "play",
    _backButton = nil,
    _characterList = {},
    _selectedCharId = nil,
    _hoveredCharId = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, CharacterSelectScene)
  instance:rebuildLocalizedUi()
  return instance
end

function CharacterSelectScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._characterList = Abilities.getCharacterList()

  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)
end

function CharacterSelectScene:enter(params)
  self._backScene = (params and params.backScene) or "play"
  self._selectedCharId = nil
  self._hoveredCharId = nil
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function CharacterSelectScene:getCardRect(index)
  local totalW = #self._characterList * CARD_W + (#self._characterList - 1) * CARD_GAP
  local startX = (Constants.BASE_WORLD_W - totalW) * 0.5
  local startY = (Constants.BASE_WORLD_H - CARD_H) * 0.5
  return {
    x = startX + (index - 1) * (CARD_W + CARD_GAP),
    y = startY,
    w = CARD_W,
    h = CARD_H
  }
end

function CharacterSelectScene:update(dt)
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  self._hoveredCharId = nil

  for idx, charDef in ipairs(self._characterList) do
    local rect = self:getCardRect(idx)
    if mouseX >= rect.x and mouseX <= rect.x + rect.w
      and mouseY >= rect.y and mouseY <= rect.y + rect.h then
      self._hoveredCharId = charDef.id
      break
    end
  end
end

function CharacterSelectScene:draw()
  local isKo = self._app:getLanguage() == "ko"

  -- 타이틀
  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  local titleText = t("single.character_select.title")
  local titleW = FontManager.getFont("title"):getWidth(titleText)
  love.graphics.print(titleText, (Constants.BASE_WORLD_W - titleW) * 0.5, 60)

  -- 서브타이틀
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  local subtitle = t("single.character_select.subtitle")
  local subW = FontManager.getFont("small"):getWidth(subtitle)
  love.graphics.print(subtitle, (Constants.BASE_WORLD_W - subW) * 0.5, 108)

  -- 캐릭터 카드
  for idx, charDef in ipairs(self._characterList) do
    local rect = self:getCardRect(idx)
    local isHovered = self._hoveredCharId == charDef.id
    local isSelected = self._selectedCharId == charDef.id
    local charColor = getCharColor(charDef.id)
    local ability = charDef.ability

    -- 카드 배경
    if isHovered then
      love.graphics.setColor(0.20, 0.30, 0.50, 1.0)
    else
      love.graphics.setColor(Constants.COLOR_PANEL)
    end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, CARD_RADIUS, CARD_RADIUS)

    -- 선택 표시
    if isSelected then
      love.graphics.setColor(charColor[1], charColor[2], charColor[3], 0.40)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, CARD_RADIUS, CARD_RADIUS)
    end

    -- 테두리
    love.graphics.setColor(isHovered and charColor or Constants.COLOR_PANEL_BORDER)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, CARD_RADIUS, CARD_RADIUS)

    -- 초상 영역 (원)
    local portraitCenterX = rect.x + rect.w * 0.5
    local portraitCenterY = rect.y + 70
    local portraitRadius = 42
    love.graphics.setColor(charColor[1] * 0.3, charColor[2] * 0.3, charColor[3] * 0.3, 1.0)
    love.graphics.circle("fill", portraitCenterX, portraitCenterY, portraitRadius)
    love.graphics.setColor(charColor)
    love.graphics.circle("line", portraitCenterX, portraitCenterY, portraitRadius)

    -- 캐릭터명 중앙
    local name = isKo and charDef.nameKo or charDef.nameEn
    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.setColor(Constants.COLOR_TEXT)
    local nameW = FontManager.getFont("ui"):getWidth(name)
    love.graphics.print(name, rect.x + (rect.w - nameW) * 0.5, rect.y + 130)

    -- 구분선
    love.graphics.setColor(charColor[1], charColor[2], charColor[3], 0.5)
    love.graphics.line(rect.x + 20, rect.y + 168, rect.x + rect.w - 20, rect.y + 168)

    -- 초능력명
    local abilityName = isKo and ability.nameKo or ability.nameEn
    love.graphics.setFont(FontManager.getFont("small"))
    love.graphics.setColor(charColor)
    local abW = FontManager.getFont("small"):getWidth(abilityName)
    love.graphics.print(abilityName, rect.x + (rect.w - abW) * 0.5, rect.y + 178)

    -- 초능력 설명 (워드랩)
    local desc = isKo and ability.descKo or ability.descEn
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    local maxDescW = rect.w - 28
    local fontSize = 15
    -- 간단한 수동 워드랩
    local words = {}
    for word in desc:gmatch("%S+") do
      words[#words + 1] = word
    end
    local lines = {}
    local line = ""
    for _, word in ipairs(words) do
      local testLine = line == "" and word or line .. " " .. word
      if FontManager.getFont("small"):getWidth(testLine) > maxDescW and line ~= "" then
        lines[#lines + 1] = line
        line = word
      else
        line = testLine
      end
    end
    if line ~= "" then
      lines[#lines + 1] = line
    end
    for li, linetext in ipairs(lines) do
      love.graphics.print(linetext, rect.x + 14, rect.y + 208 + (li - 1) * 20)
    end

    -- 호버 시 "선택" 힌트
    if isHovered and not isSelected then
      love.graphics.setColor(1.0, 1.0, 1.0, 0.7)
      local hintText = t("common.button.select")
      local hintW = FontManager.getFont("small"):getWidth(hintText)
      love.graphics.print(hintText, rect.x + (rect.w - hintW) * 0.5, rect.y + rect.h - 30)
    end
  end

  -- 백버튼
  local mouseX, mouseY = self._app:getMouseWorldPosition()
  self._backButton:draw(mouseX, mouseY)
end

function CharacterSelectScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end

  for idx, charDef in ipairs(self._characterList) do
    local rect = self:getCardRect(idx)
    if mouseX >= rect.x and mouseX <= rect.x + rect.w
      and mouseY >= rect.y and mouseY <= rect.y + rect.h then
      self._selectedCharId = charDef.id
      self._app:goMultiplayer({
        selectedCharacterId = charDef.id
      }, Config.TRANSITION_FORWARD)
      return
    end
  end
end

function CharacterSelectScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

return CharacterSelectScene
