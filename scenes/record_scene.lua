--[[
파일명: record_scene.lua
모듈명: RecordScene

역할:
- 승패 기록 통계 및 최근 전적 리스트 화면
- 백버튼으로 로비 복귀

외부에서 사용 가능한 함수:
- RecordScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local BackButton = require("ui.back_button")
local MatchHistory = require("utils.match_history")

local RecordScene = {}
RecordScene.__index = RecordScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function safeLoadRecords()
  local ok, records, stats = pcall(function()
    return MatchHistory.getRecent(10), MatchHistory.getStats()
  end)
  if ok then
    return records, stats
  end
  return {}, { totalGames = 0, wins = 0, losses = 0, winRate = 0, characterStats = {} }
end

function RecordScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _backButton = nil,
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, RecordScene)
  instance:rebuildLocalizedUi()
  return instance
end

function RecordScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)
end

function RecordScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self:rebuildLocalizedUi()
end

function RecordScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function RecordScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("record.title"), 0, 50, Constants.BASE_WORLD_W, "center")

  local records, stats = safeLoadRecords()

  -- 통계 영역
  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  local statsText = t("record.stats_line", {
    wins = stats.wins,
    losses = stats.losses,
    total = stats.totalGames,
    rate = string.format("%.1f%%", stats.winRate * 100)
  })
  love.graphics.printf(statsText, 0, 105, Constants.BASE_WORLD_W, "center")

  -- 캐릭터별 전적
  local charY = 145
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("record.character_stats_title"), 40, charY, Constants.BASE_WORLD_W - 80, "left")
  charY = charY + 22

  local charStats = stats.characterStats or {}
  for charId, charStat in pairs(charStats) do
    local charLine = t("record.character_stats_line", {
      character = charId,
      played = charStat.played,
      wins = charStat.wins,
      rate = charStat.played > 0 and string.format("%.0f%%", (charStat.wins / charStat.played) * 100) or "0%"
    })
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.printf(charLine, 60, charY, Constants.BASE_WORLD_W - 100, "left")
    charY = charY + 20
  end

  -- 최근 10경기 리스트
  local listY = math.max(charY + 20, 260)
  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("record.recent_title"), 40, listY, Constants.BASE_WORLD_W - 80, "left")
  listY = listY + 22

  for i, record in ipairs(records) do
    local resultLabel = record.result == "win" and t("record.result_win") or t("record.result_loss")
    local dateStr = tostring(record.date or "")
    local datePart = #dateStr > 10 and string.sub(dateStr, 1, 10) or dateStr
    local line = string.format("%d. %s | %s vs %s (%s) | %s",
      i,
      datePart,
      record.myCharacter or "?",
      record.opponentCharacter or "?",
      record.opponentNickname or "?",
      resultLabel)

    love.graphics.setColor(record.result == "win" and Constants.COLOR_SUCCESS or Constants.COLOR_DANGER)
    love.graphics.printf(line, 40, listY, Constants.BASE_WORLD_W - 80, "left")
    listY = listY + 20

    if listY > Constants.BASE_WORLD_H - 40 then
      break
    end
  end

  -- 기록이 없는 경우
  if #records == 0 then
    love.graphics.setColor(Constants.COLOR_TEXT_SUB)
    love.graphics.setFont(FontManager.getFont("ui"))
    love.graphics.printf(t("record.no_records"), 40, listY, Constants.BASE_WORLD_W - 80, "left")
  end

  self._backButton:draw(mouseX, mouseY)
end

function RecordScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end
  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
  end
end

function RecordScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function RecordScene:onAppEvent(_event)
end

return RecordScene
