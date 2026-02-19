# SPEC_09_LOCALIZATION_AND_TEXT - i18n and User-Facing Text Rules
Date: 2026-02-11

## Naming Convention
- Authoritative naming/comment rule file: `docs/spec/naming_convention.md`.

## 1. Scope
- This spec governs localization/i18n of user-facing client text.
- This spec does not change protocol `type` strings or server error code identifiers.

## 2. i18n Runtime Contract
- i18n module path:
  - `i18n/i18n.lua`
- Required API:
  - `setLanguage(lang)`
  - `getLanguage()`
  - `t(key, vars?)`
- Fallback chain:
  - current language -> default language (`ko`) -> `[[missing:key]]`
- Interpolation:
  - token syntax `{var}`
  - `vars[var] == nil` keeps token text
  - non-string values are converted with `tostring`

## 3. Locale Files
- Primary locale:
  - `i18n/locales/ko.lua`
- Secondary locale:
  - `i18n/locales/en.lua`
- Locale template for new language onboarding:
  - `i18n/locales/template.lua`
- Current implementation status:
  - `ko` and `en` are both maintained as full UI coverage.
  - fallback remains active for runtime safety (`current -> ko -> missing marker`).

## 4. Translation Boundary Rules
- Must be localized:
  - buttons
  - labels/titles/placeholders
  - status text shown on screen
  - system chat lines visible to users
  - on-screen warning/error text
- Must remain hardcoded (non-localized):
  - protocol `type` strings (`client.*`, `room.*`, `match.*`, etc.)
  - server/client internal keys
  - error code identifiers exchanged over protocol
  - internal-only debug text not rendered to users

## 5. Settings Integration
- `settings.ini` stores language key:
  - `language=ko|en`
- Load path:
  - app startup reads settings
  - calls `I18n.setLanguage(loadedLang)` before scene render
- Save path:
  - settings overlay save writes `display_mode`, `language`, and `nickname`
  - language applies immediately at runtime

## 6. Overlay UX Contract
- Settings overlay uses 2-column row layout:
  - `[label] [interactive control]`
- Row order (top -> bottom):
  1. `display_mode`
  2. `language`
- Dropdown behavior:
  - expanded option panel is opaque (readability first)
  - only one dropdown may remain open at a time
  - clicking outside closes opened dropdown
  - expanded panel is rendered above other overlay controls

## 7. Font + i18n Safety
- Font load failure must not crash localization flow.
- Fallback font is allowed.
- Warning text is localized through i18n keys.

## 8. Debug Helper
- Optional runtime helper:
  - `_G.I18N_DEBUG_DUMP_MISSING()`
- Purpose:
  - print missing localization keys collected during runtime.

## 9. Validation Checklist
1. Change language in settings overlay and save.
2. Verify current scene text refreshes immediately after save (no scene switch required).
3. Check lobby/room-search/waiting-room strings in selected language.
4. Restart client and verify language persistence.
5. Verify protocol `type` strings are unchanged in network flow.
6. Run i18n audit and confirm key parity.

## 10. i18n Tooling Contract
- Audit script:
  - `tools/i18n_audit.js`
- npm command:
  - `npm run i18n:audit`
- Pass condition:
  - all `t("...")` keys used in Lua code exist in both `ko.lua` and `en.lua`.
- CI/review policy:
  - locale key changes must keep audit green before merge.

## 11. New Language Onboarding Flow
1. Copy `i18n/locales/template.lua` to new locale file (example: `ja.lua`).
2. Translate values while keeping key tree unchanged.
3. Register locale in `i18n/i18n.lua` `localeMap`.
4. Add language option to settings overlay dropdown and settings sanitizer map.
5. Run `npm run i18n:audit` and smoke-test UI.

## 12. Change Log
- 2026-02-11:
  - Added locale template file contract (`i18n/locales/template.lua`).
  - Added dropdown UX behavior rules (exclusive open, outside-close, top-layer draw, opaque panel).
  - Added i18n audit tooling requirement (`npm run i18n:audit`).
  - Updated validation to require immediate in-scene language refresh after save.
