# ProjectR (알까기)

LÖVE 11.x 클라이언트와 Cloudflare Workers + Durable Objects 서버로 구성된 2인 대전 프로젝트입니다.  
현재 멀티플레이 핵심 루프(방 생성/참가 -> 대기방 -> 매치 진행 -> 결과/재대결)가 동작합니다.

## 빠른 시작

### 서버 실행 (로컬)

```bash
cd server
npm install
npm run dev
```

- 기본 로컬 서버: `http://127.0.0.1:8787`

### 클라이언트 실행

```bash
love .
```

- 멀티 테스트는 클라이언트를 2개 실행해서 진행합니다.

### 기본 점검 명령

```bash
npm --prefix server run typecheck
npm --prefix server test
node tools/i18n_audit.js
```

## 핵심 기능

### 1) 로비/메뉴/오버레이 UI

- 로비 메뉴: `플레이`, `닉네임 변경`, `환경설정`, `가이드`, `스킨`, `크레딧`, `게임 종료`
- 플레이 메뉴 분기:
  - `싱글플레이어`(더미 테스트용)
  - `멀티플레이어`
- 멀티플레이어 메뉴 분기:
  - `방 생성`
  - `방 찾기`
- 닉네임/환경설정은 씬이 아닌 오버레이(70%)로 동작
- 환경설정:
  - 창모드 `1280x720` 고정
  - 전체화면 `현재 모니터 해상도`
  - 언어 선택(`ko`, `en`)
- 설정 저장:
  - `love.filesystem.setIdentity("project_r")`
  - `settings.ini`에 영구 저장

### 2) 네트워크 (HTTP long-poll 전환 완료)

- 클라이언트 트랜스포트는 WS가 아니라 HTTP 고정
- 사용 엔드포인트:
  - `POST /room/create`
  - `POST /room/join`
  - `POST /room/send`
  - `POST /room/poll`
- long-poll 루프:
  - 항상 1개 poll in-flight 유지
  - 응답 즉시 다음 poll 재요청
  - 실패 시 지수 백오프 + 지터
- 클라이언트 내부 네트워크 이벤트:
  - `server_open`
  - `server_close`
  - `server_error`
  - `server_envelope`
- 진단 로그:
  - `[NET][POLL_REQUEST]`
  - `[NET][POLL_RESPONSE]`
  - `[NET][POLL_RESPONSE_INVALID]`
  - 환경(`serverEnv`)과 실제 base URL 같이 출력
- 디버그 메뉴에서 서버 환경 토글 지원:
  - `local` <-> `cloud`
  - 연결 중에는 변경 잠금

### 3) 대기방 기능

- 방 코드 표시 + 복사
- 호스트/게스트 역할 표시
- 게스트 `준비하기`, 호스트 `게임 시작`
- 준비/시작 조건 서버 권위 처리
- 대기방 채팅 송수신
- 나가기 처리:
  - guest leave -> host 대기 유지
  - host leave -> room closed

### 4) 매치 진행 플로우

- 진행 순서:
  - `TURN_ORDER`
  - `PLACEMENT_PRIVATE`
  - `PLACEMENT_REVEAL`
  - `CARD_SELECT`
  - `PLAYING`
  - `RESULT`
- 코인토스 연출(선공/후공 별도 씬) 후 자동 전환
- 카드 사용 컷신(서버 권위 pause/resume):
  - 카드 사용 직후 컷신 시작 이벤트 브로드캐스트
  - 컷신 재생 동안 턴 타이머 서버 일시정지
  - 컷신 종료 시 남은 시간으로 턴 타이머 재개
  - 컷신 중 샷/카드/스냅샷 입력 및 요청 차단
  - 로컬 스킵 지원(각 클라이언트 독립), 단 서버 재개 전까지 플레이 입력은 계속 차단
- 배치:
  - 클릭 배치, 최소 거리 규칙, 제출
  - 공개 타이머 후 다음 단계
- 카드 선택:
  - 선공: 2장 중 1장
  - 후공: 3장 중 2장
  - 제한시간 만료 시 자동 선택
- 플레이:
  - 턴 타이머
  - 드래그 조준/발사/취소
  - 카드 사용 규칙(턴당 1회)
- 결과:
  - 승/패/무
  - 재대결/메뉴 투표
  - 기권 처리

### 5) 카드 능력 (현재 구현)

- `reinforcement` (신병)
  - 대상 위치에 알 1개 추가
  - 추가된 알은 해당 턴 이동 제한
- `rockfall` (낙석)
  - 대상 위치에 장애물 배치
- `invincible` (무적)
  - 지정 턴 동안 방어 상태 적용
  - 충돌 시 상대만 반사되도록 처리
- `shockwave` (충격파)
  - 발사한 알 기준 충돌 시 충격파 발동
  - 반경: `STONE_RADIUS * 4.0`
  - 위력: `200`
  - 발사 알 자신/무적 알 제외
- `agile` (날렵함)
  - 같은 턴 추가 발사
  - 카드 효과 실제 반영은 카드 컷신 종료 후 서버에서 확정 적용

### 6) 인게임 채팅

- MatchScene 우하단 접힘/펼침 패널
- Enter로 열기, ESC/외부 클릭/X 버튼으로 닫기
- unread red-dot 표시
- 스크롤/스크롤바 드래그 지원
- 입력창 UTF-8/IME 경로 유지
- 카드 선택 확정 이전 UI 충돌 방지를 위한 노출 제어 적용

### 7) 입력/물리/공통 메커니즘

- 월드 좌표 기준 해상도: `1280x720`
- RenderScale 기반 screen<->world 변환 적용
- 무한 드래그(상대 마우스 모드) + 커서 복구 가드
- 예측 샷 UX(릴리즈 즉시 반응):
  - 마우스 릴리즈 즉시 로컬 발사 시작(체감 지연 최소화)
  - 서버 승인 시 고스트 상태 해제 후 확정
  - 서버 거절 시 부드러운 스냅백 롤백(짧은 입력 잠금 + 토스트)
  - 클라이언트 선검증(턴/타임아웃/샷예산/락된 알 등)으로 거절 가능성 사전 차단
- 공통 메커니즘 구조:
  - `physics_engine.lua` (물리 코어)
  - `game_mechanics.lua` (씬 공통 진입점)
  - 멀티 매치/싱글 더미가 공통 경로 사용

### 8) 폰트/로케일/i18n

- 기본 폰트: `assets/fonts/MulmaruMono.ttf`
- 공용 폰트 매니저: `assets/font_manager.lua`
- 로케일:
  - `i18n/locales/ko.lua`
  - `i18n/locales/en.lua`
  - `i18n/locales/template.lua`
- 로케일 누락 검증:
  - `node tools/i18n_audit.js`

### 9) UI 스킨/연출/디버그

- 9-slice UI 스킨 시스템(토글형)
- 씬 전환(screen wipe 계열) 적용
- 오버레이/드롭다운 등장/퇴장 연출
- 스킬 컷신 오버레이(카드별 정의 기반):
  - 정의 파일: `data/cutscene_defs.lua`
  - 재생 모듈: `ui/cutscene_manager.lua`
  - 현재는 프리미티브 기반 placeholder, 추후 카드별 에셋 교체 구조 반영
- 디버그 메뉴:
  - 단축키 `F7`
  - 씬 점프/카드존 테스트/서버 환경(local/cloud) 전환

## 서버 API 요약

### 필수 API (클라이언트 사용)

- `GET /health`
- `POST /room/create`
- `POST /room/join`
- `POST /room/send`
- `POST /room/poll`

### 호환 API (레거시)

- 서버에는 `/ws` 경로가 남아있지만, 현재 클라이언트 런타임은 사용하지 않습니다.

## 규칙/밸런스 SSOT

- 공통 규칙: `shared/gameplay_rules.json`
- 카드 수치: `shared/card_rules.json`
- 서버 로더:
  - `server/src/rules.ts`
  - `server/src/card_rules.ts`
- 클라 로더:
  - `constants.lua`
  - `shared/card_rules.lua`
- 설명 문서:
  - `shared/gameplay_rules.README.md`
  - `shared/card_rules.README.md`

## 테스트 문서

- `docs/spec/PHASE_01_SERVER_LOCAL_TEST.md`
- `docs/spec/PHASE_02_CLIENT_LOCAL_TEST.md`
- `docs/spec/PHASE_03_PLACEMENT_REVEAL_LOCAL_TEST.md`
- `docs/spec/PHASE_03_CARD_SELECT_LOCAL_TEST.md`
- `docs/spec/PHASE_03_PLAYING_LOCAL_TEST.md`
- `docs/spec/PHASE_03_RESULT_LOCAL_TEST.md`

## 문서 인덱스

- 스펙 인덱스: `docs/spec/INDEX.md`
- 핵심 개요: `docs/spec/SPEC_00_OVERVIEW.md`
- 프로토콜: `docs/spec/SPEC_03_PROTOCOL.md`
