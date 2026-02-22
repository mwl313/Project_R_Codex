# SPEC_08_ASSET_AND_POLISHING
Date: 2026-02-10

## 1. Asset Replacement Policy
- All UI/card/background visuals must be replaceable with external assets.
- Code should reference asset paths, not hardcoded pixel art assumptions.
- Resolution changes in assets must not require gameplay logic changes.

## 2. UI Skinning
- Base rectangle UI is allowed.
- Structure should remain swappable to image-based skins later.

## 3. Sound Hook System
- Major gameplay/network lifecycle events have sound hook IDs.
- Sound files live under `assets/sounds`.
- Missing sound files must be no-op (never crash).

### 3.1 Runtime Contract (Implemented)
- Client dispatches hook IDs from major HTTP long-poll/match events.
- Sound lookup order:
  - `assets/sounds/<hookId>.ogg`
  - `assets/sounds/<hookId>.wav`
  - `assets/sounds/<hookId>.mp3`
- Hook playback manager:
  - `managers/sound_manager.lua`

## 4. Effect Layer Policy
- VFX must be separated from game-rule authority.
- Rendering-only effects are client-local and must not alter server decisions.
- Centralized effect runtime manager:
  - `effects/effect_manager.lua`
- Current implemented effect:
  - shockwave pulse visualization with board/canonical coordinate conversion.

## 5. Localization and Font Safety
- User-facing text should come from i18n locale tables.
- Default language: `ko`; secondary language: `en` with fallback chain.
- Primary font:
  - `assets/fonts/MulmaruMono.ttf`
- Font loading failure must:
  - avoid crash
  - fallback to default font
  - surface warning text on UI

## 6. Future Polish Safety
- Presentation polish (SFX/VFX/skin/i18n copy tuning) must not mutate gameplay authority rules.
- Any polish-only change should avoid protocol/type-string changes.

## 7. Change Log
- 2026-02-10:
  - Added effect-layer centralization contract.
  - Added localization/font fallback safety section.
