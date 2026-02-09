# SPEC_02_COORDINATES_AND_RENDER - World/Board Transform Contract
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- All Lua naming and file-header comment rules must follow that document.

## 1. World Coordinate System (UI Space)
- Base world size:
  - `BASE_WORLD_W = 1280`
  - `BASE_WORLD_H = 720`
- All scene and overlay layout logic uses world coordinates.
- Display mode changes do not change world coordinate logic.

## 2. Screen Scaling and Letterbox
- Use uniform scale:
  - `scale = min(screenW / BASE_WORLD_W, screenH / BASE_WORLD_H)`
- Offsets:
  - `offsetX = (screenW - BASE_WORLD_W * scale) / 2`
  - `offsetY = (screenH - BASE_WORLD_H * scale) / 2`
- Conversion:
  - `worldX = (screenX - offsetX) / scale`
  - `worldY = (screenY - offsetY) / scale`
- Every mouse/touch hit test must use converted world coordinates.

## 3. Board Geometry
- `BOARD_W = 600`, `BOARD_H = 600`
- Board rectangle in world space:
  - `boardX = (BASE_WORLD_W - BOARD_W) / 2`
  - `boardY = (BASE_WORLD_H - BOARD_H) / 2`
- Card UI top/bottom margins are constants and must not cover board interaction zone.

## 4. Canonical Board Space (Server Contract)
- Canonical board coordinates are shared across clients and server.
- Ranges:
  - `x in [0, BOARD_W]`
  - `y in [0, BOARD_H]`
- Canonical side ownership:
  - Host side is lower half.
  - Guest side is upper half.

## 5. Local View Flip Rule
- UX rule: each player always sees own side at bottom.
- Host local view:
  - local == canonical.
- Guest local view:
  - `localX = canonicalX`
  - `localY = BOARD_H - canonicalY`
- Reverse conversion for guest input:
  - `canonicalX = localX`
  - `canonicalY = BOARD_H - localY`

## 6. Vector/Velocity Transform
- Guest conversion between local and canonical flips Y sign:
  - `canonicalVx = localVx`
  - `canonicalVy = -localVy`

## 7. Placement Zone Constraints
- Center line: `centerY = BOARD_H / 2`
- No-place strip width constant: `NO_PLACE_BUFFER`
- Host valid canonical placement:
  - `y >= centerY + NO_PLACE_BUFFER`
- Guest valid canonical placement:
  - `y <= centerY - NO_PLACE_BUFFER`
- Minimum pairwise distance:
  - `MIN_PLACE_DISTANCE = STONE_RADIUS + PLACE_GAP_PX`

## 8. Overlay/Input Rules
- Settings and nickname UIs are overlays, not scenes.
- Overlay panel size is 70% of current scaled screen.
- Overlay and gameplay input share same world-space hit-test path.
