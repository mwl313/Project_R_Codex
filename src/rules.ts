export const DEFAULT_PHASE = "WAITING";
export const PHASE_WAITING = "WAITING";
export const PHASE_TURN_ORDER = "TURN_ORDER";
export const PHASE_PLACEMENT_PRIVATE = "PLACEMENT_PRIVATE";
export const PHASE_PLACEMENT_REVEAL = "PLACEMENT_REVEAL";
export const PHASE_CARD_SELECT = "CARD_SELECT";
export const PHASE_PLAYING = "PLAYING";
export const PHASE_RESULT = "RESULT";

export const ROOM_CODE_LENGTH = 16;
export const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export const NICKNAME_MAX_LENGTH = 20;

export const BOARD_W = 600;
export const BOARD_H = 600;
export const STONE_COUNT_PER_PLAYER = 7;
export const STONE_RADIUS = 14;
export const PLACE_GAP_PX = 5;
export const MIN_PLACE_DISTANCE = STONE_RADIUS + PLACE_GAP_PX;
export const NO_PLACE_BUFFER = 19;
export const PLACEMENT_REVEAL_SEC = 5;
export const CARD_PICK_SEC = 15;
export const TURN_TIME_LIMIT_SEC = 30;

export const CARD_POOL = ["reinforcement", "shockwave", "invincible", "rockfall", "agile"] as const;
export type CardId = (typeof CARD_POOL)[number];
export const HOST_DEAL_COUNT = 2;
export const HOST_PICK_COUNT = 1;
export const GUEST_DEAL_COUNT = 3;
export const GUEST_PICK_COUNT = 2;

// Base shot input tuning (all cards use this baseline).
export const MAX_SHOT_POWER = 900;
export const POWER_PER_PIXEL = 4.0;

// `rockfall` obstacle footprint/boundary allowance.
export const ROCK_OBSTACLE_WIDTH = 100;
export const ROCK_OBSTACLE_HEIGHT = 50;
export const ROCK_OBSTACLE_MARGIN = 5;

// `shockwave` tuning.
// - actual radius = STONE_RADIUS * SHOCKWAVE_RANGE_MULTIPLIER
// - SHOCKWAVE_STRENGTH is flat impulse (distance falloff disabled in current design)
export const SHOCKWAVE_RANGE_MULTIPLIER = 4.0;
export const SHOCKWAVE_STRENGTH = 200;

export const CHAT_MAX_LENGTH = 120;
export const CHAT_RATE_WINDOW_SEC = 10;
export const CHAT_RATE_MAX_MSG = 6;
export const CHAT_RATE_BURST = 2;

export const CHAT_ALLOWED_PHASES = new Set<string>([
  PHASE_WAITING,
  PHASE_TURN_ORDER,
  PHASE_PLACEMENT_PRIVATE,
  PHASE_PLACEMENT_REVEAL,
  PHASE_CARD_SELECT,
  PHASE_PLAYING,
  PHASE_RESULT
]);
