# SPEC_10_SHARED_RULES_WORKFLOW - Gameplay/Card SSOT Operations
Date: 2026-02-11

## 1. Purpose
- Define 운영 규칙 for single-source gameplay/card tuning data.
- Prevent client/server drift during balance patches.

## 2. SSOT Files
- Common gameplay tunables:
  - `shared/gameplay_rules.json`
- Card-specific tunables:
  - `shared/card_rules.json`

## 3. Runtime Readers
- Client:
  - `constants.lua` reads `shared/gameplay_rules.json`
  - `shared/card_rules.lua` reads `shared/card_rules.json`
- Server:
  - `src/rules.ts` reads `shared/gameplay_rules.json`
  - `src/card_rules.ts` reads `shared/card_rules.json`

## 4. Ownership Boundary
- JSON owns:
  - numeric tunables
  - boolean on/off flags
  - per-card constraints
- Code owns:
  - turn/phase transition logic
  - protocol schema/types
  - card behavior flow (spawn/apply/resolve order)

## 5. Edit Workflow (Required)
1. Edit JSON value(s) only (prefer no key rename).
2. Update adjacent guide in same commit:
   - `shared/gameplay_rules.README.md`
   - `shared/card_rules.README.md`
3. Run validation:
   - server type check (`npm run typecheck`)
   - local gameplay smoke test (2 clients)
4. If key add/remove/rename is unavoidable:
   - update all readers (Lua/TS)
   - update this spec and related specs (`SPEC_07`, `SPEC_06`)

## 6. Versioning Contract
- `RULES_VERSION` in `shared/gameplay_rules.json` is network-facing compatibility version.
- Worker includes `rulesVersion` in HTTP create/join and poll event payloads.
- Client warns on mismatch (UI warning), but should continue to run safely when possible.

## 7. Safety Rules
- Reader parse failure must fallback to internal defaults (no crash).
- Unknown keys are ignored safely by readers.
- Balance changes must not rename protocol message `type`.

## 8. Performance Note
- JSON rule files are loaded once per runtime init path.
- No per-frame JSON parsing is allowed.

## 9. Cross-Reference
- Protocol contract:
  - `docs/spec/SPEC_03_PROTOCOL.md`
- Tunables catalog:
  - `docs/spec/SPEC_07_TUNABLES.md`
- Card behavior:
  - `docs/spec/SPEC_06_CARDS_ABILITIES.md`

