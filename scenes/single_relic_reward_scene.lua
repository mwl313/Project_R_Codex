--[[
파일명: single_relic_reward_scene.lua
모듈명: SingleRelicRewardScene

역할:
- 전투 후 릴릭 보상 3선택 UI를 제공한다.
- 선택 릴릭을 runState.relicIds에 추가하고 다음 보상 단계로 진행한다.
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local SingleRunState = require("single.single_run_state")
local RelicRegistry = require("single.relic_registry")

local SingleRelicRewardScene = {}
SingleRelicRewardScene.__index = SingleRelicRewardScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function resolveRelicName(relicId)
  local key = "single.relic.name." .. tostring(relicId or "")
  local translated = t(key)
  if type(translated) == "string" and not translated:find("^%[%[missing:") then
    return translated
  end
  return tostring(relicId or "")
end

local function resolveRelicDesc(relicId)
  local key = "single.relic.desc." .. tostring(relicId or "")
  local translated = t(key)
  if type(translated) == "string" and not translated:find("^%[%[missing:") then
    return translated
  end
  return ""
end

local function hasRelic(runState, relicId)
  if type(runState) ~= "table" or type(runState.relicIds) ~= "table" then
    return false
  end
  local targetId = tostring(relicId or "")
  for _, existingId in ipairs(runState.relicIds) do
    if tostring(existingId or "") == targetId then
      return true
    end
  end
  return false
end

function SingleRelicRewardScene.new(app)
  local instance = {
    _app = app,
    _profile = nil,
    _runState = nil,
    _nodeType = "mob",
    _nodeId = "",
    _stageIndex = 1,
    _isBoss = false,
    _choiceList = {},
    _choiceButtonList = {},
    _selectedIndex = nil,
    _confirmButton = nil,
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _lastLanguage = app:getLanguage(),
    _nextSceneName = "single_reward",
    _nextSceneParams = nil,
    _pendingAutoContinue = false
  }
  setmetatable(instance, SingleRelicRewardScene)
  instance:rebuildLocalizedUi()
  return instance
end

function SingleRelicRewardScene:setStatus(text, color)
  self._statusText = tostring(text or "")
  self._statusColor = color or Constants.COLOR_TEXT_SUB
end

function SingleRelicRewardScene:buildDefaultNextSceneParams()
  return {
    profile = self._profile,
    runState = self._runState,
    nodeType = self._nodeType,
    stageIndex = self._stageIndex,
    isBoss = self._isBoss
  }
end

function SingleRelicRewardScene:goNext()
  local nextParams = self._nextSceneParams or self:buildDefaultNextSceneParams()
  self._app:goScene(self._nextSceneName, nextParams, Config.TRANSITION_FORWARD)
end

function SingleRelicRewardScene:rebuildChoiceButtons()
  self._choiceButtonList = {}
  local startX = (Constants.BASE_WORLD_W - (3 * 250 + 2 * 26)) * 0.5
  for index = 1, 3 do
    local relic = self._choiceList[index]
    self._choiceButtonList[index] = Button.new({
      x = startX + (index - 1) * 276,
      y = 258,
      w = 250,
      h = 230,
      label = relic and relic.displayName or "-",
      onClick = function()
        self._selectedIndex = index
      end
    })
  end
end

function SingleRelicRewardScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._confirmButton = Button.new({
    x = (Constants.BASE_WORLD_W - Constants.BUTTON_W) * 0.5,
    y = 534,
    label = t("single.relic_reward.button.confirm"),
    onClick = function()
      self:confirmChoice()
    end
  })
  self:rebuildChoiceButtons()
end

function SingleRelicRewardScene:confirmChoice()
  if self._pendingAutoContinue then
    return
  end
  if not self._selectedIndex then
    self:setStatus(t("single.relic_reward.status.select_required"), Constants.COLOR_DANGER)
    return
  end
  local selected = self._choiceList[self._selectedIndex]
  if not selected then
    self:setStatus(t("single.relic_reward.status.select_required"), Constants.COLOR_DANGER)
    return
  end

  SingleRunState.ensureDefaults(self._runState, self._profile)
  if not hasRelic(self._runState, selected.relicId) then
    self._runState.relicIds[#self._runState.relicIds + 1] = selected.relicId
  end

  self:setStatus(t("single.relic_reward.status.picked", {
    relic = selected.displayName
  }), Constants.COLOR_TEXT_SUB)
  self:goNext()
end

function SingleRelicRewardScene:enter(params)
  self._profile = params and params.profile or nil
  self._runState = params and params.runState or {}
  self._nodeType = tostring((params and params.nodeType) or "mob")
  self._nodeId = tostring((params and params.nodeId) or "")
  self._stageIndex = math.max(1, math.floor(tonumber(params and params.stageIndex) or 1))
  self._isBoss = (params and params.isBoss == true) or self._nodeType == "boss"
  self._nextSceneName = tostring((params and params.nextSceneName) or "single_reward")
  self._nextSceneParams = params and params.nextSceneParams or nil
  self._pendingAutoContinue = false

  SingleRunState.ensureDefaults(self._runState, self._profile)

  local pickSeed = (tonumber(self._runState and self._runState.rngSeed) or os.time())
    + self._stageIndex * 971
    + (#(self._runState.relicIds or {}) * 17)
  local pickedRelics = RelicRegistry.pickRewardChoices({
    count = 3,
    isBoss = self._isBoss,
    runState = self._runState,
    rngSeed = pickSeed
  })

  self._choiceList = {}
  for _, relic in ipairs(pickedRelics or {}) do
    local relicId = tostring(relic.relicId or "")
    if relicId ~= "" then
      self._choiceList[#self._choiceList + 1] = {
        relicId = relicId,
        rarity = tostring(relic.rarity or "COMMON"),
        displayName = resolveRelicName(relicId),
        displayDesc = resolveRelicDesc(relicId)
      }
    end
  end

  while #self._choiceList < 3 and #self._choiceList > 0 do
    self._choiceList[#self._choiceList + 1] = self._choiceList[#self._choiceList]
  end

  self._selectedIndex = nil
  self:rebuildLocalizedUi()

  if #self._choiceList <= 0 then
    self._pendingAutoContinue = true
    self:setStatus(t("single.relic_reward.status.skip_empty"), Constants.COLOR_TEXT_SUB)
    return
  end

  self:setStatus(t("single.relic_reward.status.choose_one"), Constants.COLOR_TEXT_SUB)
end

function SingleRelicRewardScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
  if self._pendingAutoContinue then
    self._pendingAutoContinue = false
    self:goNext()
  end
end

function SingleRelicRewardScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("single.relic_reward.title"), 0, 88, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("ui"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("single.relic_reward.subtitle"), 0, 142, Constants.BASE_WORLD_W, "center")

  for index, button in ipairs(self._choiceButtonList) do
    local relic = self._choiceList[index]
    button.isPressed = self._selectedIndex == index
    button:draw(mouseX, mouseY)
    if relic then
      love.graphics.setFont(FontManager.getFont("small"))
      love.graphics.setColor(Constants.COLOR_TEXT_SUB)
      love.graphics.printf(t("single.relic_reward.rarity_line", {
        rarity = tostring(relic.rarity)
      }), button.x + 14, button.y + 124, button.w - 28, "center")
      love.graphics.printf(relic.displayDesc, button.x + 14, button.y + 152, button.w - 28, "center")
    end
  end

  self._confirmButton:draw(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 688, Constants.BASE_WORLD_W, "center")
end

function SingleRelicRewardScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  for index, choiceButton in ipairs(self._choiceButtonList) do
    if choiceButton:isHovered(mouseX, mouseY) then
      choiceButton:onClick()
      local relic = self._choiceList[index]
      if relic then
        self:setStatus(t("single.relic_reward.status.selected", {
          relic = relic.displayName
        }), Constants.COLOR_TEXT_SUB)
      end
      return
    end
  end

  if self._confirmButton:isHovered(mouseX, mouseY) then
    self._confirmButton:onClick()
  end
end

function SingleRelicRewardScene:keypressed(key)
  if key == "escape" then
    return
  end
end

function SingleRelicRewardScene:onAppEvent(_event)
end

return SingleRelicRewardScene
