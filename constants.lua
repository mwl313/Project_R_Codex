--[[
파일명: constants.lua
모듈명: Constants

역할:
- Phase 2 클라이언트 상수 정의
- 화면/네트워크/UI 관련 기본값 제공

외부에서 사용 가능한 함수:
- Constants 값 테이블 참조

주의:
- 하드코딩 숫자는 이 파일로 모은다
]]

local Constants = {
  BASE_WORLD_W = 1280,
  BASE_WORLD_H = 720,

  SERVER_HTTP_BASE_URL = "http://127.0.0.1:8787",
  SERVER_WS_BASE_URL = "ws://127.0.0.1:8787",

  FONT_KR_REGULAR_PATH = "assets/fonts/NotoSansKR-Regular.ttf",
  FONT_SIZE_TITLE = 34,
  FONT_SIZE_UI = 22,
  FONT_SIZE_SMALL = 17,

  BUTTON_W = 360,
  BUTTON_H = 48,
  BUTTON_GAP = 12,

  CHAT_MAX_MESSAGES = 18,

  COLOR_BG = { 0.07, 0.09, 0.14, 1.0 },
  COLOR_PANEL = { 0.12, 0.15, 0.22, 1.0 },
  COLOR_PANEL_BORDER = { 0.25, 0.42, 0.72, 1.0 },
  COLOR_TEXT = { 0.92, 0.94, 0.97, 1.0 },
  COLOR_TEXT_SUB = { 0.74, 0.79, 0.88, 1.0 },
  COLOR_BUTTON = { 0.18, 0.25, 0.39, 1.0 },
  COLOR_BUTTON_HOVER = { 0.24, 0.32, 0.50, 1.0 },
  COLOR_BUTTON_DISABLED = { 0.16, 0.16, 0.18, 1.0 },
  COLOR_DANGER = { 0.65, 0.20, 0.22, 1.0 },
  COLOR_INPUT_BG = { 0.10, 0.12, 0.18, 1.0 }
}

return Constants
