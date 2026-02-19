--[[
파일명: en.lua
모듈명: LocaleEn

역할:
- 영어 UI 문자열 리소스를 제공한다.

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
      back = "Back",
      copy = "Copy",
      send = "Send",
      join = "Join",
      back_to_lobby = "Lobby",
      leave = "Leave",
      start_game = "Start",
      submit_placement = "Submit Placement",
      confirm_selection = "Confirm",
      surrender = "Surrender",
      rematch = "Rematch",
      menu = "Menu"
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
      rules_version_mismatch = "Rules version mismatch: client {clientVersion} / server {serverVersion}",
      ui_skin_toggle = "UI skin: {state}"
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
      play = "Play",
      debug_menu = "Debug Menu",
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
  play = {
    title = "Play",
    subtitle = "Choose a mode",
    menu = {
      single_player = "Single Player",
      multi_player = "Multiplayer"
    }
  },
  multiplayer = {
    title = "Multiplayer",
    subtitle = "Choose create room or find room",
    menu = {
      create_room = "Create Room",
      search_room = "Find Room"
    },
    status = {
      creating_room = "Creating room..."
    }
  },
  debug_menu = {
    title = "Debug Menu",
    subtitle = "Manual scene/effect test launcher",
    action = {
      go_lobby = "Lobby Scene",
      go_play = "Play Scene",
      go_multiplayer = "Multiplayer Scene",
      go_room_search = "Room Search Scene",
      waiting_mock = "Waiting Room (Mock)",
      coin_first = "Coin Toss (First)",
      coin_second = "Coin Toss (Second)",
      match_placement = "Match: Placement Phase",
      match_card_first = "Match: Card Select (Pick 1)",
      match_card_second = "Match: Card Select (Pick 2)",
      match_playing = "Match: Playing Phase",
      match_result = "Match: Result Phase",
      single_dummy = "Single Dummy Scene"
    },
    status = {
      default = "Debug menu ready (F7 shortcut available)",
      opened_from = "Opened debug menu from: {scene}",
      waiting_mock = "Entered waiting room mock state"
    }
  },
  guide = {
    title = "Guide"
  },
  skin = {
    title = "Skin"
  },
  credits = {
    title = "Credits"
  },
  stub = {
    message = "Stub"
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
    button = {
      ready = "Ready",
      waiting = "Waiting"
    },
    status = {
      ws_waiting = "Waiting for WS connection...",
      left_room = "Left waiting room.",
      start_condition_not_met = "Match start conditions are not met.",
      start_request_sent = "Match start request sent...",
      ready_request_sent = "Ready request sent...",
      guest_not_ready = "Guest is not ready.",
      already_ready = "Already marked as ready.",
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
      player_left = "[SYSTEM] player {playerIndex} left ({reason})",
      guest_ready = "{nickname} is ready."
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
    },
    validate = {
      rockfall_board_margin = "Obstacle must be placed at least 5px inside board edges.",
      rockfall_overlap_stone = "Obstacle cannot overlap any stone.",
      rockfall_overlap_obstacle = "Obstacle cannot overlap existing obstacle.",
      reinforcement_out_of_board = "Reinforcement stone must be placed inside board bounds.",
      reinforcement_too_close = "Position is too close to an existing stone.",
      reinforcement_overlap_obstacle = "Cannot place on top of an obstacle."
    },
    hint = {
      reinforcement_click = "Click on board to place reinforcement stone",
      rockfall_click = "Click on board to place rockfall obstacle",
      reinforcement_start = "Select reinforcement target: click on board. ESC/right-click to cancel",
      rockfall_start = "Select rockfall target: click on board. ESC/right-click to cancel",
      reinforcement_out_of_board = "Click inside the board to place reinforcement.",
      rockfall_out_of_board = "Click inside the board to place rockfall.",
      reinforcement_sending = "Sending reinforcement card request...",
      rockfall_sending = "Sending rockfall card request..."
    }
  },
  match = {
    title = "Match Phase",
    phase_label = "Current Phase: {phase}",
    turn_card_title = "TURN Card",
    card_select_title = "Card Selection",
    card_select_prompt = "Choose {pickCount} ability card(s)",
    card_select_waiting = "Waiting for opponent card lock...",
    card_select_selected = "Selected {selectedCount}/{pickCount}",
    power_label = "Power {power}",
    button = {
      submit_placement = "Submit Placement",
      confirm_selection = "Confirm Selection",
      surrender = "Surrender",
      rematch = "Rematch",
      menu = "Back to Menu"
    },
    validate = {
      out_of_board = "Position is outside board bounds.",
      must_place_own_zone = "You can only place in your own zone (bottom half).",
      too_close_existing = "Position is too close to existing placement."
    },
    status = {
      syncing = "Synchronizing match state...",
      placement_already_submitted = "Placement already submitted.",
      placement_count_full = "All placement slots (7) are used.",
      placement_progress = "Placement progress: {count}/{max}",
      placement_need_all = "You must place all 7 stones before submitting.",
      placement_submitted_waiting = "Placement submitted. Waiting for opponent...",
      card_pick_max = "You can select up to {count} card(s).",
      card_pick_need_exact = "Select exactly {count} card(s) before confirming.",
      card_pick_submit = "Sending card selection...",
      cannot_use_card_now = "Cannot use card right now.",
      card_use_submit = "Sending card use request...",
      card_target_cancel = "Card target selection cancelled.",
      card_target_cannot_place = "Cannot place card target at this position.",
      cannot_surrender_now = "Cannot surrender right now.",
      surrender_submit = "Sending surrender request...",
      cannot_vote_now = "Cannot vote on result right now.",
      vote_rematch_submit = "Sending rematch vote...",
      vote_lobby_submit = "Sending menu vote...",
      aiming = "Aiming... release mouse to shoot, ESC/right-click to cancel",
      shot_cancelled = "Shot cancelled.",
      shot_stone_missing = "Cannot find selected stone for shot.",
      shot_drag_too_short = "Drag distance is too short.",
      shot_dir_calc_failed = "Failed to calculate shot direction.",
      shot_submit = "Sending shot request...",
      snapshot_submit = "Submitting turn snapshot ({reason})",
      snapshot_reason_auto = "auto",
      back_to_waiting_after_result = "Returned to waiting state for rematch.",
      placement_phase_guide = "Placement phase: place 7 stones by clicking, then submit.",
      reveal_phase = "Placement reveal in progress...",
      card_select_phase = "Card selection phase.",
      my_turn_guide = "Your turn. Drag a stone to shoot.",
      opponent_turn_guide = "Opponent turn in progress...",
      result_vote_status = "Result phase: vote next action (my vote: {vote})",
      turn_order = "Turn order decided: first player P{playerIndex}",
      phase_changed = "Phase changed: {from} -> {to}",
      reveal_started = "Placement reveal has started.",
      cards_dealt = "Cards dealt. Choose and confirm.",
      my_cards_locked = "Your card selection is locked.",
      opponent_cards_locked = "Opponent card selection is locked.",
      my_turn_start = "Your turn started. Drag to shoot.",
      opponent_turn_start = "Opponent turn started.",
      card_cue = "Card cue: P{playerIndex} / {cardLabel}",
      card_applied = "Card applied: {cardLabel}",
      shot_accepted_wait_snapshot = "Shot accepted, waiting for snapshot...",
      shot_accepted_extra = "Shot accepted, extra shot available.",
      snapshot_requested = "Server requested a turn snapshot.",
      snapshot_applied = "Turn snapshot applied.",
      result_winner = "Result: winner P{winner}",
      server_error = "Server error: {code}",
      room_closed = "Room has been closed.",
      ws_close = "WS closed: {reason}",
      ws_error = "WS error: {message}"
    },
    result = {
      title = "RESULT - {title}",
      reason = "Reason: {reason}",
      vote = "My vote: {myVote} | Opponent vote: {opponentVote}",
      title_win = "Victory",
      title_lose = "Defeat",
      title_draw = "Draw",
      reason_stone_zero = "Eliminated all opponent stones",
      reason_draw = "Draw",
      reason_player_left = "Opponent left",
      reason_surrender = "Surrender",
      reason_snapshot_timeout = "Host snapshot timeout",
      vote_none = "None",
      vote_rematch = "Rematch",
      vote_lobby = "Menu"
    },
    info = {
      placement_my_done = "Done",
      placement_my_doing = "In progress",
      placement_opponent_done = "Done",
      placement_opponent_waiting = "Waiting",
      reveal_remaining = " / Reveal remaining: {sec}s",
      placement_line = "My placement: {myState} ({count}/{max}) | Opponent: {opponentState}{timerText}",
      turn_owner_me = "My turn",
      turn_owner_other = "Opponent turn",
      state_aim = "Ready to aim",
      state_wait_snapshot = "Waiting snapshot",
      state_pick_card_target = "Selecting card target",
      state_card_pending = "Sending card request",
      state_shot_done = "Shot completed",
      state_simulating = "Simulating physics",
      state_shot_pending = "Sending shot request",
      turn_line = "Turn {turnIndex} | {turnOwner} | Remaining: {remainSec}s | Shot {shotUsed}/{shotBudget} | Card used:{hasCardUsed} | State: {stateText}",
      card_select_line = "Need {pickCount} card(s) / Selected {selectedCount} / Remaining {remainSec}s",
      card_select_remaining_only = "Remaining: {remainSec}s",
      lock_done = "My selection locked",
      lock_wait = "Waiting to lock my selection",
      opponent_done = "Opponent locked",
      opponent_selecting = "Opponent selecting"
    }
  },
  single_dummy = {
    title = "Single Dummy (Manual Test)",
    subtitle = "Shockwave(1): {shockwave} | Opponent Invincible(2): {invincible} | R: Reset | ESC: Lobby",
    back_button = "Back",
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
