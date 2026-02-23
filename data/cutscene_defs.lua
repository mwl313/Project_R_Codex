--[[
파일명: cutscene_defs.lua
모듈명: CutsceneDefs

역할:
- 카드별 스킬 컷신 설정(시간/색상/연출 파라미터)을 한 곳에서 관리한다.
- 현재는 프리미티브(도형) 기반 placeholder 연출이며, 추후 에셋 교체를 위한 필드를 포함한다.

외부에서 사용 가능한 함수:
- CutsceneDefs.get(cardId)
]]

local Constants = require("constants")

local CutsceneDefs = {}

local DEFAULT_DEF = {
  durationMs = Constants.CUTSCENE_DEFAULT_DURATION_MS,
  cardFocusSec = Constants.CUTSCENE_CARD_FOCUS_SEC,
  bandEnterSec = Constants.CUTSCENE_BAND_ENTER_SEC,
  characterEnterSec = Constants.CUTSCENE_CHARACTER_ENTER_SEC,
  characterShakeSec = Constants.CUTSCENE_CHARACTER_SHAKE_SEC,
  characterExitSec = Constants.CUTSCENE_CHARACTER_EXIT_SEC,
  bandExitSec = Constants.CUTSCENE_BAND_EXIT_SEC,
  bandWidth = Constants.CUTSCENE_BAND_WIDTH,
  bandHeight = Constants.CUTSCENE_BAND_HEIGHT,
  bandTiltPx = Constants.CUTSCENE_BAND_TILT_PX,
  bandShakePx = Constants.CUTSCENE_BAND_SHAKE_PX,
  bandRearHeightScale = Constants.CUTSCENE_BAND_REAR_HEIGHT_SCALE,
  bandFrontHeightScale = Constants.CUTSCENE_BAND_FRONT_HEIGHT_SCALE,
  dimAlpha = Constants.CUTSCENE_DIM_ALPHA,
  bandColor = { 0.17, 0.30, 0.52, 0.90 },
  bandBorderColor = { 0.55, 0.74, 0.96, 0.92 },
  characterPlaceholderColor = { 1.0, 0.92, 0.18, 0.42 },
  characterPlaceholderBorder = { 1.0, 0.97, 0.62, 0.90 },
  characterWidth = Constants.CUTSCENE_CHARACTER_W,
  characterHeight = Constants.CUTSCENE_CHARACTER_H,
  -- 아래 필드는 향후 실제 에셋 적용용 예약 슬롯이다.
  characterAssetPath = nil,
  bandAssetPath = nil,
  usesGif = false
}

local CUTSCENE_DEF_BY_CARD_ID = {
  reinforcement = {
    bandColor = { 0.20, 0.47, 0.36, 0.90 },
    bandBorderColor = { 0.55, 0.90, 0.74, 0.92 }
  },
  shockwave = {
    bandColor = { 0.36, 0.26, 0.56, 0.90 },
    bandBorderColor = { 0.76, 0.62, 0.96, 0.92 }
  },
  invincible = {
    bandColor = { 0.16, 0.36, 0.54, 0.90 },
    bandBorderColor = { 0.60, 0.82, 0.96, 0.92 }
  },
  rockfall = {
    bandColor = { 0.44, 0.32, 0.20, 0.90 },
    bandBorderColor = { 0.88, 0.73, 0.52, 0.92 }
  },
  agile = {
    bandColor = { 0.42, 0.22, 0.22, 0.90 },
    bandBorderColor = { 0.96, 0.62, 0.62, 0.92 }
  }
}

local function copyTable(source)
  local copied = {}
  for key, value in pairs(source or {}) do
    if type(value) == "table" then
      local nested = {}
      for nestedKey, nestedValue in pairs(value) do
        nested[nestedKey] = nestedValue
      end
      copied[key] = nested
    else
      copied[key] = value
    end
  end
  return copied
end

function CutsceneDefs.get(cardId)
  local merged = copyTable(DEFAULT_DEF)
  local override = CUTSCENE_DEF_BY_CARD_ID[tostring(cardId or "")]
  for key, value in pairs(override or {}) do
    if type(value) == "table" then
      merged[key] = copyTable(value)
    else
      merged[key] = value
    end
  end
  return merged
end

return CutsceneDefs
