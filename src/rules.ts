export const DEFAULT_PHASE = "WAITING";

export const ROOM_CODE_LENGTH = 16;
export const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export const NICKNAME_MAX_LENGTH = 20;

export const CHAT_MAX_LENGTH = 120;
export const CHAT_RATE_WINDOW_SEC = 10;
export const CHAT_RATE_MAX_MSG = 12;
export const CHAT_RATE_BURST = 6;

export const CHAT_ALLOWED_PHASES = new Set<string>(["WAITING", "PLAYING"]);
