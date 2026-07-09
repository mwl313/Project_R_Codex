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
      tutorial = "튜토리얼",
      record = "전적",
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
  single = {
    campaign = {
      title = "싱글 캠페인",
      subtitle = "SP-01 세로 슬라이스",
      summary = "기본 덱: {deckSize}장 | 보유 카드 종류: {ownedKinds}",
      button = {
        run_start = "런 시작",
        deck_manage = "카드 관리"
      },
      status = {
        profile_loaded = "싱글 프로필을 불러왔습니다.",
        profile_recovered = "프로필을 복구해 기본값으로 불러왔습니다.",
        deck_missing = "기본 덱을 찾을 수 없습니다.",
        deck_invalid = "덱 유효성 검사 실패: {reason}"
      }
    },
    deck = {
      title = "카드 관리",
      summary = "덱 크기: {deckSize}/{maxSize} | 페이지 {page}/{maxPage}",
      row_owned = "보유: {owned}",
      row_in_deck = "덱 포함: {count}",
      owned_max = "3/3 (MAX)",
      button = {
        prev = "이전",
        next = "다음",
        add = "추가",
        remove = "제거"
      },
      status = {
        loaded = "덱 편집 화면입니다.",
        profile_recovered = "프로필을 복구해 기본값으로 불러왔습니다.",
        save_failed = "저장 실패: {error}",
        deck_missing = "기본 덱이 없습니다.",
        add_ok = "카드를 덱에 추가했습니다.",
        add_fail = "추가 실패: {reason}",
        remove_ok = "카드를 덱에서 제거했습니다.",
        remove_fail = "해당 카드를 덱에서 찾지 못했습니다."
      }
    },
    node = {
      mob = "잡몹 전투",
      elite = "엘리트 전투",
      boss = "보스 전투",
      shop = "상점",
      rest = "휴식",
      deck_clean = "덱 정리",
      event = "이벤트"
    },
    map = {
      title = "런 맵",
      node_default = "다음 노드",
      node_line = "{nodeIndex}/{nodeCount} - {nodeTitle}",
      gold_line = "보유 골드: {gold}G",
      node = {
        combat = "전투",
        elite = "엘리트",
        boss = "보스"
      },
      button = {
        start_combat = "전투 시작",
        enter_node = "노드 진행"
      },
      status = {
        ready = "전투를 시작할 수 있습니다.",
        deck_invalid = "덱이 유효하지 않습니다. 카드 관리에서 수정하세요.",
        deck_missing = "기본 덱이 없습니다.",
        selected = "선택됨: {nodeTitle}",
        select_invalid = "현재 깊이에서 선택할 수 없는 노드입니다.",
        select_blocked = "해당 선택은 스테이지 구성 제약과 충돌합니다."
      }
    },
    shop = {
      title = "상점",
      gold_line = "보유 골드: {gold}G",
      mode = {
        buy = "카드 구매",
        upgrade = "카드 강화",
        remove = "카드 제거"
      },
      button = {
        buy = "구매",
        buy_upgrade = "강화 ({price}G)",
        buy_remove = "제거 ({price}G)",
        leave = "떠나기"
      },
      row = {
        level = "강화 레벨: {level}"
      },
      status = {
        ready = "상점에서 1회 행동을 선택하세요.",
        not_enough_gold = "골드가 부족합니다.",
        buy_ok = "{card} 구매 완료 (남은 골드: {gold}G)",
        buy_fail = "구매 실패: {reason}",
        upgrade_ok = "{card} 강화 완료 (Lv.{level})",
        remove_ok = "{card} 제거 완료",
        remove_fail = "카드 제거에 실패했습니다."
      }
    },
    rest = {
      title = "휴식",
      subtitle = "무료로 카드 강화 또는 카드 제거 중 하나를 선택하세요.",
      mode = {
        upgrade = "무료 강화",
        remove = "무료 제거"
      },
      row = {
        level = "강화 레벨: {level}"
      },
      button = {
        upgrade = "강화",
        remove = "제거"
      },
      status = {
        ready = "휴식 보너스를 선택하세요.",
        upgrade_ok = "{card} 강화 완료 (Lv.{level})",
        remove_ok = "{card} 제거 완료",
        remove_fail = "카드 제거에 실패했습니다.",
        deck_empty = "덱이 비어 있어 휴식 효과를 적용하지 못했습니다."
      }
    },
    deck_clean = {
      title = "덱 정리",
      subtitle = "카드 1장을 무료로 제거할 수 있습니다.",
      button = {
        remove = "제거"
      },
      status = {
        ready = "제거할 카드를 선택하세요.",
        remove_ok = "{card} 제거 완료",
        remove_fail = "카드 제거에 실패했습니다.",
        deck_empty = "덱이 비어 있어 덱 정리 효과를 건너뜁니다."
      }
    },
    event = {
      title = "이벤트",
      desc = "결정을 선택하세요.",
      gold_line = "보유 골드: {gold}G",
      status = {
        ready = "이벤트 선택지를 고르세요.",
        gold_gain = "골드 +{gold}",
        gold_lose = "골드 -{gold}",
        temp_applied = "임시 효과가 적용되었습니다.",
        upgrade_random = "{card} 강화 완료 (Lv.{level})",
        remove_random = "{card} 제거 완료",
        remove_n_ok = "카드 {count}장 제거 완료",
        deck_empty = "덱에 카드가 없습니다.",
        not_enough_gold = "골드가 부족합니다.",
        rare_missing = "희귀 카드 풀이 비어 있습니다.",
        buy_fail = "카드를 구매할 수 없습니다.",
        buy_rare_ok = "{card} 희귀 카드를 구매했습니다.",
        duplicate_ok = "{card} 복제 성공",
        duplicate_fail = "복제에 실패했습니다."
      },
      table = {
        event_gold_or_draw_penalty = {
          title = "의문의 제안",
          desc = "낯선 상인이 거래를 제안합니다.",
          choice_gain_gold = "골드 +30",
          choice_lose_draw = "다음 전투 드로우 -1"
        },
        event_upgrade_or_remove = {
          title = "대장간",
          desc = "대장장이가 단 한 번 도와줄 수 있다고 합니다.",
          choice_upgrade = "무작위 카드 강화",
          choice_remove = "무작위 카드 제거"
        },
        event_rare_offer = {
          title = "암시장",
          desc = "희귀 카드를 구매할 기회입니다.",
          choice_buy = "희귀 카드 구매 (30G)",
          choice_gain_gold = "거래 거절하고 골드 +20"
        },
        event_mystery_fight = {
          title = "수상한 소리",
          desc = "앞길에서 강한 적의 기척이 느껴집니다.",
          choice_fight = "정체불명 전투(엘리트)",
          choice_skip = "우회하고 골드 +15"
        },
        event_duplicate_or_gold = {
          title = "복제 장치",
          desc = "덱의 카드를 복제하거나 보상을 받을 수 있습니다.",
          choice_duplicate = "무작위 카드 복제",
          choice_gain_gold = "안전하게 골드 +25"
        },
        event_remove_two_or_lose_gold = {
          title = "무거운 짐",
          desc = "덱을 가볍게 하거나 통행료를 내야 합니다.",
          choice_remove_two = "카드 2장 제거",
          choice_lose_gold = "골드 -20"
        }
      }
    },
    combat = {
      title = "싱글 전투",
      subtitle = "드래그로 알을 쏘고 상대를 전부 탈락시키세요.",
      node_line = "노드: {nodeType} ({nodeId})",
      turn_owner = {
        player = "플레이어",
        ai = "AI"
      },
      info_line = "턴 {turnIndex} | {turnOwner} | 남은 시간 {remainSec}s | 샷 {shotUsed}/{shotBudget}",
      info_line_no_timer = "턴 {turnIndex} | {turnOwner} | 샷 {shotUsed}/{shotBudget}",
      status = {
        player_turn = "내 턴입니다. 알을 드래그해 발사하세요.",
        ai_turn = "상대 턴입니다.",
        ai_thinking = "AI가 조준 중입니다...",
        shot_too_short = "드래그 거리가 너무 짧습니다.",
        card_cannot_use = "지금은 해당 카드를 사용할 수 없습니다.",
        card_unsupported = "해당 카드는 현재 싱글 전투에 아직 구현되지 않았습니다.",
        card_target_invalid = "카드 대상이 유효하지 않습니다.",
        card_target_cancel = "카드 대상 선택을 취소했습니다.",
        card_used = "{card} 사용 완료",
        shot_fired = "샷 발사",
        turn_timeout = "턴 시간이 종료되어 턴이 넘어갑니다.",
        combat_win = "승리했습니다!",
        combat_lose = "패배했습니다.",
        combat_draw = "무승부입니다.",
        extra_shot = "추가 샷 기회가 남아 있습니다."
      },
      gimmick = {
        auto_rockfall = "보스 기믹: 자동 낙석",
        blackhole_pulse = "보스 기믹: 블랙홀 맥동",
        bind_random_enemy = "보스 기믹: 무작위 결박"
      }
    },
    character_select = {
      title = "초능력자 선택",
      subtitle = "당신의 초능력자를 고르세요"
    },
    wave = {
      title = "싱글 웨이브 무한모드",
      stage_line = "Stage {stage} / Wave {wave}",
      hud = {
        wave_title = "Wave",
        wave_value = "Wave {wave}",
        score_title = "Score",
        max_combo = "Max Combo: {value}",
        enemies_killed = "Enemies Killed: {value}",
        relic_title = "Relic Buff",
        deck_title = "덱존",
        deck_count = "Draw {drawCount} | Discard {discardCount}\nHand {handCount}/{handMax}"
      },
      status = {
        profile_recovered = "싱글 프로필을 복구해 로드했습니다.",
        intro_playing = "런 시작 연출 재생 중...",
        wave_start = "Wave {wave} 시작",
        run_end = "런이 종료되었습니다."
      },
      upgrade = {
        title = "업그레이드 선택",
        subtitle = "3개 중 1개를 선택하고 확정하세요.",
        category = {
          card = "카드",
          relic = "유물",
          hand_ops = "패조작"
        },
        button = {
          confirm = "확정",
          reopen = "업그레이드 다시 열기"
        },
        status = {
          choose = "업그레이드를 선택하세요.",
          select_required = "선택 후 확정할 수 있습니다.",
          reopen_required = "업그레이드 선택이 필요합니다.",
          card_to_hand = "카드를 손패에 추가했습니다.",
          card_to_deck = "손패가 가득 차 덱에 추가 후 셔플했습니다.",
          relic_added = "유물을 획득했습니다.",
          god_relic_added = "갓 유물을 획득했습니다.",
          relic_skip = "이미 보유 중인 유물이라 적용되지 않았습니다.",
          hand_op_applied = "패조작 효과를 적용했습니다.",
          apply_failed = "업그레이드 적용에 실패했습니다."
        },
        hand_op = {
          hand_draw_one = {
            title = "빠른 드로우",
            desc = "덱에서 카드 1장을 즉시 뽑습니다."
          },
          hand_draw_two = {
            title = "연속 드로우",
            desc = "덱에서 카드 2장을 즉시 뽑습니다."
          },
          hand_shuffle_deck = {
            title = "덱 셔플",
            desc = "현재 드로우 덱을 즉시 셔플합니다."
          },
          hand_recycle_discard = {
            title = "버림 더미 회수",
            desc = "버림 더미를 덱으로 되돌려 셔플합니다."
          }
        }
      },
      pause = {
        title = "일시정지",
        button = {
          resume = "계속하기",
          lobby = "로비로",
          reset = "리셋",
          settings = "환경설정"
        },
        status = {
          settings_saved = "환경설정을 저장했습니다."
        }
      },
      result = {
        lose = "런 실패",
        draw = "런 무승부",
        subtitle = "리셋 또는 로비 복귀를 선택하세요."
      }
    },
    relic_reward = {
      title = "릴릭 보상",
      subtitle = "릴릭 3개 중 1개를 선택하세요.",
      rarity_line = "등급: {rarity}",
      button = {
        confirm = "릴릭 획득"
      },
      status = {
        choose_one = "획득할 릴릭을 선택하세요.",
        select_required = "릴릭을 먼저 선택하세요.",
        selected = "선택됨: {relic}",
        picked = "릴릭 획득: {relic}",
        skip_empty = "획득 가능한 릴릭이 없어 다음 단계로 진행합니다."
      }
    },
    relic = {
      name = {
        relic_draw_plus = "집중의 깃털",
        relic_gold_mul = "황금 주머니",
        relic_stable_hand = "안정된 손놀림",
        relic_minor_power = "미세 증폭기",
        relic_coin_pouch = "동전 주머니",
        relic_power_plus = "출력 증폭 코어",
        relic_tactical_draw = "전술 메모",
        relic_merchant_emblem = "상인의 문장",
        relic_overclock_core = "오버클록 코어",
        relic_kings_trophy = "왕의 전리품"
      },
      desc = {
        relic_draw_plus = "전투 시작 시 드로우 +1",
        relic_gold_mul = "전투 골드 획득량 1.2배",
        relic_stable_hand = "전투 시작 시 드로우 +1",
        relic_minor_power = "최대 샷 파워 1.05배",
        relic_coin_pouch = "전투 골드 획득량 1.15배",
        relic_power_plus = "최대 샷 파워 1.10배",
        relic_tactical_draw = "전투 시작 시 드로우 +2",
        relic_merchant_emblem = "전투 골드 획득량 1.25배",
        relic_overclock_core = "최대 샷 파워 1.20배, 드로우 +1",
        relic_kings_trophy = "전투 골드 획득량 1.40배, 드로우 +1"
      }
    },
    reward = {
      title = "전투 보상",
      subtitle = "카드 3장 중 1장을 선택하세요.",
      button = {
        confirm = "선택 적용"
      },
      status = {
        choose_one = "보상 카드를 선택하세요.",
        select_required = "카드를 먼저 선택하세요.",
        profile_invalid = "프로필 데이터가 올바르지 않습니다.",
        deck_missing = "기본 덱이 없습니다.",
        add_skipped = "덱 제한으로 보상 카드 추가를 건너뛰었습니다.",
        picked = "보상 카드 선택: {card}",
        selected = "선택 카드 #{index}",
        save_failed = "저장 실패: {error}"
      }
    },
    discard = {
      title = "카드 버리기",
      subtitle = "덱 크기 {deckSize}/{maxSize} - 1장을 버려야 진행할 수 있습니다.",
      button = {
        confirm = "선택 카드 버리기"
      },
      status = {
        guide = "버릴 카드를 선택한 뒤 확정하세요.",
        deck_missing = "기본 덱이 없습니다.",
        select_required = "버릴 카드를 선택하세요.",
        remove_fail = "카드 제거에 실패했습니다.",
        selected = "선택됨: {card}",
        save_failed = "저장 실패: {error}"
      }
    },
    discard_overlay = {
      title = "카드가 너무 많습니다",
      message = "덱 상한({maxSize})을 초과했습니다. 버릴 카드를 1장 선택하세요.",
      button = {
        confirm = "확정"
      },
      status = {
        select_required = "버릴 카드를 먼저 선택하세요.",
        selected = "선택됨: {card}",
        discard_failed = "카드 제거에 실패했습니다."
      }
    },
    result = {
      title = "런 결과",
      title_win = "승리",
      title_lose = "패배",
      subtitle_win = "다음 단계로 진행합니다.",
      subtitle_lose = "캠페인 화면으로 복귀합니다.",
      button = {
        proceed = "진행"
      }
    },
    reason = {
      invalid_deck = "유효하지 않은 덱입니다.",
      unknown_card_id = "알 수 없는 카드입니다.",
      duplicate_limit = "같은 카드는 3장까지만 넣을 수 있습니다.",
      duplicate_limit_exceeded = "같은 카드가 허용 수량을 초과했습니다.",
      owned_count = "보유 수량을 초과해 추가할 수 없습니다.",
      owned_count_exceeded = "덱이 보유 수량 제한을 초과했습니다.",
      deck_full = "덱이 가득 찼습니다.",
      deck_size_exceeded = "덱 크기가 최대치를 초과했습니다.",
      deck_too_small = "덱 크기가 최소 조건(5장)보다 작습니다."
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
      server_error_event = "서버 이벤트 오류: {message}",
      ability_use_submit = "초능력 발동 요청 중...",
      ability_not_charged = "초능력이 아직 충전되지 않았습니다",
      cannot_use_ability_now = "지금은 초능력을 사용할 수 없습니다"
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
    subtitle = "충격파(1): {shockwave} | 상대 무적(2): {invincible} | 갓유물(3~7) | 8: GOD 초기화 | R: 리셋 | ESC: 로비",
    back_button = "뒤로",
    god_debug_title = "갓 유물 디버그",
    god_debug_hint = "버튼/단축키(3~7)로 스택 추가, 8로 초기화",
    god_debug_empty = "획득한 갓 유물이 없습니다.",
    status = {
      entered = "더미 모드: 드래그 발사 / 1=충격파 / 2=상대 무적 / R=리셋",
      exited = "싱글 더미 테스트 종료",
      drag_too_short = "드래그 거리가 너무 짧습니다.",
      reset_done = "더미 상태를 초기화했습니다.",
      shockwave_toggle = "충격파 토글: {value}",
      invincible_toggle = "상대 무적 토글: {value}",
      god_relic_added = "갓 유물 추가: {name} (x{count})",
      god_relic_cleared = "갓 유물 디버그 스택을 초기화했습니다."
    }
  },
  record = {
    title = "전적 기록",
    stats_line = "승: {wins} / 패: {losses} / 총 {total}경기 (승률 {rate})",
    character_stats_title = "캐릭터별 전적",
    character_stats_line = "{character}: {played}전 {wins}승 (승률 {rate})",
    recent_title = "최근 10경기",
    result_win = "승",
    result_loss = "패",
    no_records = "기록이 없습니다."
  }
}

return LocaleKo
