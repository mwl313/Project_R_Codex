# gameplay_rules.json Guide

이 문서는 `shared/gameplay_rules.json`의 **모든 항목**을 설명합니다.
코드를 모르는 상태에서도 이 문서만 보고 밸런스를 조절할 수 있도록 작성되었습니다.

## 1) 파일 목적
- 멀티플레이/싱글플레이 공통 규칙(보드, 턴, 물리, 채팅 제한)을 한 곳에서 관리합니다.
- 클라이언트(`constants.lua`)와 서버(`src/rules.ts`)가 같은 값을 읽습니다.

## 2) 수정 원칙
- 값만 수정하고 키 이름은 바꾸지 마세요.
- JSON 문법(쉼표, 따옴표, 중괄호)을 반드시 지키세요.
- 키를 추가/삭제/이름변경하면 이 README도 즉시 갱신하세요.
- 카드별 상세 수치(카드 개별 제약)는 `shared/card_rules.json`도 함께 확인하세요.

## 3) 전체 항목 설명

### A. 버전/식별

- `RULES_VERSION`
  - 의미: 룰 데이터 버전 번호.
  - 단위: 정수.
  - 영향: 클라/서버 버전 불일치 시 경고 표시 기준.

- `ROOM_CODE_LENGTH`
  - 의미: 방 코드 길이.
  - 단위: 글자 수.
  - 영향: 방 생성/입장 유효성 검사.

- `ROOM_CODE_ALPHABET`
  - 의미: 방 코드 생성에 사용되는 문자 집합.
  - 단위: 문자열.
  - 영향: 사람이 읽기 쉬운 코드 체계 유지.

- `NICKNAME_MAX_LENGTH`
  - 의미: 닉네임 최대 길이.
  - 단위: 글자 수.
  - 영향: 입력 제한/저장 제한.

### B. 보드/기본 배치

- `BOARD_W`
  - 의미: 보드 너비.
  - 단위: px.
  - 영향: 배치 가능 영역, 충돌 경계.

- `BOARD_H`
  - 의미: 보드 높이.
  - 단위: px.
  - 영향: 배치 가능 영역, 충돌 경계.

- `STONE_COUNT_PER_PLAYER`
  - 의미: 플레이어 기본 돌 개수.
  - 단위: 개.
  - 영향: 시작 배치/승패 난이도.

- `STONE_RADIUS`
  - 의미: 돌 반지름.
  - 단위: px.
  - 영향: 충돌, 배치 거리, 충격파 반경 계산.

- `PLACE_GAP_PX`
  - 의미: 돌 간 추가 간격.
  - 단위: px.
  - 영향: 최소 배치 거리 계산.
  - 참고: 실제 최소 배치 거리는 `STONE_RADIUS + PLACE_GAP_PX`로 계산됩니다.

- `NO_PLACE_BUFFER`
  - 의미: 중앙선 근처 배치 금지 완충 폭.
  - 단위: px.
  - 영향: 배치 전략/초반 충돌 빈도.

### C. 페이즈/타이머

- `PLACEMENT_REVEAL_SEC`
  - 의미: 배치 공개 단계 시간.
  - 단위: 초.
  - 영향: 공개 후 전환 속도.

- `CARD_PICK_SEC`
  - 의미: 카드 선택 제한 시간.
  - 단위: 초.
  - 영향: 자동 선택 발생 빈도.

- `TURN_TIME_LIMIT_SEC`
  - 의미: 턴 제한 시간.
  - 단위: 초.
  - 영향: 턴 템포.

- `SNAPSHOT_TIMEOUT_SEC`
  - 의미: 스냅샷 대기 최대 시간.
  - 단위: 초.
  - 영향: 동기화 지연 시 강제 결과 전환 타이밍.

### D. 카드 분배 규칙(페이즈 규칙)

- `HOST_DEAL_COUNT`
  - 의미: 호스트에게 분배되는 카드 수.
  - 단위: 장.
  - 영향: 선택 폭.

- `HOST_PICK_COUNT`
  - 의미: 호스트가 확정 선택하는 카드 수.
  - 단위: 장.
  - 영향: 턴 전략 다양성.

- `GUEST_DEAL_COUNT`
  - 의미: 게스트에게 분배되는 카드 수.
  - 단위: 장.
  - 영향: 선택 폭.

- `GUEST_PICK_COUNT`
  - 의미: 게스트가 확정 선택하는 카드 수.
  - 단위: 장.
  - 영향: 턴 전략 다양성.

### E. 발사/물리

- `MAX_SHOT_POWER`
  - 의미: 발사 파워 상한.
  - 단위: 내부 파워 값.
  - 영향: 최대 속도/충돌 강도.

- `POWER_PER_PIXEL`
  - 의미: 드래그 거리(px)당 파워 증가량.
  - 단위: 파워/px.
  - 영향: 조작 민감도.

- `SHOT_SPEED_SCALE`
  - 의미: 최종 파워를 실제 속도로 변환하는 배율.
  - 단위: 배율.
  - 영향: 전체 게임 속도감.

- `PHYSICS_DAMPING_PER_SEC`
  - 의미: 초당 감쇠량.
  - 단위: 계수.
  - 영향: 클수록 빨리 감속/정지.

- `PHYSICS_RESTITUTION`
  - 의미: 반발 계수.
  - 단위: 0~1 권장.
  - 영향: 클수록 더 튐.

- `PHYSICS_STOP_SPEED`
  - 의미: 정지 판정 속도 임계값.
  - 단위: 속도.
  - 영향: 시뮬 종료 시점.

- `PHYSICS_FIXED_STEP_SEC`
  - 의미: 물리 고정 스텝.
  - 단위: 초.
  - 영향: 정밀도/성능 균형.

- `PHYSICS_MAX_SIM_SEC`
  - 의미: 1턴 시뮬 최대 시간.
  - 단위: 초.
  - 영향: 장시간 미세 진동 방지.

### F. 장애물/충격파 공통 규칙

- `ROCK_OBSTACLE_WIDTH`
  - 의미: 낙석 장애물 가로 길이 기본값.
  - 단위: px.
  - 영향: 길막 범위.

- `ROCK_OBSTACLE_HEIGHT`
  - 의미: 낙석 장애물 세로 길이 기본값.
  - 단위: px.
  - 영향: 길막 범위.

- `ROCK_OBSTACLE_MARGIN`
  - 의미: 장애물의 보드 경계 최소 여유.
  - 단위: px.
  - 영향: 경계 배치 허용 범위.

- `SHOCKWAVE_RANGE_MULTIPLIER`
  - 의미: 충격파 반경 배수.
  - 단위: 배율.
  - 영향: 실제 반경 = `STONE_RADIUS * SHOCKWAVE_RANGE_MULTIPLIER`.

- `SHOCKWAVE_STRENGTH`
  - 의미: 충격파 힘.
  - 단위: 내부 힘 값.
  - 영향: 주변 돌 밀어내기 강도.

### G. 채팅/스팸 제한

- `CHAT_MAX_LENGTH`
  - 의미: 채팅 최대 길이.
  - 단위: 글자 수.
  - 영향: 입력/서버 검증 제한.

- `CHAT_RATE_WINDOW_SEC`
  - 의미: 레이트리밋 계산 윈도우 길이.
  - 단위: 초.
  - 영향: 제한 민감도.

- `CHAT_RATE_MAX_MSG`
  - 의미: 윈도우 내 허용 메시지 수.
  - 단위: 개.
  - 영향: 스팸 허용량.

- `CHAT_RATE_BURST`
  - 의미: 순간 버스트 추가 허용량.
  - 단위: 개.
  - 영향: 단기 연속 전송 허용 폭.

## 4) 변경 후 필수 점검
1. 서버 실행: `npm run dev`
2. 클라이언트 2개 실행
3. 방 생성/입장/매치 1판 완료
4. 타이머/물리/채팅 제한이 의도대로인지 확인
5. 카드 수치 변경 시 `shared/card_rules.json`과 함께 확인

## 5) 관련 파일
- 데이터: `shared/gameplay_rules.json`
- 서버 로더: `src/rules.ts`
- 클라 로더: `constants.lua`
- 카드 데이터: `shared/card_rules.json`

## 6) 문서 동기화 규칙
- `gameplay_rules.json`의 키가 바뀌면 이 README를 **같은 커밋에서** 업데이트합니다.
- `card_rules.json` 키 변경 시 `card_rules.README.md`도 같은 원칙으로 업데이트합니다.
