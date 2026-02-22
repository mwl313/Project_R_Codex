# SPEC_00_OVERVIEW - ProjectR MVP Guardrails
Date: 2026-02-10

## 1. Goal
- Build a fully playable 2-player MVP flow:
  `MATCHING -> WAITING -> TURN_ORDER -> PLACEMENT -> REVEAL(5s) -> CARD_SELECT -> PLAYING(30s turn limit) -> RESULT -> REMATCH/LOBBY`.
- Stack is fixed:
  - Client: LÖVE 11.x (Lua)
  - Server: Cloudflare Workers + Durable Objects (TypeScript)
  - Transport: HTTP (`/room/create`, `/room/join`, `/room/send`, `/room/poll` long-poll)

## 2. Non-Negotiable Rules
- No implementation code before spec approval.
- Do not break already-working behavior by refactor/simplification.
- Network and IO must be non-blocking on the client main thread.
- Server authoritative scope must include phase, timer, result, disconnect/leave handling.
- All tuning values must be centralized constants.
## Guardrails (Do Not Change)

- **Do not rename protocol `type` strings** (e.g., `room.join`, `chat.send`, `match.*`). They are code-facing identifiers.
- **Do not rename constant keys / config keys / file or module names** referenced by code. Only edit prose.
- Reordering sections is allowed, but **do not break cross-references/links** without updating them.


## 3. MVP Scope
- Lobby keeps existing menu and adds `싱글플레이어` button (placeholder only).
- Settings and nickname change are overlays (not scenes), each with panel size = 70% of current scaled screen.
- Settings overlay uses row layout:
  - `[항목 설명] [변경 가능한 드롭다운]`
  - order: `디스플레이 모드` -> `언어 설정`
- Nickname and settings persist to `settings.ini` under identity `project_r`.
- Fixed world coordinate system: `1280x720`; input must use screen-to-world transform.
- Room code: 16 characters, server generated.
- Board: `600x600`, centered.
- Players always see "my side at bottom"; one player is rendered/input-flipped vertically.
- Chat is available in waiting room and during game, with server-side spam limiting.
- Card use is capped at one per turn and resolved before shot step.
- UI text is localized via i18n (`ko` default, `en` secondary fallback).

## 4. Out of Scope for This MVP
- Single-player gameplay implementation.
- Ranking, replay, spectator mode.
- Advanced anti-cheat beyond host snapshot validation and normalization.

## 5. Naming Rule (Authoritative)
- Authoritative naming document exists at:
  - `docs/spec/naming_convention.md`
- This document has priority for all Lua-side naming/comment rules.
- Mandatory Lua rules from that document:
  - variables/functions: `camelCase`
  - module tables: `PascalCase`
  - constants: `UPPER_SNAKE_CASE`
  - booleans prefix: `is`, `has`, `can`, `should`
  - top-of-file module comment block: required
- Additional cross-system protocol rule remains:
  - message types use dot namespace (`room.state`, `client.chat.send`)

## 6. Deliverable Rule for This Turn
- Phase 0 only: finalize `SPEC_*.md`.
- Implementation starts only after explicit user approval.

## 7. Change Log
- 2026-02-10:
  - Added settings overlay row-order contract (`display -> language`).
  - Added i18n scope (`ko` default + `en` fallback).
