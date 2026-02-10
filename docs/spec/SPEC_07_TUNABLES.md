# SPEC_07_TUNABLES - Central Constants
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Lua constant modules using this table must follow that document.

## 1. Constant Files
- Server constants live in `rules.ts` or `constants.ts`.
- Client constants live in `config.lua` or `constants.lua`.
- No gameplay number literals outside constant modules.

## 2. World/Display
- `BASE_WORLD_W = 1280`
- `BASE_WORLD_H = 720`
- `DISPLAY_MODE_WINDOWED = "windowed_1280x720"`
- `DISPLAY_MODE_FULLSCREEN = "fullscreen_native"`
- `OVERLAY_PANEL_RATIO = 0.70` (settings and nickname overlays)

## 3. Room/Identity
- `ROOM_CODE_LENGTH = 16`
- `ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"` (excludes `O0I1`)
- `SAVE_IDENTITY = "project_r"`
- `SETTINGS_FILENAME = "settings.ini"`
- Save location root:
  - `love.filesystem.getSaveDirectory()` under `SAVE_IDENTITY`

## 4. Board/Layout
- `BOARD_W = 600`
- `BOARD_H = 600`
- `CARD_UI_MARGIN_TOP = 64`
- `CARD_UI_MARGIN_BOTTOM = 96`
- `CENTER_BUFFER = 19`
- `NO_PLACE_BUFFER = 19` (separate constant for future split)

## 5. Stones and Placement
- `STONE_COUNT_PER_PLAYER = 7`
- `STONE_RADIUS = 14`
- `PLACE_GAP_PX = 5`
- `MIN_PLACE_DISTANCE = STONE_RADIUS + PLACE_GAP_PX`
- `STONE_ADDED_THIS_TURN_MOVABLE = false` (for reinforcement behavior)

## 6. Physics and Turn Settlement
- `PHYSICS_FRICTION = 0.985`
- `PHYSICS_RESTITUTION = 0.92`
- `PHYSICS_LINEAR_DAMPING = 0.995`
- `MAX_SHOT_POWER = 900`
- `POWER_PER_PIXEL = 4.0`
- `STOP_SPEED_THRESHOLD = 6.0`
- `STOP_FRAMES_REQUIRED = 20`

## 7. Phase Timers and Turn Limits
- `PLACEMENT_REVEAL_SEC = 5`
- `CARD_PICK_SEC = 15`
- `TURN_TIME_LIMIT_SEC = 30`
- `MAX_TURN_COUNT = 60`

## 8. Card Draft and Effects
- `CARD_POOL = ["reinforcement","shockwave","invincible","rockfall","agile"]`
- `HOST_DEAL_COUNT = 2`
- `HOST_PICK_COUNT = 1`
- `GUEST_DEAL_COUNT = 3`
- `GUEST_PICK_COUNT = 2`
- `AUTO_PICK_POLICY = "front_first"`
- `CARD_USE_MAX_PER_TURN = 1`
- `CARD_USE_STAGE = "CARD_ACTION"` (pre-shot stage)
- `SHOTS_PER_TURN_BASE = 1`
- `AGILE_EXTRA_SHOTS = 1`
- `INVINCIBLE_TURNS = 1`
- `SHOCKWAVE_RANGE_MULTIPLIER = 4.0`
- `SHOCKWAVE_STRENGTH = 200`
- `ROCK_OBSTACLE_WIDTH = 100`
- `ROCK_OBSTACLE_HEIGHT = 50`
- `ROCK_OBSTACLE_MARGIN = 5`

## 9. Chat and Anti-Spam
- `CHAT_MAX_LENGTH = 120`
- `CHAT_RATE_WINDOW_SEC = 10`
- `CHAT_RATE_MAX_MSG = 6`
- `CHAT_RATE_BURST = 2`

## 10. Snapshot Reconciliation
- `SNAPSHOT_AUTHORITY = "host"`
- `SNAPSHOT_PER_TURN = 1`
- `SNAPSHOT_POS_EPSILON = 2.0`
- `SNAPSHOT_VEL_EPSILON = 2.0`
- `SNAPSHOT_APPLY_MODE = "immediate"` (MVP default)

## 11. Persistence Settings Contract
### 11.1 Scope
- Persistent storage includes nickname and environment settings.
- Storage backend uses LÖVE filesystem identity space.

### 11.2 Identity and save location
- `love.filesystem.setIdentity` is fixed to `project_r`.
- Settings file name is fixed to `settings.ini`.
- Physical path is under `love.filesystem.getSaveDirectory()`.
- Debug guidance:
  - expose/log `getSaveDirectory()` path when needed.

### 11.3 File format
- UTF-8 text.
- Line format: `key=value`.
- Comment line: `# ...`
- Unknown keys:
  - ignored on load.
- Invalid lines:
  - skipped safely (no crash).

### 11.4 Key template and defaults
```ini
# ProjectR settings.ini (UTF-8)
nickname=Player
display_mode=windowed_1280x720
window_width=1280
window_height=720
fullscreen=true
fullscreen_mode=desktop
# future extension examples:
# master_volume=1.0
# sensitivity=1.0
```

### 11.5 Display rules
- Windowed mode: fixed `1280x720`.
- Fullscreen mode: current monitor/native desktop resolution.

### 11.6 Save/load/apply timing
- Load:
  - once at boot before first scene render.
- Apply:
  - immediately after parse at boot.
  - immediately after user confirms settings/nickname changes.
- Save:
  - explicit apply/save action is baseline.
  - optional autosave on quit is allowed.

### 11.7 Overlay integration
- Settings and nickname changes are overlays (not scenes).
- Overlay panel size is 70% of viewport/world-scaled screen.
- Save button flow:
  1. validate fields
  2. write `settings.ini`
  3. apply runtime changes
  4. show success/failure status

### 11.8 Extension rules
- Future keys (volume/sensitivity) may be added.
- New keys must keep:
  - backward compatibility
  - unknown-key-ignore behavior
  - default values in this spec.

### 11.9 Cross-reference
- Overlay and coordinate behavior:
  - `docs/spec/SPEC_02_COORDINATES_AND_RENDER.md`
- MVP overview:
  - `docs/spec/SPEC_00_OVERVIEW.md`
