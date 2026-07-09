--[[
파일명: debug_menu_scene.lua
모듈명: DebugMenuScene

역할:
- 연출/씬 수동 테스트용 디버그 메뉴를 제공한다.
- 네트워크 연결 없이 주요 씬 및 매치 페이즈 프리셋으로 점프할 수 있다.

외부에서 사용 가능한 함수:
- DebugMenuScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local I18n = require("i18n.i18n")
local FontManager = require("assets.font_manager")
local Button = require("ui.button")
local BackButton = require("ui.back_button")
local TimeUtils = require("utils.time_utils")

local DebugMenuScene = {}
DebugMenuScene.__index = DebugMenuScene

local function t(key, vars)
  return I18n.t(key, vars)
end

local function isPointInRect(x, y, rect)
  if not rect then
    return false
  end
  return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function clonePlacementStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      x = stone.x,
      y = stone.y
    }
  end
  return cloned
end

local function clonePlayingStoneList(stoneList)
  local cloned = {}
  for _, stone in ipairs(stoneList or {}) do
    cloned[#cloned + 1] = {
      id = stone.id,
      ownerPlayerIndex = stone.ownerPlayerIndex,
      x = stone.x,
      y = stone.y,
      alive = stone.alive ~= false
    }
  end
  return cloned
end

local function buildPlacementStonePair()
  local hostStoneList = {}
  local guestStoneList = {}
  local stoneCount = Constants.STONE_COUNT_PER_PLAYER
  local cols = math.max(3, math.ceil(math.sqrt(stoneCount)))
  local spacingX = (Constants.BOARD_W - 140) / math.max(1, cols - 1)

  for index = 1, stoneCount do
    local col = (index - 1) % cols
    local row = math.floor((index - 1) / cols)
    local hostX = 70 + col * spacingX + (row % 2) * 14
    local hostY = Constants.BOARD_H - 120 - row * 42
    local guestX = 70 + col * spacingX + ((row + 1) % 2) * 14
    local guestY = 120 + row * 42
    hostStoneList[#hostStoneList + 1] = {
      id = "h" .. tostring(index),
      x = hostX,
      y = hostY
    }
    guestStoneList[#guestStoneList + 1] = {
      id = "g" .. tostring(index),
      x = guestX,
      y = guestY
    }
  end

  return hostStoneList, guestStoneList
end

local function buildMockMatchRoomState(phase, options)
  local nowMs = TimeUtils.nowEpochMs()
  local hostPlacementStoneList, guestPlacementStoneList = buildPlacementStonePair()
  local playingStoneList = {}
  for _, stone in ipairs(hostPlacementStoneList) do
    playingStoneList[#playingStoneList + 1] = {
      id = stone.id,
      ownerPlayerIndex = 1,
      x = stone.x,
      y = stone.y,
      alive = true
    }
  end
  for _, stone in ipairs(guestPlacementStoneList) do
    playingStoneList[#playingStoneList + 1] = {
      id = stone.id,
      ownerPlayerIndex = 2,
      x = stone.x,
      y = stone.y,
      alive = true
    }
  end

  local cardRuleOptions = options or {}
  local dealtCardList = cardRuleOptions.dealtCards or {
    "reinforcement",
    "shockwave"
  }
  local pickCount = cardRuleOptions.pickCount or 1
  local myLocked = cardRuleOptions.myLocked == true
  local opponentLocked = cardRuleOptions.opponentLocked == true

  local roomState = {
    roomCode = "DEBUGROOM0000001",
    phase = phase,
    host = {
      connected = true,
      nickname = "DebugHost"
    },
    guest = {
      connected = true,
      nickname = "DebugGuest"
    },
    guestReady = true,
    timers = {},
    match = {
      firstPlayerIndex = 1,
      placement = {
        myStones = clonePlacementStoneList(hostPlacementStoneList),
        mySubmitted = true,
        opponentSubmitted = true,
        hostSubmitted = true,
        guestSubmitted = true,
        revealStones = {
          host = clonePlacementStoneList(hostPlacementStoneList),
          guest = clonePlacementStoneList(guestPlacementStoneList)
        },
        revealEndsAtMs = nil
      },
      cardSelect = {
        myDealtCards = dealtCardList,
        myPickedCards = myLocked and { dealtCardList[1] } or {},
        myPickCount = pickCount,
        myLocked = myLocked,
        opponentLocked = opponentLocked,
        hostLocked = false,
        guestLocked = false,
        selectEndsAtMs = nowMs + Constants.CARD_PICK_SEC * 1000
      },
      playing = {
        turnIndex = 3,
        activePlayerIndex = 1,
        turnEndsAtMs = nowMs + Constants.TURN_TIME_LIMIT_SEC * 1000,
        shotBudget = 1,
        shotUsed = 0,
        hasCardUsedThisTurn = false,
        lockedStoneIds = {},
        obstacles = {
          {
            id = "rock_debug_1",
            x = Constants.BOARD_W * 0.5,
            y = Constants.BOARD_H * 0.5,
            width = Constants.ROCK_OBSTACLE_WIDTH,
            height = Constants.ROCK_OBSTACLE_HEIGHT
          }
        },
        invincibleTurnByPlayer = {
          [1] = nil,
          [2] = nil
        },
        shockwaveOwnerPlayerIndex = nil,
        shotCommitted = false,
        awaitingSnapshot = false,
        stones = clonePlayingStoneList(playingStoneList)
      }
    },
    result = nil
  }

  if phase == Constants.PHASE_PLACEMENT_PRIVATE then
    roomState.match.placement.mySubmitted = false
    roomState.match.placement.opponentSubmitted = false
    roomState.match.placement.hostSubmitted = false
    roomState.match.placement.guestSubmitted = false
    roomState.match.placement.revealStones = nil
    roomState.match.placement.myStones = {
      clonePlacementStoneList(hostPlacementStoneList)[1],
      clonePlacementStoneList(hostPlacementStoneList)[2]
    }
  elseif phase == Constants.PHASE_PLACEMENT_REVEAL then
    roomState.match.placement.revealEndsAtMs = nowMs + 5000
  elseif phase == Constants.PHASE_PLAYING then
    roomState.match.cardSelect.myPickedCards = {
      "agile"
    }
    roomState.match.cardSelect.myLocked = true
    roomState.match.cardSelect.opponentLocked = true
    roomState.match.cardSelect.selectEndsAtMs = nil
  elseif phase == Constants.PHASE_RESULT then
    roomState.result = {
      winnerPlayerIndex = 1,
      reason = "stone_zero",
      myVote = nil,
      opponentVote = nil
    }
  end

  return roomState
end

local function buildCardZoneTestRoomState()
  local roomState = buildMockMatchRoomState(Constants.PHASE_PLAYING)
  roomState.match.cardSelect.myPickedCards = {
    "reinforcement",
    "rockfall",
    "invincible"
  }
  roomState.match.cardSelect.myLocked = true
  roomState.match.cardSelect.opponentLocked = true
  roomState.match.playing.activePlayerIndex = 1
  roomState.match.playing.hasCardUsedThisTurn = false
  roomState.match.playing.shotUsed = 0
  roomState.match.playing.shotBudget = 1
  roomState.match.playing.awaitingSnapshot = false
  roomState.match.playing.shotCommitted = false
  return roomState
end

function DebugMenuScene.new(app)
  local instance = {
    _app = app,
    _backScene = "lobby",
    _statusText = "",
    _statusColor = Constants.COLOR_TEXT_SUB,
    _backButton = nil,
    _buttonList = {},
    _serverEnvPanelRect = nil,
    _serverEnvLocalRect = nil,
    _serverEnvCloudRect = nil,
    _serverEnvApplyButton = nil,
    _serverEnvPending = app:getServerEnv(),
    _lastLanguage = app:getLanguage()
  }
  setmetatable(instance, DebugMenuScene)
  instance:rebuildLocalizedUi()
  return instance
end

function DebugMenuScene:createActionList()
  return {
    {
      label = t("debug_menu.action.go_lobby"),
      onClick = function()
        self._app:goLobby(nil, Config.TRANSITION_BACK)
      end
    },
    {
      label = t("debug_menu.action.go_play"),
      onClick = function()
        self._app:goPlay({
          backScene = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.go_multiplayer"),
      onClick = function()
        self._app:goMultiplayer({
          backScene = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.go_room_search"),
      onClick = function()
        self._app:goRoomSearch({
          backScene = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.waiting_mock"),
      onClick = function()
        self._app:goWaitingRoom({
          roomState = {
            phase = Constants.PHASE_WAITING,
            host = {
              connected = true,
              nickname = "DebugHost"
            },
            guest = {
              connected = true,
              nickname = "DebugGuest"
            },
            guestReady = true
          },
          statusText = t("debug_menu.status.waiting_mock"),
          statusColor = Constants.COLOR_TEXT_SUB
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.coin_first"),
      onClick = function()
        self._app:goScene("coinTossFirst", {
          roomState = buildMockMatchRoomState(Constants.PHASE_PLACEMENT_PRIVATE),
          nextSceneName = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.coin_second"),
      onClick = function()
        self._app:goScene("coinTossSecond", {
          roomState = buildMockMatchRoomState(Constants.PHASE_PLACEMENT_PRIVATE),
          nextSceneName = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_placement"),
      onClick = function()
        self._app:goMatch({
          roomState = buildMockMatchRoomState(Constants.PHASE_PLACEMENT_PRIVATE)
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_card_first"),
      onClick = function()
        self._app:goMatch({
          roomState = buildMockMatchRoomState(Constants.PHASE_PLAYING, {
            pickCount = 1,
            dealtCards = {
              "reinforcement",
              "shockwave"
            }
          })
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_card_second"),
      onClick = function()
        self._app:goMatch({
          roomState = buildMockMatchRoomState(Constants.PHASE_PLAYING, {
            pickCount = 2,
            dealtCards = {
              "invincible",
              "rockfall",
              "agile"
            }
          })
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_playing"),
      onClick = function()
        self._app:goMatch({
          roomState = buildMockMatchRoomState(Constants.PHASE_PLAYING)
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_card_zone"),
      onClick = function()
        self._app:goMatch({
          roomState = buildCardZoneTestRoomState(),
          localRole = "host"
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.match_result"),
      onClick = function()
        self._app:goMatch({
          roomState = buildMockMatchRoomState(Constants.PHASE_RESULT)
        }, Config.TRANSITION_FORWARD)
      end
    },
    {
      label = t("debug_menu.action.single_dummy"),
      onClick = function()
        self._app:goSingleDummy({
          backScene = "debugMenu"
        }, Config.TRANSITION_FORWARD)
      end
    }
  }
end

function DebugMenuScene:rebuildLocalizedUi()
  self._lastLanguage = self._app:getLanguage()
  self._backButton = BackButton.new(t("common.button.back"), function()
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end)

  local actionList = self:createActionList()
  self._buttonList = {}
  local columns = 2
  local buttonW = 500
  local buttonH = 44
  local gapX = 32
  local gapY = 12
  local startX = (Constants.BASE_WORLD_W - (buttonW * columns + gapX)) * 0.5
  local startY = 150

  for index, action in ipairs(actionList) do
    local row = math.floor((index - 1) / columns)
    local col = (index - 1) % columns
    local x = startX + col * (buttonW + gapX)
    local y = startY + row * (buttonH + gapY)
    self._buttonList[#self._buttonList + 1] = Button.new({
      x = x,
      y = y,
      w = buttonW,
      h = buttonH,
      label = action.label,
      onClick = action.onClick
    })
  end

  local panelW = 700
  local panelH = 116
  local panelX = (Constants.BASE_WORLD_W - panelW) * 0.5
  local panelY = 548
  self._serverEnvPanelRect = {
    x = panelX,
    y = panelY,
    w = panelW,
    h = panelH
  }
  self._serverEnvLocalRect = {
    x = panelX + 24,
    y = panelY + 40,
    w = 130,
    h = 28
  }
  self._serverEnvCloudRect = {
    x = panelX + 170,
    y = panelY + 40,
    w = 150,
    h = 28
  }
  self._serverEnvApplyButton = Button.new({
    x = panelX + panelW - 126,
    y = panelY + panelH - 42,
    w = 96,
    h = 30,
    label = t("debug_menu.network.apply"),
    onClick = function()
      local isOk, statusText = self._app:setServerEnv(self._serverEnvPending)
      if isOk then
        self._statusColor = Constants.COLOR_TEXT_SUB
      else
        self._statusColor = Constants.COLOR_DANGER
      end
      self._statusText = statusText or ""
    end
  })
end

function DebugMenuScene:enter(params)
  self._backScene = (params and params.backScene) or "lobby"
  self._statusText = (params and params.statusText) or t("debug_menu.status.default")
  self._statusColor = (params and params.statusColor) or Constants.COLOR_TEXT_SUB
  self._serverEnvPending = self._app:getServerEnv()
  self:rebuildLocalizedUi()
end

function DebugMenuScene:update(_dt)
  if self._lastLanguage ~= self._app:getLanguage() then
    self:rebuildLocalizedUi()
  end
end

function DebugMenuScene:draw()
  local mouseX, mouseY = self._app:getMouseWorldPosition()

  love.graphics.setFont(FontManager.getFont("title"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.printf(t("debug_menu.title"), 0, 70, Constants.BASE_WORLD_W, "center")

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT_SUB)
  love.graphics.printf(t("debug_menu.subtitle"), 0, 112, Constants.BASE_WORLD_W, "center")

  self._backButton:draw(mouseX, mouseY)
  for _, button in ipairs(self._buttonList) do
    button:draw(mouseX, mouseY)
  end

  self:drawServerEnvPanel(mouseX, mouseY)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(self._statusColor)
  love.graphics.printf(self._statusText, 0, 690, Constants.BASE_WORLD_W, "center")
end

function DebugMenuScene:drawServerEnvPanel(mouseX, mouseY)
  local panel = self._serverEnvPanelRect
  if not panel then
    return
  end

  local canSwitch = self._app:canSwitchServerEnv()
  local currentEnv = self._app:getServerEnv()
  local pendingEnv = self._serverEnvPending
  local alpha = canSwitch and 1.0 or 0.55

  love.graphics.setColor(0.0, 0.0, 0.0, 0.36)
  love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 8, 8)
  love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], 0.85)
  love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 8, 8)

  love.graphics.setFont(FontManager.getFont("small"))
  love.graphics.setColor(Constants.COLOR_TEXT)
  love.graphics.print(t("debug_menu.network.title"), panel.x + 16, panel.y + 12)

  love.graphics.setColor(Constants.COLOR_TEXT_SUB[1], Constants.COLOR_TEXT_SUB[2], Constants.COLOR_TEXT_SUB[3], alpha)
  love.graphics.print(
    t("debug_menu.network.current", {
      env = currentEnv == Constants.SERVER_ENV_LOCAL and t("debug_menu.network.local") or t("debug_menu.network.cloud")
    }),
    panel.x + 16,
    panel.y + 30
  )

  self:drawServerEnvRadio(self._serverEnvLocalRect, t("debug_menu.network.local"), pendingEnv == Constants.SERVER_ENV_LOCAL, alpha)
  self:drawServerEnvRadio(self._serverEnvCloudRect, t("debug_menu.network.cloud"), pendingEnv == Constants.SERVER_ENV_CLOUD, alpha)

  local httpBase = self._app:getServerHttpBase(pendingEnv)
  love.graphics.setColor(Constants.COLOR_TEXT_SUB[1], Constants.COLOR_TEXT_SUB[2], Constants.COLOR_TEXT_SUB[3], 0.90)
  love.graphics.print("HTTP: " .. tostring(httpBase), panel.x + 342, panel.y + 44)
  love.graphics.print("Transport: HTTP long-poll", panel.x + 342, panel.y + 66)

  self._serverEnvApplyButton.isEnabled = canSwitch and pendingEnv ~= currentEnv
  self._serverEnvApplyButton:draw(mouseX, mouseY)
end

function DebugMenuScene:drawServerEnvRadio(rect, label, isSelected, alpha)
  local circleX = rect.x + 10
  local circleY = rect.y + rect.h * 0.5
  love.graphics.setColor(Constants.COLOR_TEXT_SUB[1], Constants.COLOR_TEXT_SUB[2], Constants.COLOR_TEXT_SUB[3], alpha)
  love.graphics.circle("line", circleX, circleY, 8)
  if isSelected then
    love.graphics.setColor(Constants.COLOR_PANEL_BORDER[1], Constants.COLOR_PANEL_BORDER[2], Constants.COLOR_PANEL_BORDER[3], alpha)
    love.graphics.circle("fill", circleX, circleY, 4)
  end

  love.graphics.setColor(Constants.COLOR_TEXT[1], Constants.COLOR_TEXT[2], Constants.COLOR_TEXT[3], alpha)
  love.graphics.print(label, rect.x + 24, rect.y + (rect.h - FontManager.getFont("small"):getHeight()) * 0.5)
end

function DebugMenuScene:mousepressed(mouseX, mouseY, button)
  if button ~= 1 then
    return
  end

  if self._backButton:isHovered(mouseX, mouseY) then
    self._backButton:onClick()
    return
  end

  if self:handleServerEnvMousePressed(mouseX, mouseY) then
    return
  end

  for _, menuButton in ipairs(self._buttonList) do
    if menuButton:isHovered(mouseX, mouseY) then
      menuButton:onClick()
      return
    end
  end
end

function DebugMenuScene:handleServerEnvMousePressed(mouseX, mouseY)
  local panel = self._serverEnvPanelRect
  if not panel or not isPointInRect(mouseX, mouseY, panel) then
    return false
  end

  local canSwitch = self._app:canSwitchServerEnv()
  if isPointInRect(mouseX, mouseY, self._serverEnvLocalRect) then
    if canSwitch then
      self._serverEnvPending = Constants.SERVER_ENV_LOCAL
    else
      self._statusText = t("debug_menu.status.server_env_locked")
      self._statusColor = Constants.COLOR_DANGER
    end
    return true
  end
  if isPointInRect(mouseX, mouseY, self._serverEnvCloudRect) then
    if canSwitch then
      self._serverEnvPending = Constants.SERVER_ENV_CLOUD
    else
      self._statusText = t("debug_menu.status.server_env_locked")
      self._statusColor = Constants.COLOR_DANGER
    end
    return true
  end
  if self._serverEnvApplyButton and self._serverEnvApplyButton:isHovered(mouseX, mouseY) then
    if self._serverEnvApplyButton.isEnabled then
      self._serverEnvApplyButton:onClick()
    elseif not canSwitch then
      self._statusText = t("debug_menu.status.server_env_locked")
      self._statusColor = Constants.COLOR_DANGER
    end
    return true
  end

  return true
end

function DebugMenuScene:keypressed(key)
  if key == "escape" then
    self._app:goScene(self._backScene, nil, Config.TRANSITION_BACK)
  end
end

function DebugMenuScene:onAppEvent(event)
  if event.type == "ui_status" then
    self._statusText = event.text or ""
    self._statusColor = event.color or Constants.COLOR_TEXT_SUB
  end
end

return DebugMenuScene
