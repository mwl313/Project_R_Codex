--[[
파일명: config.lua
모듈명: Config

역할:
- 클라이언트 전역 런타임 설정 플래그를 보관한다.
]]

local Config = {
  -- false = 레거시 사각형 UI
  -- true = 9-slice UI 스킨
  UI_USE_NINESLICE = false,

  TRANSITION_FORWARD = "FORWARD",
  TRANSITION_BACK = "BACK",
  TRANSITION_WIPE_ENABLED = true,
  TRANSITION_WIPE_DURATION_SEC = 0.80,
  TRANSITION_WIPE_BAND_WIDTH_RATIO = 1.00,
  TRANSITION_WIPE_EDGE_SOFTNESS_PX = 24
}

return Config

