--[[
파일명: ko.lua
모듈명: LocaleKo

역할:
- 한국어(기본) UI 문자열 리소스를 제공한다.

외부에서 사용 가능한 함수:
- LocaleKo 테이블 참조
]]

local LocaleKo = {
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
      save = "저장",
      cancel = "취소",
      back = "뒤로",
      copy = "복사",
      send = "전송",
      join = "참가",
      back_to_lobby = "로비로",
      leave = "나가기",
      start_game = "게임 시작",
      submit_placement = "배치 제출",
      confirm_selection = "선택 확정",
      surrender = "기권",
      rematch = "재대결",
      menu = "메뉴로"
    }
  },
  font = {
    warning = {
      load_failed = "폰트 로딩 실패({path}): {error}. 기본 폰트로 폴백합니다."
    }
  },
  app = {
    ui = {
      server_url_missing = "서버 URL이 없습니다.",
      response_parse_failed = "응답 파싱 실패",
      request_failed = "요청 실패: {reason}",
      server_message_parse_failed = "서버 메시지 파싱 실패",
      rules_version_mismatch = "룰 버전 불일치: 클라이언트 {clientVersion} / 서버 {serverVersion}",
      poll_session_invalid = "세션이 유효하지 않습니다({reason}). 서버 혼용(local/cloud)/서버 재시작/세션 만료를 확인하세요. env={env}, base={base}",
      ui_skin_toggle = "UI skin: {state}"
    },
    settings = {
      load_failed_default = "settings.ini 로드 실패, 기본값 사용: {error}",
      apply_failed_windowed = "디스플레이 적용 실패, 창모드 사용: {error}",
      save_failed = "settings.ini 저장 실패: {error}",
      apply_warning = "디스플레이 모드 적용 경고: {error}"
    }
  },
  lobby = {
    title = "ProjectR Lobby",
    current_nickname = "현재 닉네임: {nickname}",
    menu = {
      play = "플레이",
      debug_menu = "디버그 메뉴",
      single_player = "싱글플레이어",
      create_room = "방 생성",
      search_room = "방 찾기",
      change_nickname = "닉네임 변경",
      settings = "환경설정",
      guide = "가이드",
      skin = "스킨",
      credits = "크레딧",
      quit = "게임 종료"
    },
    status = {
      enter_single_dummy = "싱글 더미 테스트 모드로 진입합니다.",
      creating_room = "방 생성 요청 중...",
      opened_nickname_overlay = "닉네임 오버레이를 열었습니다.",
      opened_settings_overlay = "환경설정 오버레이를 열었습니다.",
      guide_todo = "가이드는 Phase 3 이후에 확장됩니다.",
      skin_todo = "스킨 기능은 Phase 4 이후에 확장됩니다.",
      credits_text = "ProjectR MVP by Team + Codex",
      nickname_empty = "닉네임은 비어 있을 수 없습니다.",
      nickname_saved = "닉네임 저장됨: {nickname}",
      settings_saved = "환경설정 저장됨: {displayMode} / {language}",
      settings_saved_with_warning = "환경설정 저장됨: {displayMode} / {language} / {warning}"
    },
    display_mode = {
      windowed = "창모드(1280x720 고정)",
      fullscreen = "전체화면(현재 모니터 해상도)",
      option_windowed = "창모드 (1280x720)",
      option_fullscreen = "전체화면 (현재 모니터)"
    },
    language = {
      option_ko = "한국어",
      option_en = "English"
    },
    overlay = {
      nickname = {
        title = "닉네임 변경",
        subtitle = "새 닉네임을 입력하고 저장하세요.",
        placeholder = "닉네임 입력"
      },
      settings = {
        title = "환경설정",
        display_mode = "디스플레이 모드",
        language = "언어 설정",
        save_path = "저장 경로: {path}"
      }
    }
  },
  play = {
    title = "플레이",
    subtitle = "모드를 선택하세요",
    menu = {
      single_player = "싱글플레이어",
      multi_player = "멀티플레이어"
    }
  },
  multiplayer = {
    title = "멀티플레이어",
    subtitle = "방 생성 또는 방 찾기를 선택하세요",
    menu = {
      create_room = "방 생성",
      search_room = "방 찾기"
    },
    status = {
      creating_room = "방 생성 요청 중..."
    }
  },
  debug_menu = {
    title = "Debug Menu",
    subtitle = "씬/연출 수동 테스트",
    network = {
      title = "서버 환경",
      current = "현재: {env}",
      ["local"] = "로컬 테스트",
      ["cloud"] = "네트워크 테스트",
      apply = "적용"
    },
    action = {
      go_lobby = "로비 씬",
      go_play = "플레이 씬",
      go_multiplayer = "멀티플레이어 씬",
      go_room_search = "방 찾기 씬",
      waiting_mock = "대기방(모의 상태)",
      coin_first = "코인토스(선공)",
      coin_second = "코인토스(후공)",
      match_placement = "매치: 배치 단계",
      match_card_first = "매치: 카드선택(1장 선택)",
      match_card_second = "매치: 카드선택(2장 선택)",
      match_playing = "매치: 턴 플레이 단계",
      match_card_zone = "매치: 카드존 테스트",
      match_result = "매치: 결과 단계",
      single_dummy = "싱글 더미 씬"
    },
    status = {
      default = "디버그 메뉴 준비 완료 (F7 단축키 지원)",
      opened_from = "디버그 메뉴 열림: {scene}",
      waiting_mock = "모의 대기방 상태로 진입",
      server_env_locked = "연결 중에는 서버를 변경할 수 없습니다. 먼저 나가기/연결 종료를 해주세요.",
      server_env_applied = "서버 환경 적용: {env}"
    }
  },
  guide = {
    title = "가이드"
  },
  skin = {
    title = "스킨"
  },
  credits = {
    title = "크레딧"
  },
  stub = {
    message = "Stub"
  },
  room_search = {
    title = "방 찾기",
    subtitle = "로컬 서버 기준 룸 코드를 입력하세요",
    placeholder = "16자리 룸 코드를 입력하세요",
    button = {
      paste_clipboard = "클립보드에서 불어넣기"
    },
    status = {
      code_len_invalid = "룸 코드는 16자리여야 합니다.",
      joining = "참가 요청 중...",
      clipboard_not_available = "클립보드 기능을 사용할 수 없습니다.",
      clipboard_read_failed = "클립보드 읽기 실패: {error}",
      clipboard_invalid_code = "클립보드에 유효한 룸 코드가 없습니다.",
      clipboard_pasted = "클립보드에서 룸 코드를 불어넣었습니다."
    }
  },
  waiting_room = {
    title = "대기방",
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
    chat_placeholder = "채팅 입력 (Enter 전송)",
    button = {
      ready = "준비하기",
      waiting = "대기중"
    },
    status = {
      server_waiting = "서버 이벤트 연결 대기 중...",
      left_room = "대기방에서 나왔습니다.",
      start_condition_not_met = "게임 시작 조건이 충족되지 않았습니다.",
      start_request_sent = "게임 시작 요청 전송...",
      ready_request_sent = "준비 완료 요청 전송...",
      guest_not_ready = "게스트가 준비되지 않았습니다.",
      already_ready = "이미 준비 완료 상태입니다.",
      no_room_code = "복사할 룸 코드가 없습니다.",
      clipboard_not_available = "클립보드 기능을 사용할 수 없습니다.",
      room_copy_failed = "룸 코드 복사 실패: {error}",
      room_copied = "룸 코드 복사됨: {roomCode}",
      chat_denied = "채팅 거부: {reason}",
      connected = "연결됨 ({role})",
      turn_order = "선공 결정: P{playerIndex}",
      room_closed = "방이 종료되었습니다: {reason}",
      server_error = "서버 오류: {code}",
      server_open = "서버 이벤트 연결 성공",
      server_close = "서버 이벤트 연결 종료: {reason}",
      server_error_event = "서버 이벤트 오류: {message}"
    },
    system = {
      player_joined = "[SYSTEM] player {playerIndex} joined",
      player_left = "[SYSTEM] player {playerIndex} left ({reason})",
      guest_ready = "{nickname}님이 준비완료되었습니다."
    },
    chat_line = "[{nickname}] {text}"
  },
  abilities = {
    card_label = {
      reinforcement = "신병",
      shockwave = "충격파",
      invincible = "무적",
      rockfall = "낙석",
      agile = "날렵함"
    },
    validate = {
      rockfall_board_margin = "장애물은 보드 경계에서 5px 안쪽에만 배치할 수 있습니다.",
      rockfall_overlap_stone = "장애물은 알과 겹칠 수 없습니다.",
      rockfall_overlap_obstacle = "기존 장애물과 겹칠 수 없습니다.",
      reinforcement_out_of_board = "신병 알은 보드 안쪽 경계에서만 배치할 수 있습니다.",
      reinforcement_too_close = "기존 알과 너무 가깝습니다.",
      reinforcement_overlap_obstacle = "장애물과 겹치는 위치에는 배치할 수 없습니다."
    },
    hint = {
      reinforcement_click = "신병 위치를 보드에서 클릭",
      rockfall_click = "낙석 위치를 보드에서 클릭",
      reinforcement_start = "신병 대상 선택: 보드 위를 클릭해 알을 배치하세요. ESC/우클릭 취소",
      rockfall_start = "낙석 대상 선택: 보드 위를 클릭해 장애물을 배치하세요. ESC/우클릭 취소",
      reinforcement_out_of_board = "보드 안을 클릭해 신병 위치를 선택하세요.",
      rockfall_out_of_board = "보드 안을 클릭해 낙석 위치를 선택하세요.",
      reinforcement_sending = "신병 카드 사용 요청 전송...",
      rockfall_sending = "낙석 카드 사용 요청 전송..."
    }
  },
  match = {
    title = "Match Phase",
    phase_label = "현재 Phase: {phase}",
    turn_card_title = "TURN 카드",
    card_select_title = "카드 선택",
    card_select_prompt = "초능력 카드를 {pickCount}장 고르세요",
    card_select_waiting = "상대 선택 대기중...",
    card_select_selected = "{selectedCount}/{pickCount} 선택",
    power_label = "Power {power}",
    hand = {
      drop_prompt = "가운데 영역에 카드를 내려놓아 사용"
    },
    cutscene = {
      skip = "건너뛰기",
      waiting_opponent = "상대 컷신 대기중..."
    },
    chat = {
      toggle_label = "채팅",
      panel_title = "인게임 채팅",
      input_placeholder = "메시지를 입력하세요 (Enter 전송)",
      line = "[{nickname}] {text}",
      system_denied = "[SYSTEM] 채팅 거부: {reason}"
    },
    shot_deny_reason = {
      not_in_phase = "지금은 샷을 할 수 없는 상태입니다.",
      invalid_payload = "샷 정보가 올바르지 않습니다.",
      turn_mismatch = "턴 정보가 맞지 않습니다. (동기화 중)",
      not_your_turn = "내 턴이 아닙니다.",
      shot_budget_exceeded = "이번 턴에는 더 이상 샷을 할 수 없습니다.",
      awaiting_snapshot = "정산 중입니다. 잠시만 기다려주세요.",
      cutscene_active = "스킬 연출 중입니다. 잠시만 기다려주세요.",
      invalid_shot_power = "샷 파워가 범위를 벗어났습니다.",
      invalid_shot_dir = "샷 방향이 올바르지 않습니다.",
      timeout = "턴 시간이 종료되었습니다.",
      invalid_shot_stone = "선택한 알이 유효하지 않습니다.",
      stone_locked_this_turn = "이번 턴에는 해당 알을 움직일 수 없습니다."
    },
    button = {
      submit_placement = "배치 제출",
      confirm_selection = "선택 확정",
      surrender = "기권",
      rematch = "재대결",
      menu = "메뉴로"
    },
    validate = {
      out_of_board = "보드 경계를 벗어났습니다.",
      must_place_own_zone = "내 진영(하단 절반) 안에서만 배치할 수 있습니다.",
      too_close_existing = "기존 배치와 너무 가깝습니다."
    },
    status = {
      syncing = "매치 상태 동기화 중...",
      placement_already_submitted = "이미 배치를 제출했습니다.",
      placement_count_full = "배치 가능 개수(7개)를 모두 사용했습니다.",
      placement_progress = "배치 진행: {count}/{max}",
      placement_need_all = "7개를 모두 배치해야 제출할 수 있습니다.",
      placement_submitted_waiting = "배치 제출 완료, 상대를 기다리는 중...",
      card_pick_max = "최대 {count}장까지만 선택할 수 있습니다.",
      card_pick_need_exact = "{count}장을 선택 후 확정하세요.",
      card_pick_submit = "카드 선택 확정 요청 전송...",
      cannot_use_card_now = "지금은 카드를 사용할 수 없습니다.",
      card_already_used_turn = "이번 턴에는 이미 카드를 사용했습니다.",
      card_use_submit = "카드 사용 요청 전송...",
      card_target_cancel = "카드 대상 선택을 취소했습니다.",
      card_target_cannot_place = "해당 위치에는 배치할 수 없습니다.",
      cannot_surrender_now = "지금은 기권할 수 없습니다.",
      surrender_submit = "기권 요청 전송...",
      cannot_vote_now = "지금은 결과 투표를 할 수 없습니다.",
      vote_rematch_submit = "재대결 투표 전송...",
      vote_lobby_submit = "메뉴 복귀 투표 전송...",
      aiming = "조준 중... 마우스를 놓아 발사, ESC/우클릭으로 취소",
      shot_cancelled = "발사를 취소했습니다.",
      shot_stone_missing = "발사할 알을 찾지 못했습니다.",
      shot_drag_too_short = "드래그 거리가 너무 짧습니다.",
      shot_dir_calc_failed = "발사 방향 계산 실패",
      shot_submit = "발사 요청 전송...",
      snapshot_submit = "턴 스냅샷 제출 ({reason})",
      snapshot_reason_auto = "auto",
      back_to_waiting_after_result = "재대결 대기 상태로 복귀했습니다.",
      placement_phase_guide = "배치 단계: 클릭으로 7개를 배치한 뒤 제출하세요.",
      reveal_phase = "배치 공개 중...",
      card_select_phase = "카드 선택 단계입니다.",
      my_turn_guide = "내 턴입니다. 알을 드래그해 발사하세요.",
      opponent_turn_guide = "상대 턴 진행 중...",
      result_vote_status = "결과 단계: 후속 동작 투표 (내 투표: {vote})",
      turn_order = "턴 순서 결정됨: 선공 P{playerIndex}",
      phase_changed = "Phase 변경: {from} -> {to}",
      reveal_started = "배치 공개가 시작되었습니다.",
      cards_dealt = "카드가 분배되었습니다. 선택 후 확정하세요.",
      my_cards_locked = "내 카드 선택이 확정되었습니다.",
      opponent_cards_locked = "상대가 카드 선택을 확정했습니다.",
      my_turn_start = "내 턴 시작. 드래그해서 발사하세요.",
      opponent_turn_start = "상대 턴 시작",
      card_cue = "카드 사용 연출: P{playerIndex} / {cardLabel}",
      card_applied = "카드 효과 적용됨: {cardLabel}",
      cutscene_playing = "스킬 연출 재생 중: {cardLabel}",
      shot_accepted_wait_snapshot = "발사 수락, 스냅샷 대기 중...",
      shot_accepted_extra = "발사 수락, 추가 발사 가능",
      snapshot_requested = "서버가 턴 스냅샷을 요청했습니다.",
      snapshot_applied = "턴 스냅샷 적용 완료",
      result_winner = "결과: winner P{winner}",
      server_error = "서버 오류: {code}",
      room_closed = "방이 종료되었습니다.",
      server_close = "서버 이벤트 연결 종료: {reason}",
      server_error_event = "서버 이벤트 오류: {message}"
    },
    result = {
      title = "RESULT - {title}",
      reason = "사유: {reason}",
      vote = "내 투표: {myVote} | 상대 투표: {opponentVote}",
      title_win = "승리",
      title_lose = "패배",
      title_draw = "무승부",
      reason_stone_zero = "상대 알 전멸",
      reason_draw = "무승부",
      reason_player_left = "상대 이탈",
      reason_surrender = "기권",
      reason_snapshot_timeout = "호스트 스냅샷 타임아웃",
      vote_none = "없음",
      vote_rematch = "재대결",
      vote_lobby = "메뉴"
    },
    info = {
      placement_my_done = "완료",
      placement_my_doing = "진행중",
      placement_opponent_done = "완료",
      placement_opponent_waiting = "대기중",
      reveal_remaining = " / 공개 남은 시간: {sec}s",
      placement_line = "내 배치: {myState} ({count}/{max}) | 상대 배치: {opponentState}{timerText}",
      turn_owner_me = "내 턴",
      turn_owner_other = "상대 턴",
      state_aim = "조준 가능",
      state_wait_snapshot = "스냅샷 대기",
      state_pick_card_target = "카드 대상 선택 중",
      state_card_pending = "카드 요청 전송 중",
      state_cutscene_paused = "스킬 연출 재생 중 (타이머 일시정지)",
      state_shot_done = "발사 완료",
      state_simulating = "물리 시뮬레이션 중",
      state_shot_pending = "발사 요청 전송 중",
      turn_line = "턴 {turnIndex} | {turnOwner} | 남은 시간: {remainSec}s | 샷 {shotUsed}/{shotBudget} | 카드사용:{hasCardUsed} | 상태: {stateText}",
      card_select_line = "선택 수: {pickCount}장 / 선택됨: {selectedCount}장 / 남은 시간: {remainSec}s",
      card_select_remaining_only = "남은 시간: {remainSec}s",
      lock_done = "내 선택 확정 완료",
      lock_wait = "내 선택 대기중",
      opponent_done = "상대 확정 완료",
      opponent_selecting = "상대 선택 중"
    }
  },
  single_dummy = {
    title = "Single Dummy (Manual Test)",
    subtitle = "충격파(1): {shockwave} | 상대 무적(2): {invincible} | R: 리셋 | ESC: 로비",
    back_button = "뒤로",
    status = {
      entered = "더미 모드: 드래그 발사 / 1=충격파 / 2=상대 무적 / R=리셋",
      exited = "싱글 더미 테스트 종료",
      drag_too_short = "드래그 거리가 너무 짧습니다.",
      reset_done = "더미 상태를 초기화했습니다.",
      shockwave_toggle = "충격파 토글: {value}",
      invincible_toggle = "상대 무적 토글: {value}"
    }
  }
}

return LocaleKo
