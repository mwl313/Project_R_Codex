# SPEC_01_OVERVIEW - Definitions and State Model
Date: 2026-02-09

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.
- All Lua naming and file-header comment rules must follow that document.

## 1. Core Definitions
- `Host`: room creator, fixed snapshot authority.
- `Guest`: room joiner.
- `Room`: 1v1 game session with a 16-character room code.
- `Canonical Board Space`: server-authoritative board coordinates (see `SPEC_02`).
- `Phase`: server-authoritative game progress step.

## 2. Authoritative Responsibilities
- Server (Worker + DO) is authoritative for:
  - room membership and token auth
  - phase transitions
  - all phase/turn timers
  - card draft/pick validation and timeout auto-pick
  - leave/disconnect/surrender resolution
  - result (`p1_win`, `p2_win`, `draw`)
- Client is responsible for:
  - UI rendering/input
  - local physics simulation
  - sending requests/events
  - applying snapshot reconciliation

## 3. Mandatory Phase Order
1. `WAITING`
2. `TURN_ORDER`
3. `PLACEMENT_PRIVATE`
4. `PLACEMENT_REVEAL`
5. `CARD_SELECT`
6. `PLAYING`
7. `RESULT`

## 4. State Machine Rules
- One-way forward flow for gameplay phases.
- No backward transition from gameplay phases to prior gameplay phases.
- Any leave/disconnect/surrender during gameplay forces `RESULT`.
- Waiting-room leave rules are separate and defined in `SPEC_04` and `SPEC_05`.

## 5. Gameplay Baselines
- Board size: `600x600`.
- Base world resolution: `1280x720`.
- Stones per player at match start: `7`.
- Turn limit: `30 seconds`.
- Reveal duration: `5 seconds`.
- Base shots per turn: `1` (extendable by card effects).
- Card use count per turn: max `1` (pre-shot stage).

## 6. Card Pool (Light Version, fixed for MVP)
- `reinforcement` (신병)
- `shockwave` (충격파)
- `invincible` (무적)
- `rockfall` (낙석)
- `agile` (날렵함)

## 7. Card Distribution Rule (must follow exactly)
- Host receives 2 cards, picks 1.
- Guest receives 3 cards, picks 2.
- Cards are unique globally in a round (no overlap between players).
- On pick timeout: auto-pick from front of dealt list.

## 8. Persistence and Overlay Rules
- Nickname and settings persist in `settings.ini` under identity `project_r`.
- Settings/nickname changes must be handled as overlays (not scene transitions).
- Overlay panel ratio is fixed at 70% of viewport/world-scaled screen.

## 9. Definition of Done (MVP)
- With local worker + two clients:
  1. create/join room
  2. waiting-room chat
  3. complete game flow to result
  4. rematch/lobby return and leave handling
- No crash in end-to-end run.

## 10. Change Log
- 2026-02-09:
  - Resolved spec conflict: reveal duration updated from `10 seconds` to `5 seconds` to match current gameplay rules and implementation.
