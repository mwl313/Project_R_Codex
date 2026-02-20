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
  -- Shared gameplay rules are loaded from a single SSOT JSON file
  -- so client/server tunables do not drift over time.
}

local Json = require("utils.json")

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function loadSharedRules()
  if not love or not love.filesystem then
    return {}
  end
  local isReadOk, rawOrError = pcall(love.filesystem.read, "shared/gameplay_rules.json")
  if not isReadOk or type(rawOrError) ~= "string" or rawOrError == "" then
    return {}
  end
  local isDecoded, parsed = pcall(Json.decode, rawOrError)
  if not isDecoded or type(parsed) ~= "table" then
    return {}
  end
  return parsed
end

local SHARED_RULES = loadSharedRules()

local function readNumberRule(key, fallback)
  local value = SHARED_RULES[key]
  if isFiniteNumber(value) then
    return value
  end
  return fallback
end

local function readStringRule(key, fallback)
  local value = SHARED_RULES[key]
  if type(value) == "string" and value ~= "" then
    return value
  end
  return fallback
end

Constants = {
  BASE_WORLD_W = 1280,
  BASE_WORLD_H = 720,

  SERVER_HTTP_BASE_URL = "http://127.0.0.1:8787",
  SERVER_WS_BASE_URL = "ws://127.0.0.1:8787",

  SAVE_IDENTITY = "project_r",
  SETTINGS_FILENAME = "settings.ini",

  DISPLAY_MODE_WINDOWED = "windowed_1280x720",
  DISPLAY_MODE_FULLSCREEN = "fullscreen_native",
  WINDOWED_W = 1280,
  WINDOWED_H = 720,
  OVERLAY_PANEL_RATIO = 0.70,
  OVERLAY_ENTER_SEC = 0.28,
  OVERLAY_EXIT_SEC = 0.22,
  DROPDOWN_OPEN_SEC = 0.16,
  DROPDOWN_CLOSE_SEC = 0.13,

  PHASE_WAITING = "WAITING",
  PHASE_TURN_ORDER = "TURN_ORDER",
  PHASE_PLACEMENT_PRIVATE = "PLACEMENT_PRIVATE",
  PHASE_PLACEMENT_REVEAL = "PLACEMENT_REVEAL",
  PHASE_CARD_SELECT = "CARD_SELECT",
  PHASE_PLAYING = "PLAYING",
  PHASE_RESULT = "RESULT",

  RULES_VERSION = readNumberRule("RULES_VERSION", 1),
  ROOM_CODE_LENGTH = readNumberRule("ROOM_CODE_LENGTH", 16),
  ROOM_CODE_ALPHABET = readStringRule("ROOM_CODE_ALPHABET", "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"),
  NICKNAME_MAX_LENGTH = readNumberRule("NICKNAME_MAX_LENGTH", 20),

  BOARD_W = readNumberRule("BOARD_W", 600),
  BOARD_H = readNumberRule("BOARD_H", 600),
  STONE_COUNT_PER_PLAYER = readNumberRule("STONE_COUNT_PER_PLAYER", 7),
  STONE_RADIUS = readNumberRule("STONE_RADIUS", 14),
  PLACE_GAP_PX = readNumberRule("PLACE_GAP_PX", 5),
  NO_PLACE_BUFFER = readNumberRule("NO_PLACE_BUFFER", 19),
  CARD_PICK_SEC = readNumberRule("CARD_PICK_SEC", 15),
  TURN_TIME_LIMIT_SEC = readNumberRule("TURN_TIME_LIMIT_SEC", 30),
  SNAPSHOT_TIMEOUT_SEC = readNumberRule("SNAPSHOT_TIMEOUT_SEC", 8),
  HOST_PICK_COUNT = readNumberRule("HOST_PICK_COUNT", 1),
  GUEST_PICK_COUNT = readNumberRule("GUEST_PICK_COUNT", 2),
  MAX_SHOT_POWER = readNumberRule("MAX_SHOT_POWER", 900),
  POWER_PER_PIXEL = readNumberRule("POWER_PER_PIXEL", 4.0),
  -- `rockfall` (낙석) 밸런스/배치 상수:
  -- 장애물 기본 크기와 보드 경계 여유치.
  ROCK_OBSTACLE_WIDTH = readNumberRule("ROCK_OBSTACLE_WIDTH", 100),
  ROCK_OBSTACLE_HEIGHT = readNumberRule("ROCK_OBSTACLE_HEIGHT", 50),
  ROCK_OBSTACLE_MARGIN = readNumberRule("ROCK_OBSTACLE_MARGIN", 5),
  -- `shockwave` (충격파) 밸런스 상수:
  -- 실제 반경 = STONE_RADIUS * SHOCKWAVE_RANGE_MULTIPLIER
  -- 현재 설계는 거리 감쇠 없이 SHOCKWAVE_STRENGTH를 평탄 적용.
  SHOCKWAVE_RANGE_MULTIPLIER = readNumberRule("SHOCKWAVE_RANGE_MULTIPLIER", 4.0),
  SHOCKWAVE_STRENGTH = readNumberRule("SHOCKWAVE_STRENGTH", 200),
  SHOT_SPEED_SCALE = readNumberRule("SHOT_SPEED_SCALE", 0.60),
  PHYSICS_DAMPING_PER_SEC = readNumberRule("PHYSICS_DAMPING_PER_SEC", 2.40),
  PHYSICS_RESTITUTION = readNumberRule("PHYSICS_RESTITUTION", 0.86),
  PHYSICS_STOP_SPEED = readNumberRule("PHYSICS_STOP_SPEED", 12),
  PHYSICS_FIXED_STEP_SEC = readNumberRule("PHYSICS_FIXED_STEP_SEC", 0.016),
  PHYSICS_MAX_SIM_SEC = readNumberRule("PHYSICS_MAX_SIM_SEC", 6.0),

  -- 프로젝트 공용 UI 폰트(영문/한글 렌더링 공용).
  FONT_KR_REGULAR_PATH = "assets/fonts/MulmaruMono.ttf",
  FONT_SIZE_TITLE = 34,
  FONT_SIZE_UI = 22,
  FONT_SIZE_SMALL = 17,
  COIN_TOSS_TOTAL_SEC = 2.2,
  COIN_TOSS_FLIP_SEC = 1.4,
  COIN_TOSS_PULSE_AMPLITUDE = 0.06,
  COIN_TOSS_START_DELAY_SEC = 1.0,
  COIN_TOSS_POST_HOLD_SEC = 2.0,

  CARD_W = 118,
  CARD_H = 166,
  CARD_HAND_OPEN_SEC = 0.15,
  CARD_HAND_CLOSE_SEC = 0.15,
  CARD_HAND_CLOSE_DELAY_SEC = 0.12,
  CARD_HAND_PEEK_HEIGHT = 30,
  CARD_HAND_OPEN_RISE_PX = 132,
  CARD_HAND_OPEN_SPACING = 132,
  CARD_HAND_CLOSED_SPACING = 30,
  CARD_HAND_OPEN_ARC_PX = 10,
  CARD_HAND_HOVER_LIFT_PX = 14,
  CARD_HAND_HOVER_SCALE = 0.06,
  CARD_HAND_DRAG_SCALE = 0.08,
  CARD_HAND_RETURN_SEC = 0.20,
  CARD_HAND_SNAPBACK_CLOSE_HOLD_SEC = 0.15,
  CARD_HAND_GLOW_ALPHA = 0.30,
  CARD_DROP_ZONE_SIZE = 160,
  CARD_DROP_ZONE_FLASH_PERIOD_SEC = 0.80,
  CARD_DROP_ZONE_ALPHA_MIN = 0.15,
  CARD_DROP_ZONE_ALPHA_MAX = 0.35,
  CARD_LOCAL_FAN_SPACING = 132,
  CARD_OPPONENT_FAN_SPACING = 86,
  CARD_DECK_ENTER_SEC = 0.60,
  CARD_SHUFFLE_SEC = 0.60,
  CARD_DEAL_SEC = 0.46,
  CARD_DEAL_STAGGER_SEC = 0.14,
  CARD_FLIP_SEC = 0.44,
  CARD_FLIP_STAGGER_SEC = 0.12,
  CARD_CLEANUP_SEC = 1.24,
  CARD_HOVER_LIFT_PX = 16,
  CARD_HOVER_SCALE = 0.06,
  CARD_GLOW_ALPHA = 0.28,
  CARD_BORDER_THICKNESS = 3,

  BUTTON_W = 360,
  BUTTON_H = 48,
  BUTTON_GAP = 12,

  CHAT_MAX_MESSAGES = 18,
  CHAT_MAX_LENGTH = readNumberRule("CHAT_MAX_LENGTH", 100),
  CHAT_RATE_WINDOW_SEC = readNumberRule("CHAT_RATE_WINDOW_SEC", 10),
  CHAT_RATE_MAX_MSG = readNumberRule("CHAT_RATE_MAX_MSG", 6),
  CHAT_RATE_BURST = readNumberRule("CHAT_RATE_BURST", 2),
  INGAME_CHAT_OPEN_SEC = 0.20,
  INGAME_CHAT_MAX_MESSAGES = 80,
  INGAME_CHAT_MARGIN_RIGHT = 18,
  INGAME_CHAT_MARGIN_BOTTOM = 16,
  INGAME_CHAT_BAR_W = 236,
  INGAME_CHAT_BAR_H = 42,
  INGAME_CHAT_PANEL_W = 438,
  INGAME_CHAT_PANEL_H = 268,
  INGAME_CHAT_SCROLL_LINES_PER_TICK = 3,

  COLOR_BG = { 0.07, 0.09, 0.14, 1.0 },
  COLOR_PANEL = { 0.12, 0.15, 0.22, 1.0 },
  COLOR_PANEL_BORDER = { 0.25, 0.42, 0.72, 1.0 },
  COLOR_TEXT = { 0.92, 0.94, 0.97, 1.0 },
  COLOR_TEXT_SUB = { 0.74, 0.79, 0.88, 1.0 },
  COLOR_BUTTON = { 0.18, 0.25, 0.39, 1.0 },
  COLOR_BUTTON_HOVER = { 0.24, 0.32, 0.50, 1.0 },
  COLOR_BUTTON_SELECTED = { 0.20, 0.44, 0.34, 1.0 },
  COLOR_BUTTON_SELECTED_ALT = { 0.46, 0.36, 0.18, 1.0 },
  COLOR_BUTTON_DISABLED = { 0.16, 0.16, 0.18, 1.0 },
  COLOR_DANGER = { 0.65, 0.20, 0.22, 1.0 },
  COLOR_INPUT_BG = { 0.10, 0.12, 0.18, 1.0 },
  COLOR_OVERLAY_DIM = { 0.0, 0.0, 0.0, 0.56 },
  COLOR_STONE_HOST = { 0.25, 0.62, 0.95, 1.0 },
  COLOR_STONE_GUEST = { 0.95, 0.55, 0.25, 1.0 }
}

Constants.MIN_PLACE_DISTANCE = Constants.STONE_RADIUS + Constants.PLACE_GAP_PX

return Constants
