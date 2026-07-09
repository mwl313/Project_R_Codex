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
      server_url_missing = "Server URL is missing.",
      response_parse_failed = "Failed to parse response.",
      request_failed = "Request failed: {reason}",
      server_message_parse_failed = "Failed to parse server message.",
      rules_version_mismatch = "Rules version mismatch: client {clientVersion} / server {serverVersion}",
      poll_session_invalid = "Session is invalid ({reason}). Check local/cloud mix, server restart, or session expiration. env={env}, base={base}",
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
      record = "History",
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
  single = {
    campaign = {
      title = "Single Campaign",
      subtitle = "SP-01 Vertical Slice",
      summary = "Default Deck: {deckSize} cards | Owned Card Kinds: {ownedKinds}",
      button = {
        run_start = "Start Run",
        deck_manage = "Deck Manage"
      },
      status = {
        profile_loaded = "Single profile loaded.",
        profile_recovered = "Profile was recovered with defaults.",
        deck_missing = "Default deck not found.",
        deck_invalid = "Deck validation failed: {reason}"
      }
    },
    deck = {
      title = "Deck Manage",
      summary = "Deck Size: {deckSize}/{maxSize} | Page {page}/{maxPage}",
      row_owned = "Owned: {owned}",
      row_in_deck = "In Deck: {count}",
      owned_max = "3/3 (MAX)",
      button = {
        prev = "Prev",
        next = "Next",
        add = "Add",
        remove = "Remove"
      },
      status = {
        loaded = "Deck edit view loaded.",
        profile_recovered = "Profile was recovered with defaults.",
        save_failed = "Save failed: {error}",
        deck_missing = "Default deck is missing.",
        add_ok = "Card added to deck.",
        add_fail = "Add failed: {reason}",
        remove_ok = "Card removed from deck.",
        remove_fail = "Card not found in deck."
      }
    },
    node = {
      mob = "Mob Combat",
      elite = "Elite Combat",
      boss = "Boss Combat",
      shop = "Shop",
      rest = "Rest",
      deck_clean = "Deck Clean",
      event = "Event"
    },
    map = {
      title = "Run Map",
      node_default = "Next Node",
      node_line = "{nodeIndex}/{nodeCount} - {nodeTitle}",
      gold_line = "Gold: {gold}G",
      node = {
        combat = "Combat",
        elite = "Elite",
        boss = "Boss"
      },
      button = {
        start_combat = "Start Combat",
        enter_node = "Enter Node"
      },
      status = {
        ready = "Ready to start combat.",
        deck_invalid = "Deck is invalid. Fix it in deck manage.",
        deck_missing = "Default deck is missing.",
        selected = "Selected: {nodeTitle}",
        select_invalid = "This node cannot be selected at the current depth.",
        select_blocked = "This choice conflicts with stage path constraints."
      }
    },
    shop = {
      title = "Shop",
      gold_line = "Gold: {gold}G",
      mode = {
        buy = "Buy Card",
        upgrade = "Upgrade Card",
        remove = "Remove Card"
      },
      button = {
        buy = "Buy",
        buy_upgrade = "Upgrade ({price}G)",
        buy_remove = "Remove ({price}G)",
        leave = "Leave"
      },
      row = {
        level = "Upgrade Lv: {level}"
      },
      status = {
        ready = "Choose one action in the shop.",
        not_enough_gold = "Not enough gold.",
        buy_ok = "Purchased {card} (Gold: {gold}G)",
        buy_fail = "Purchase failed: {reason}",
        upgrade_ok = "{card} upgraded (Lv.{level})",
        remove_ok = "{card} removed",
        remove_fail = "Failed to remove card."
      }
    },
    rest = {
      title = "Rest",
      subtitle = "Choose one free action: upgrade or remove.",
      mode = {
        upgrade = "Free Upgrade",
        remove = "Free Remove"
      },
      row = {
        level = "Upgrade Lv: {level}"
      },
      button = {
        upgrade = "Upgrade",
        remove = "Remove"
      },
      status = {
        ready = "Choose your rest bonus.",
        upgrade_ok = "{card} upgraded (Lv.{level})",
        remove_ok = "{card} removed",
        remove_fail = "Failed to remove card.",
        deck_empty = "Deck is empty. Rest effect is skipped."
      }
    },
    deck_clean = {
      title = "Deck Clean",
      subtitle = "Remove one card for free.",
      button = {
        remove = "Remove"
      },
      status = {
        ready = "Choose a card to remove.",
        remove_ok = "{card} removed",
        remove_fail = "Failed to remove card.",
        deck_empty = "Deck is empty. Deck-clean effect is skipped."
      }
    },
    event = {
      title = "Event",
      desc = "Choose an option.",
      gold_line = "Gold: {gold}G",
      status = {
        ready = "Pick one event option.",
        gold_gain = "Gold +{gold}",
        gold_lose = "Gold -{gold}",
        temp_applied = "Temporary modifier applied.",
        upgrade_random = "{card} upgraded (Lv.{level})",
        remove_random = "{card} removed",
        remove_n_ok = "{count} cards removed",
        deck_empty = "Deck is empty.",
        not_enough_gold = "Not enough gold.",
        rare_missing = "No rare cards available.",
        buy_fail = "Cannot purchase card.",
        buy_rare_ok = "Purchased rare card: {card}",
        duplicate_ok = "Duplicated {card}",
        duplicate_fail = "Failed to duplicate card."
      },
      table = {
        event_gold_or_draw_penalty = {
          title = "Strange Offer",
          desc = "A stranger proposes a trade.",
          choice_gain_gold = "Gain 30 Gold",
          choice_lose_draw = "Next combat draw -1"
        },
        event_upgrade_or_remove = {
          title = "Forge",
          desc = "The smith can help only once.",
          choice_upgrade = "Upgrade random card",
          choice_remove = "Remove random card"
        },
        event_rare_offer = {
          title = "Black Market",
          desc = "You can buy a rare card.",
          choice_buy = "Buy rare card (30G)",
          choice_gain_gold = "Decline and gain 20G"
        },
        event_mystery_fight = {
          title = "Suspicious Noise",
          desc = "A strong enemy blocks the way.",
          choice_fight = "Mystery Fight (Elite)",
          choice_skip = "Bypass and gain 15G"
        },
        event_duplicate_or_gold = {
          title = "Duplicator",
          desc = "Duplicate a deck card or take gold.",
          choice_duplicate = "Duplicate random card",
          choice_gain_gold = "Take 25G"
        },
        event_remove_two_or_lose_gold = {
          title = "Heavy Load",
          desc = "Lighten your deck or pay toll.",
          choice_remove_two = "Remove 2 cards",
          choice_lose_gold = "Lose 20G"
        }
      }
    },
    combat = {
      title = "Single Combat",
      subtitle = "Drag and shoot to eliminate all enemy stones.",
      node_line = "Node: {nodeType} ({nodeId})",
      turn_owner = {
        player = "Player",
        ai = "AI"
      },
      info_line = "Turn {turnIndex} | {turnOwner} | Time {remainSec}s | Shot {shotUsed}/{shotBudget}",
      info_line_no_timer = "Turn {turnIndex} | {turnOwner} | Shot {shotUsed}/{shotBudget}",
      status = {
        player_turn = "Your turn. Drag a stone to shoot.",
        ai_turn = "Opponent turn.",
        ai_thinking = "AI is aiming...",
        shot_too_short = "Drag distance is too short.",
        card_cannot_use = "You cannot use this card right now.",
        card_unsupported = "This card is not implemented in single combat yet.",
        card_target_invalid = "Invalid card target.",
        card_target_cancel = "Card targeting cancelled.",
        card_used = "{card} used",
        shot_fired = "Shot fired",
        turn_timeout = "Turn timer expired. Passing turn.",
        combat_win = "Victory!",
        combat_lose = "Defeat.",
        combat_draw = "Draw.",
        extra_shot = "You still have an extra shot."
      },
      gimmick = {
        auto_rockfall = "Boss Gimmick: Auto Rockfall",
        blackhole_pulse = "Boss Gimmick: Blackhole Pulse",
        bind_random_enemy = "Boss Gimmick: Random Bind"
      }
    },
    character_select = {
      title = "Choose Your Psychic",
      subtitle = "Select your character"
    },
    wave = {
      title = "Single Wave Endless",
      stage_line = "Stage {stage} / Wave {wave}",
      hud = {
        wave_title = "Wave",
        wave_value = "Wave {wave}",
        score_title = "Score",
        max_combo = "Max Combo: {value}",
        enemies_killed = "Enemies Killed: {value}",
        relic_title = "Relic Buff",
        deck_title = "Deck Zone",
        deck_count = "Draw {drawCount} | Discard {discardCount}\nHand {handCount}/{handMax}"
      },
      status = {
        profile_recovered = "Recovered and loaded single profile.",
        intro_playing = "Playing run start intro...",
        wave_start = "Wave {wave} started",
        run_end = "Run ended."
      },
      upgrade = {
        title = "Upgrade Selection",
        subtitle = "Pick 1 of 3 and confirm.",
        category = {
          card = "Card",
          relic = "Relic",
          hand_ops = "Hand Ops"
        },
        button = {
          confirm = "Confirm",
          reopen = "Reopen Upgrade"
        },
        status = {
          choose = "Choose an upgrade.",
          select_required = "Select an option first.",
          reopen_required = "Upgrade selection is required.",
          card_to_hand = "Card added to hand.",
          card_to_deck = "Hand is full. Added to deck and shuffled.",
          relic_added = "Relic acquired.",
          god_relic_added = "God relic acquired.",
          relic_skip = "Relic already owned. Skipped.",
          hand_op_applied = "Hand operation applied.",
          apply_failed = "Failed to apply upgrade."
        },
        hand_op = {
          hand_draw_one = {
            title = "Quick Draw",
            desc = "Draw 1 card immediately from deck."
          },
          hand_draw_two = {
            title = "Double Draw",
            desc = "Draw 2 cards immediately from deck."
          },
          hand_shuffle_deck = {
            title = "Deck Shuffle",
            desc = "Shuffle current draw pile."
          },
          hand_recycle_discard = {
            title = "Recycle Discard",
            desc = "Return discard pile to deck and shuffle."
          }
        }
      },
      pause = {
        title = "Paused",
        button = {
          resume = "Resume",
          lobby = "Back to Lobby",
          reset = "Reset Run",
          settings = "Settings"
        },
        status = {
          settings_saved = "Settings saved."
        }
      },
      result = {
        lose = "Run Failed",
        draw = "Run Draw",
        subtitle = "Choose reset or back to lobby."
      }
    },
    relic_reward = {
      title = "Relic Reward",
      subtitle = "Pick 1 relic out of 3.",
      rarity_line = "Rarity: {rarity}",
      button = {
        confirm = "Acquire Relic"
      },
      status = {
        choose_one = "Choose a relic to acquire.",
        select_required = "Select a relic first.",
        selected = "Selected: {relic}",
        picked = "Relic acquired: {relic}",
        skip_empty = "No available relics. Proceeding to the next step."
      }
    },
    relic = {
      name = {
        relic_draw_plus = "Feather of Focus",
        relic_gold_mul = "Golden Pouch",
        relic_stable_hand = "Stable Hands",
        relic_minor_power = "Minor Amplifier",
        relic_coin_pouch = "Coin Pouch",
        relic_power_plus = "Power Core",
        relic_tactical_draw = "Tactical Note",
        relic_merchant_emblem = "Merchant Emblem",
        relic_overclock_core = "Overclock Core",
        relic_kings_trophy = "King's Trophy"
      },
      desc = {
        relic_draw_plus = "+1 draw at combat start",
        relic_gold_mul = "x1.2 combat gold reward",
        relic_stable_hand = "+1 draw at combat start",
        relic_minor_power = "x1.05 max shot power",
        relic_coin_pouch = "x1.15 combat gold reward",
        relic_power_plus = "x1.10 max shot power",
        relic_tactical_draw = "+2 draw at combat start",
        relic_merchant_emblem = "x1.25 combat gold reward",
        relic_overclock_core = "x1.20 max shot power, +1 draw",
        relic_kings_trophy = "x1.40 combat gold reward, +1 draw"
      }
    },
    reward = {
      title = "Combat Reward",
      subtitle = "Pick 1 card out of 3.",
      button = {
        confirm = "Apply Reward"
      },
      status = {
        choose_one = "Choose a reward card.",
        select_required = "Select a card first.",
        profile_invalid = "Profile data is invalid.",
        deck_missing = "Default deck not found.",
        add_skipped = "Skipped adding reward card due to deck/card limits.",
        picked = "Reward selected: {card}",
        selected = "Selected card #{index}",
        save_failed = "Save failed: {error}"
      }
    },
    discard = {
      title = "Discard Card",
      subtitle = "Deck size {deckSize}/{maxSize} - discard 1 card to continue.",
      button = {
        confirm = "Discard Selected Card"
      },
      status = {
        guide = "Select one card to discard, then confirm.",
        deck_missing = "Default deck is missing.",
        select_required = "Please select a card to discard.",
        remove_fail = "Failed to remove the card.",
        selected = "Selected: {card}",
        save_failed = "Save failed: {error}"
      }
    },
    discard_overlay = {
      title = "Too Many Cards",
      message = "Deck limit ({maxSize}) exceeded. Select 1 card to discard.",
      button = {
        confirm = "Confirm"
      },
      status = {
        select_required = "Select a card to discard first.",
        selected = "Selected: {card}",
        discard_failed = "Failed to remove the selected card."
      }
    },
    result = {
      title = "Run Result",
      title_win = "Victory",
      title_lose = "Defeat",
      subtitle_win = "Proceeding to the next step.",
      subtitle_lose = "Returning to campaign.",
      button = {
        proceed = "Proceed"
      }
    },
    reason = {
      invalid_deck = "Deck is invalid.",
      unknown_card_id = "Unknown card.",
      duplicate_limit = "You can include up to 3 copies of the same card.",
      duplicate_limit_exceeded = "Deck exceeds duplicate copy limit.",
      owned_count = "Cannot add beyond owned count.",
      owned_count_exceeded = "Deck exceeds owned count limit.",
      deck_full = "Deck is full.",
      deck_size_exceeded = "Deck size exceeds the maximum.",
      deck_too_small = "Deck size is below the minimum (5 cards)."
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
    network = {
      title = "Server Environment",
      current = "Current: {env}",
      ["local"] = "Local Test",
      ["cloud"] = "Network Test",
      apply = "Apply"
    },
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
      match_card_zone = "Match: Card Zone Test",
      match_result = "Match: Result Phase",
      single_dummy = "Single Dummy Scene"
    },
    status = {
      default = "Debug menu ready (F7 shortcut available)",
      opened_from = "Opened debug menu from: {scene}",
      waiting_mock = "Entered waiting room mock state",
      server_env_locked = "Cannot change server while connected. Leave/disconnect first.",
      server_env_applied = "Server environment applied: {env}"
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
      server_waiting = "Waiting for server event connection...",
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
      server_open = "Server event connected",
      server_close = "Server event disconnected: {reason}",
      server_error_event = "Server event error: {message}"
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
    hand = {
      drop_prompt = "Drop a card in the center zone to use it"
    },
    cutscene = {
      skip = "Skip",
      waiting_opponent = "Waiting for opponent cutscene..."
    },
    chat = {
      toggle_label = "Chat",
      panel_title = "In-Game Chat",
      input_placeholder = "Type a message (Enter to send)",
      line = "[{nickname}] {text}",
      system_denied = "[SYSTEM] Chat denied: {reason}"
    },
    shot_deny_reason = {
      not_in_phase = "You cannot shoot in the current state.",
      invalid_payload = "Shot payload is invalid.",
      turn_mismatch = "Turn information is out of sync.",
      not_your_turn = "It is not your turn.",
      shot_budget_exceeded = "No more shots are available this turn.",
      awaiting_snapshot = "Resolving snapshot. Please wait.",
      cutscene_active = "Skill cutscene is playing. Please wait.",
      invalid_shot_power = "Shot power is out of range.",
      invalid_shot_dir = "Shot direction is invalid.",
      timeout = "Turn time has expired.",
      invalid_shot_stone = "Selected stone is invalid.",
      stone_locked_this_turn = "That stone is locked for this turn."
    },
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
      card_already_used_turn = "You already used a card this turn.",
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
      cutscene_playing = "Playing skill cutscene: {cardLabel}",
      shot_accepted_wait_snapshot = "Shot accepted, waiting for snapshot...",
      shot_accepted_extra = "Shot accepted, extra shot available.",
      snapshot_requested = "Server requested a turn snapshot.",
      snapshot_applied = "Turn snapshot applied.",
      result_winner = "Result: winner P{winner}",
      server_error = "Server error: {code}",
      room_closed = "Room has been closed.",
      server_close = "Server event disconnected: {reason}",
      server_error_event = "Server event error: {message}",
      ability_use_submit = "Requesting ability use...",
      ability_not_charged = "Ability is not yet charged",
      cannot_use_ability_now = "Cannot use ability right now"
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
      state_cutscene_paused = "Skill cutscene active (timer paused)",
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
    subtitle = "Shockwave(1): {shockwave} | Opponent Invincible(2): {invincible} | God Relics(3~7) | 8: GOD reset | R: Reset | ESC: Lobby",
    back_button = "Back",
    god_debug_title = "God Relic Debug",
    god_debug_hint = "Add stacks with buttons/keys (3~7), reset with 8",
    god_debug_empty = "No god relic acquired.",
    status = {
      entered = "Dummy mode: drag to shoot / 1=shockwave / 2=opponent invincible / R=reset",
      exited = "Single dummy test ended",
      drag_too_short = "Drag distance is too short.",
      reset_done = "Dummy state has been reset.",
      shockwave_toggle = "Shockwave toggle: {value}",
      invincible_toggle = "Opponent invincible toggle: {value}",
      god_relic_added = "God relic added: {name} (x{count})",
      god_relic_cleared = "God relic debug stacks have been reset."
    }
  },
  record = {
    title = "Match History",
    stats_line = "Wins: {wins} / Losses: {losses} / Total: {total} (Win Rate {rate})",
    character_stats_title = "Character Stats",
    character_stats_line = "{character}: {played} games, {wins} wins (Win Rate {rate})",
    recent_title = "Recent 10 Matches",
    result_win = "Win",
    result_loss = "Loss",
    no_records = "No records yet."
  }
}

return LocaleEn
