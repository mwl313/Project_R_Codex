# ProjectR (알까기)

LÖVE 11.x 클라이언트 + Cloudflare Workers + Durable Objects 서버 기반 2인 대전 MVP 프로젝트입니다.

## 실행 방법

### 1) 서버 실행 (Workers)

```bash
npm install
npm run dev
```

- 기본 로컬 주소: `http://127.0.0.1:8787`

### 2) 클라이언트 실행 (LÖVE)

```bash
love .
```

- 2인 테스트는 클라이언트를 2개 실행해서 진행합니다.

## 현재 구현 상태 (Phase별)

### Phase 0 (SPEC/SSOT)

- `docs/spec/` 아래 스펙 문서 체계 구성
- `docs/spec/INDEX.md`로 스펙/테스트 문서 인덱싱
- 네이밍 규칙 문서 반영: `docs/spec/naming_convention.md`

### Phase 1 (서버 최소 골격)

- HTTP 엔드포인트 구현
- `GET /health`
- `POST /room/create`
- `POST /room/join`
- WS 업그레이드 구현
- `GET /ws?code=...&token=...`
- Durable Object 룸 상태 관리
- `roomCode`, `host/guest token`, `phase`, `timers`, `chatLimiter`
- 기본 브로드캐스트 이벤트
- `room.state`, `room.joined`, `room.left`, `room.closed`
- `chat.message`, `chat.denied`
- 룸 코드 정책
- 16자리 코드, 가독성 문자셋 사용 (`O/0`, `I/1` 제외 계열)

### Phase 2 (클라이언트 매칭~대기방)

- 로비 메뉴 구현
- `싱글플레이어`(수동 테스트용 더미 씬), `방 생성`, `방 찾기`, `닉네임 변경`, `환경설정`, 기타 메뉴
- 오버레이(팝업) 기반 설정 UI
- 닉네임 변경 오버레이 (70%)
- 환경설정 오버레이 (70%)
- 디스플레이 모드 드롭다운
- 창모드 `1280x720` 고정
- 전체화면 `현재 모니터 해상도`
- 영구 저장
- `love.filesystem.setIdentity("project_r")`
- `settings.ini` 로드/저장 (`project_r` save directory)
- 한글 폰트/입력 안정화
- 공용 FontManager (`title/ui/small`)
- 폰트 누락 시 기본 폰트 폴백 + 경고
- UTF-8 안전 TextInput + IME 조합 표시
- 대기방 기능
- 룸 코드 복사 버튼
- 채팅 송수신
- 나가기/상태 표시
- 방 찾기 기능
- 룸 코드 입력 및 참가
- 클립보드 붙여넣기 버튼

### Phase 3 (게임 플로우)

- 페이즈 진행
- `PLACEMENT_PRIVATE -> PLACEMENT_REVEAL -> CARD_SELECT -> PLAYING -> RESULT`
- 배치 단계
- 클릭 배치, 최소 거리 체크, 제출
- 공개 타이머 후 전환
- 카드 선택
- 호스트 2장 중 1장 선택
- 게스트 3장 중 2장 선택
- 제한시간 자동 선택
- 플레이 단계
- 턴 시작/종료, 30초 타이머
- 드래그 조준/발사/취소
- 서버 권위 턴 단위 스냅샷 정산
- 호스트 스냅샷 제출, 양측 동기화
- 결과 단계
- 승/패/무 처리
- `재대결` / `로비로` 투표 전환
- 기권 버튼 및 `surrender` 결과 처리

### Phase 4 (카드 효과 구현 상태)

- `reinforcement` (신병)
- 타겟 지정 후 보드 클릭 배치
- 생성 알은 해당 턴 발사 제한
- `rockfall` (낙석)
- 보드 클릭으로 장애물 생성
- `invincible` (무적)
- 다음 턴 방어 상태 적용
- 무적 돌 충돌 시 비무적 돌 반사 중심으로 처리
- `shockwave` (충격파)
- 발사된 돌 기반 발동
- 돌-벽/돌-돌/돌-장애물 충돌 시 반복 발동
- 발산 중심: 발사된 돌 중심
- 반경: `STONE_RADIUS * 4.0`
- 위력: `200`
- 발사 돌 본인은 충격파 영향 제외
- 무적 돌은 충격파 영향 제외
- `agile` (날렵함)
- 동일 턴 추가 발사(2회) 지원

### Phase 5 (Asset/Polish 일부)

- 사운드 훅 시스템 추가
- 중앙 관리: `managers/sound_manager.lua`
- 주요 HTTP/WS/매치 이벤트에서 훅 ID 재생
- 파일 규칙: `assets/sounds/<hookId>.(ogg|wav|mp3)`
- 사운드 파일이 없어도 no-op으로 정상 진행(크래시 없음)

## 이펙트 구조

- 공용 이펙트 매니저 추가: `effects/effect_manager.lua`
- 현재 구현 이펙트
- 충격파 원형 파동(임시 시각효과)
- MatchScene에서 이펙트 생성/업데이트/렌더를 매니저에 위임

## 메커니즘 구조 (클라 1단계 공통화)

- 공용 진입점: `game_mechanics.lua`
- 물리 코어: `physics_engine.lua`
- 멀티 씬(`scenes/match_scene.lua`)과 싱글 더미 씬(`scenes/single_dummy_scene.lua`)이 동일 메커니즘 진입점을 참조

## 로컬 테스트 문서

- `docs/spec/PHASE_01_SERVER_LOCAL_TEST.md`
- `docs/spec/PHASE_02_CLIENT_LOCAL_TEST.md`
- `docs/spec/PHASE_03_PLACEMENT_REVEAL_LOCAL_TEST.md`
- `docs/spec/PHASE_03_CARD_SELECT_LOCAL_TEST.md`
- `docs/spec/PHASE_03_PLAYING_LOCAL_TEST.md`
- `docs/spec/PHASE_03_RESULT_LOCAL_TEST.md`

## 참고 문서

- 스펙 인덱스: `docs/spec/INDEX.md`
- 핵심 SSOT: `docs/spec/SPEC_00_OVERVIEW.md`
