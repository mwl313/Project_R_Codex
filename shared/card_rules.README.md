# card_rules.json Guide

이 문서는 `shared/card_rules.json`을 코드 지식 없이 카드 밸런싱할 수 있게 돕는 가이드입니다.

## 1) 이 파일의 목적
- 카드별 수치/제약을 한 곳에서 관리합니다.
- 카드의 실제 행동 로직은 코드(`abilities.lua`, `src/abilities.ts`)에 남기고,
  밸런스 숫자만 JSON으로 조정합니다.

## 2) 수정 원칙
- 키 이름은 유지하고 값만 수정하세요.
- `enabled`는 카드 활성/비활성 토글입니다.
- `card_pool` 순서가 실제 카드 분배 풀의 기준이 됩니다.
- JSON 문법(쉼표, 따옴표) 오류가 나면 게임이 기본값으로 폴백됩니다.

## 3) 카드별 항목 설명

### card_pool (카드 분배 풀)
- 카드 분배 단계에서 섞는 전체 카드 ID 목록입니다.
- 여기 있는 항목 수가 카드 풀 총량(`totalPoolCount`)이 됩니다.
- 중복 없이 쓰는 것을 권장합니다.
- 카드 ID 문자열은 아래 `cards` 섹션의 키와 일치해야 합니다.

### reinforcement (신병)
- `enabled`: 카드 사용 가능 여부
- `min_place_distance`: 다른 돌과 최소 거리
- `lock_spawned_stone_for_turn`: 이번 턴 이동 금지 여부

### shockwave (충격파)
- `enabled`: 카드 사용 가능 여부
- `radius_multiplier`: 충격파 반경 배수 (실반경 = 돌 반지름 * 배수)
- `strength`: 충격파 밀어내기 힘
- `exclude_source_stone`: 발사 원본 돌 제외 여부
- `ignore_invincible_targets`: 무적 대상 제외 여부

### invincible (무적)
- `enabled`: 카드 사용 가능 여부
- `protect_after_turn_offset`: 보호가 적용되는 턴 오프셋

### rockfall (낙석)
- `enabled`: 카드 사용 가능 여부
- `width`: 장애물 가로
- `height`: 장애물 세로
- `margin`: 보드 경계 여유

### agile (날렵함)
- `enabled`: 카드 사용 가능 여부
- `shot_budget`: 해당 턴 허용 샷 수

## 4) 변경 후 점검
1. 로비 -> 방 생성/참가
2. 카드 선택에서 분배 카드 개수/선택 개수가 의도대로인지 확인
3. 카드 사용 시 범위/강도/제약이 의도대로인지 확인
4. 서버/클라 모두 같은 결과가 나오는지 확인

## 5) 관련 파일
- 데이터: `shared/card_rules.json`
- 서버 적용: `src/card_rules.ts`, `src/abilities.ts`
- 클라 적용: `shared/card_rules.lua`, `abilities.lua`

## 6) 유지보수 규칙
- `card_rules.json` 키를 변경/추가/삭제하면 이 README도 즉시 갱신합니다.
