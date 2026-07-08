# Spec: 초능력 알까기 — Phase 1 알파

## Objective
멀티플레이어 전용 초능력 알까기 시스템의 알파 버전을 구현한다.
카드 선택 페이즈를 제거하고, 4종 캐릭터 + 충전식 초능력 시스템으로 교체한다.
친구와 1v1 대전이 가능한 최소 기능 상태를 목표로 한다.

## Tech Stack
- 클라이언트: LÖVE2D 11.x + Lua 5.1+ (jit)
- 서버: Cloudflare Workers + Durable Objects (TypeScript)
- 데이터: JSON SSOT (`shared/*.json`)
- 도구: Cline CLI (deepseek-chat / Flash) + Aria (DeepSeek V4 Pro)

## Commands
- Run: `love .` (프로젝트 루트에서)
- Lint: `luacheck .` (존재하는 경우)
- Server deploy: `npx wrangler deploy` (server/ 디렉토리)
- Test: N/A (LÖVE2D Lua 프로젝트, 수동 실행 테스트)

## Project Structure
```
ProjectR/
├── shared/
│   ├── characters.json          # [신규] 캐릭터·초능력 정의
│   ├── gameplay_rules.json      # [수정] TURN_TIME_LIMIT_SEC 30→20, 신규 상수 추가
│   └── card_rules.json          # [축소] 멀티 전용만 유지
├── constants.lua                # [수정] 신규 페이즈·상수 추가
├── game_mechanics.lua           # [수정] 충전 상태 관리
├── abilities.lua                # [수정] 4종 초능력으로 리팩터
├── scenes/
│   ├── character_select_scene.lua  # [신규]
│   └── match_scene.lua             # [대수정]
├── ui/
│   └── charge_gauge.lua            # [신규]
└── server/src/
    ├── room_do.ts                   # [수정] 카드 페이즈 제거, 초능력 추가
    └── abilities.ts                 # [수정] 초능력 서버 검증
```

## Boundaries
- Always: 기존 물리 엔진·서버 통신·매칭 시스템 보존, SSOT JSON으로 데이터 관리
- Ask first: 싱글플레이 코드 제거 여부, 서버 재배포 시점
- Never: 물리 상수 변경, 싱글플레이 파일 임의 삭제

## Success Criteria
- [x] 캐릭터 선택 화면에서 4종 중 선택 가능
- [x] 선택한 캐릭터의 초능력이 충전 게이지와 함께 표시됨
- [x] 충전 게이지가 매 턴 25%씩 차고, 내 알 아웃 시 +15%
- [x] 충전 100% 시 초능력 버튼 활성화, 사용 시 0% 리셋
- [x] 카드 선택 페이즈가 완전히 제거됨
- [x] 서버가 초능력 액션을 검증하고 브로드캐스트함
- [x] 로컬에서 2클라이언트 열어서 1판 완주 가능

## Open Questions
- 없음 (DESIGN_DOC.md에 모두 결정됨)
