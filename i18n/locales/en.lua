--[[
파일명: en.lua
모듈명: LocaleEn

역할:
- 영어 UI 문자열 리소스를 제공한다.
- 일부 키는 의도적으로 ko fallback을 사용한다.

외부에서 사용 가능한 함수:
- LocaleEn 테이블 참조
]]

local LocaleEn = {
  common = {
    on = "ON",
    off = "OFF",
    unknown = "unknown",
    yes = "Y",
    no = "N",
    role = {
      host = "host",
      guest = "guest"
    },
    button = {
      save = "Save",
      cancel = "Cancel",
      copy = "Copy",
      send = "Send",
      join = "Join",
      back_to_lobby = "Lobby",
      leave = "Leave",
      start_game = "Start",
      submit_placement = "Submit Placement",
      confirm_selection = "Confirm",
      surrender = "Surrender",
      rematch = "Rematch"
    }
  },
  font = {
    warning = {
      load_failed = "Font load failed ({path}): {error}. Falling back to default font."
    }
  },
  app = {
    ui = {
      ws_url_missing = "WS URL is missing.",
      response_parse_failed = "Failed to parse response.",
      request_failed = "Request failed: {reason}",
      ws_message_parse_failed = "Failed to parse WS message.",
      rules_version_mismatch = "Rules version mismatch: client {clientVersion} / server {serverVersion}"
    },
    settings = {
      load_failed_default = "Failed to load settings.ini, using defaults: {error}",
      apply_failed_windowed = "Failed to apply display mode, using windowed mode: {error}",
      save_failed = "Failed to save settings.ini: {error}",
      apply_warning = "Display mode warning: {error}"
    }
  },
  lobby = {
    title = "ProjectR Lobby",
    current_nickname = "Nickname: {nickname}",
    menu = {
      single_player = "Single Player",
      create_room = "Create Room",
      search_room = "Find Room",
      change_nickname = "Change Nickname",
      settings = "Settings",
      guide = "Guide",
      skin = "Skin",
      credits = "Credits",
      quit = "Quit"
    },
    status = {
      enter_single_dummy = "Entering single dummy test mode.",
      creating_room = "Creating room...",
      opened_nickname_overlay = "Opened nickname overlay.",
      opened_settings_overlay = "Opened settings overlay.",
      guide_todo = "Guide will be expanded after Phase 3.",
      skin_todo = "Skin feature will be expanded after Phase 4.",
      credits_text = "ProjectR MVP by Team + Codex",
      nickname_empty = "Nickname cannot be empty.",
      nickname_saved = "Nickname saved: {nickname}",
      settings_saved = "Settings saved: {displayMode} / {language}",
      settings_saved_with_warning = "Settings saved: {displayMode} / {language} / {warning}"
    },
    display_mode = {
      windowed = "Windowed (1280x720 fixed)",
      fullscreen = "Fullscreen (current monitor)",
      option_windowed = "Windowed (1280x720)",
      option_fullscreen = "Fullscreen (current monitor)"
    },
    language = {
      option_ko = "Korean",
      option_en = "English"
    },
    overlay = {
      nickname = {
        title = "Change Nickname",
        subtitle = "Enter a new nickname and save.",
        placeholder = "Enter nickname"
      },
      settings = {
        title = "Settings",
        display_mode = "Display Mode",
        language = "Language",
        save_path = "Save Path: {path}"
      }
    }
  },
  room_search = {
    title = "Find Room",
    subtitle = "Enter room code for local server",
    placeholder = "Enter 16-character room code",
    button = {
      paste_clipboard = "Paste from Clipboard"
    },
    status = {
      code_len_invalid = "Room code must be 16 characters.",
      joining = "Joining room...",
      clipboard_not_available = "Clipboard is not available.",
      clipboard_read_failed = "Failed to read clipboard: {error}",
      clipboard_invalid_code = "No valid room code in clipboard.",
      clipboard_pasted = "Room code pasted from clipboard."
    }
  },
  waiting_room = {
    title = "Waiting Room",
    default_host_name = "Host",
    default_guest_name = "Guest",
    room_label = "Room: {roomCode}",
    role_label = "Role: {role}",
    role_unknown = "Role: -",
    host_line = "HOST: {nickname} [{state}]",
    guest_line = "GUEST: {nickname} [{state}]",
    guest_empty = "GUEST: (empty)",
    phase_line = "Phase: {phase}",
    online = "online",
    offline = "offline",
    chat_placeholder = "Type chat (Enter to send)",
    status = {
      ws_waiting = "Waiting for WS connection...",
      left_room = "Left waiting room.",
      start_condition_not_met = "Match start conditions are not met.",
      start_request_sent = "Match start request sent...",
      no_room_code = "No room code to copy.",
      clipboard_not_available = "Clipboard is not available.",
      room_copy_failed = "Failed to copy room code: {error}",
      room_copied = "Room code copied: {roomCode}",
      chat_denied = "Chat denied: {reason}",
      connected = "Connected ({role})",
      turn_order = "First turn: P{playerIndex}",
      room_closed = "Room closed: {reason}",
      server_error = "Server error: {code}",
      ws_open = "WS connected",
      ws_close = "WS closed: {reason}",
      ws_error = "WS error: {message}"
    },
    system = {
      player_joined = "[SYSTEM] player {playerIndex} joined",
      player_left = "[SYSTEM] player {playerIndex} left ({reason})"
    },
    chat_line = "[{nickname}] {text}"
  },
  abilities = {
    card_label = {
      reinforcement = "Reinforcement",
      shockwave = "Shockwave",
      invincible = "Invincible",
      rockfall = "Rockfall",
      agile = "Agile"
    }
  },
  single_dummy = {
    title = "Single Dummy (Manual Test)",
    subtitle = "Shockwave(1): {shockwave} | Opponent Invincible(2): {invincible} | R: Reset | ESC: Lobby",
    back_button = "Lobby",
    status = {
      entered = "Dummy mode: drag to shoot / 1=shockwave / 2=opponent invincible / R=reset",
      exited = "Single dummy test ended",
      drag_too_short = "Drag distance is too short.",
      reset_done = "Dummy state has been reset.",
      shockwave_toggle = "Shockwave toggle: {value}",
      invincible_toggle = "Opponent invincible toggle: {value}"
    }
  }
}

return LocaleEn
