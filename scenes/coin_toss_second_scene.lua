--[[
파일명: coin_toss_second_scene.lua
모듈명: CoinTossSecondScene

역할:
- local player가 후공일 때 코인 토스 연출을 보여준다.
- 연출 종료 후 자동으로 매치 씬으로 진행한다.

외부에서 사용 가능한 함수:
- CoinTossSecondScene.new(app)
]]

local Constants = require("constants")
local Config = require("config")
local CoinTossView = require("ui.coin_toss_view")

local CoinTossSecondScene = {}
CoinTossSecondScene.__index = CoinTossSecondScene

function CoinTossSecondScene.new(app)
  local instance = {
    _app = app,
    _view = nil,
    _nextSceneName = "match",
    _latestRoomState = nil,
    _isLeaving = false,
    _startDelaySec = Constants.COIN_TOSS_START_DELAY_SEC,
    _startDelayElapsedSec = 0,
    _postHoldSec = Constants.COIN_TOSS_POST_HOLD_SEC,
    _postHoldElapsedSec = 0
  }
  return setmetatable(instance, CoinTossSecondScene)
end

function CoinTossSecondScene:enter(params)
  self._isLeaving = false
  self._startDelayElapsedSec = 0
  self._postHoldElapsedSec = 0
  self._nextSceneName = (params and params.nextSceneName) or "match"
  self._latestRoomState = params and params.roomState or nil
  self._selectedCharacterId = tostring((params and params.selectedCharacterId) or "")
  self._view = CoinTossView.new({
    isFirst = false,
    totalSec = Constants.COIN_TOSS_TOTAL_SEC,
    flipSec = Constants.COIN_TOSS_FLIP_SEC,
    pulseAmplitude = Constants.COIN_TOSS_PULSE_AMPLITUDE,
    titleText = "후공",
    subtitleText = "당신이 후공입니다."
  })
end

function CoinTossSecondScene:update(dt)
  if not self._view then
    return
  end
  if self._isLeaving then
    return
  end

  if self._startDelayElapsedSec < self._startDelaySec then
    self._startDelayElapsedSec = math.min(self._startDelaySec, self._startDelayElapsedSec + dt)
    return
  end

  self._view:update(dt)
  if not self._view:isComplete() then
    return
  end

  self._postHoldElapsedSec = self._postHoldElapsedSec + dt
  if self._postHoldElapsedSec < self._postHoldSec then
    return
  end

  self._isLeaving = true
  local session = self._app:getSession()
  local nextParams = {}
  local roomState = self._latestRoomState or (session and session.lastRoomState) or nil
  if type(roomState) == "table" then
    nextParams.roomState = roomState
  end
  if self._selectedCharacterId ~= "" then
    nextParams.selectedCharacterId = self._selectedCharacterId
  end
  self._app:goScene(self._nextSceneName, nextParams, Config.TRANSITION_FORWARD)
end

function CoinTossSecondScene:draw()
  if not self._view then
    return
  end
  if self._startDelayElapsedSec < self._startDelaySec then
    self._view:drawIdle()
    return
  end
  self._view:draw()
end

function CoinTossSecondScene:onAppEvent(event)
  if event.type ~= "server_envelope" then
    return
  end
  local envelope = event.envelope
  if not envelope or type(envelope) ~= "table" then
    return
  end
  if envelope.type == "room.state" and type(envelope.payload) == "table" then
    self._latestRoomState = envelope.payload
  end
end

return CoinTossSecondScene
