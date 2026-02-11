# SPEC_09_LOCALIZATION_AND_TEXT - i18n and User-Facing Text Rules
Date: 2026-02-10

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
- `en` may be partial and may rely on `ko` fallback.

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
2. Restart client and verify language persistence.
3. Check lobby/room-search/waiting-room strings in selected language.
4. Verify protocol `type` strings are unchanged in network flow.
5. Run missing-key dump and confirm no critical UI key gaps.

