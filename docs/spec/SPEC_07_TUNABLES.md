# SPEC_07_TUNABLES - Central Constants and Persistence Keys
Date: 2026-02-11

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- Lua constant modules using this table must follow that document.

## 1. Constant Files
- SSOT data sources:
  - `shared/gameplay_rules.json` (phase/board/physics/chat/common gameplay tunables)
  - `shared/card_rules.json` (card-specific tunables/enable flags)
- Runtime adapters:
  - Server common rules loader: `src/rules.ts`
  - Server card rules loader: `src/card_rules.ts`
  - Client common rules loader: `constants.lua`
  - Client card rules loader: `shared/card_rules.lua`
- Rule:
  - gameplay 숫자 상수는 JSON SSOT에서 관리하고, 코드에서는 로더/검증/폴백만 담당한다.
  - 임시 하드코딩 값은 허용하지 않는다(예외 필요 시 change log에 근거 기록).

## 2. World / Display / Overlay
- `BASE_WORLD_W = 1280`
- `BASE_WORLD_H = 720`
- `DISPLAY_MODE_WINDOWED = "windowed_1280x720"`
- `DISPLAY_MODE_FULLSCREEN = "fullscreen_native"`
- `WINDOWED_W = 1280`
- `WINDOWED_H = 720`
- `OVERLAY_PANEL_RATIO = 0.70`

## 3. Room / Identity / Language
- `ROOM_CODE_LENGTH = 16`
- `ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"` (excludes `O0I1`)
- `SAVE_IDENTITY = "project_r"`
- `SETTINGS_FILENAME = "settings.ini"`
- `language` allowed values: `ko`, `en`
- Save location root:
  - `love.filesystem.getSaveDirectory()` under `SAVE_IDENTITY`

## 4. Board / Placement
- `BOARD_W = 600`
- `BOARD_H = 600`
- `STONE_COUNT_PER_PLAYER = 7`
- `STONE_RADIUS = 14`
- `PLACE_GAP_PX = 5`
- `MIN_PLACE_DISTANCE = STONE_RADIUS + PLACE_GAP_PX (=19)`
- `NO_PLACE_BUFFER = 19`
- Rockfall obstacle footprint:
  - `ROCK_OBSTACLE_WIDTH = 100`
  - `ROCK_OBSTACLE_HEIGHT = 50`
  - `ROCK_OBSTACLE_MARGIN = 5`

## 5. Phase / Turn Timers
- `PLACEMENT_REVEAL_SEC = 5`
- `CARD_PICK_SEC = 15`
- `TURN_TIME_LIMIT_SEC = 30`

## 6. Shot / Physics (Current Implementation)
- `MAX_SHOT_POWER = 900`
- `POWER_PER_PIXEL = 4.0`
- `SHOT_SPEED_SCALE = 0.60`
- `PHYSICS_DAMPING_PER_SEC = 2.40`
- `PHYSICS_RESTITUTION = 0.86`
- `PHYSICS_STOP_SPEED = 12`
- `PHYSICS_FIXED_STEP_SEC = 0.016`
- `PHYSICS_MAX_SIM_SEC = 6.0`

## 7. Card Draft / Effect Tunables
- `CARD_POOL = ["reinforcement", "shockwave", "invincible", "rockfall", "agile"]`
- Host/Guest card draft:
  - `HOST_DEAL_COUNT = 2`
  - `HOST_PICK_COUNT = 1`
  - `GUEST_DEAL_COUNT = 3`
  - `GUEST_PICK_COUNT = 2`
- Auto-pick policy: front-first
- Turn card constraints:
  - card use max 1 per turn
  - use stage: pre-shot (`CARD_ACTION`)
- Card-specific JSON source:
  - `shared/card_rules.json`
- Card tunables currently centralized in JSON:
  - `reinforcement.min_place_distance`
  - `reinforcement.lock_spawned_stone_for_turn`
  - `shockwave.radius_multiplier`
  - `shockwave.strength`
  - `shockwave.exclude_source_stone`
  - `shockwave.ignore_invincible_targets`
  - `invincible.protect_after_turn_offset`
  - `rockfall.width`, `rockfall.height`, `rockfall.margin`
  - `agile.shot_budget`
- Behavior logic separation:
  - JSON controls numeric constraints/toggles.
  - Ability action flow remains in `abilities.lua` and `src/abilities.ts`.

## 8. Chat Anti-Spam
- `CHAT_MAX_LENGTH = 120`
- `CHAT_RATE_WINDOW_SEC = 10`
- `CHAT_RATE_MAX_MSG = 6`
- `CHAT_RATE_BURST = 2`

## 9. Font and Text
- Primary UI font path:
  - `FONT_KR_REGULAR_PATH = "assets/fonts/MulmaruMono.ttf"`
- Font sizes:
  - `FONT_SIZE_TITLE = 34`
  - `FONT_SIZE_UI = 22`
  - `FONT_SIZE_SMALL = 17`
- Font load failure behavior:
  - fallback to default font
  - user-visible warning text via i18n

## 10. Settings.ini Contract
### 10.1 File format
- UTF-8 text
- line format: `key=value`
- comments: `# ...`
- unknown keys ignored safely
- invalid lines skipped safely

### 10.2 Current keys
```ini
# ProjectR settings.ini (UTF-8)
nickname=Player
display_mode=windowed_1280x720
language=ko
window_width=1280
window_height=720
fullscreen=false
fullscreen_mode=windowed
```

### 10.3 Apply timing
- Load once at boot before first scene draw
- Apply immediately after save on settings overlay
- Persisted fields used at runtime:
  - nickname
  - display mode
  - language

## 11. Cross-Reference
- Coordinates/render:
  - `docs/spec/SPEC_02_COORDINATES_AND_RENDER.md`
- Cards:
  - `docs/spec/SPEC_06_CARDS_ABILITIES.md`
- Localization:
  - `docs/spec/SPEC_09_LOCALIZATION_AND_TEXT.md`
- SSOT rule files guide:
  - `shared/gameplay_rules.README.md`
  - `shared/card_rules.README.md`

## 12. Change Log
- 2026-02-10:
  - Replaced outdated physics constants with actual implementation constants.
  - Added language persistence key and allowed values.
  - Updated font path to `assets/fonts/MulmaruMono.ttf`.
- 2026-02-11:
  - Updated constant ownership to JSON SSOT model (`gameplay_rules.json`, `card_rules.json`).
  - Added server/client rule-loader modules and card-rule adapter references.
  - Removed outdated note about agile/invincible hardcoded tunables.
