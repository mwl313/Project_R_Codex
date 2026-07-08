# Tasks: 초능력 알까기 Phase 1

## Dependency Order

```
Task 1: characters.json (SSOT)
    │
    ├─→ Task 2: constants.lua (신규 상수)
    │       │
    │       ├─→ Task 4: charge_gauge.lua (UI 위젯)
    │       ├─→ Task 5: abilities.lua (초능력 효과)
    │       └─→ Task 8: game_mechanics.lua (충전 콜백)
    │
    ├─→ Task 3: gameplay_rules.json (룰 상수)
    │       │
    │       └─→ Task 7: match_scene.lua (메인 씬 통합)
    │
    ├─→ Task 6: character_select_scene.lua (선택 씬)
    │
    └─→ Task 9: room_do.ts (서버 수정)
            │
            └─→ Task 10: abilities.ts (서버 검증)
```

## Task List

### Task 1: shared/characters.json [SSOT 데이터]

- [ ] 4종 캐릭터 정의 (나이트로드/아크메이지/팔라딘/아란)
- [ ] 각 초능력 정의 (id, nameKo, descKo, targetMode, effects)
- [ ] 글로벌 충전 파라미터 (chargePerTurn, chargeOnAllyOut, chargeMax)
- Acceptance: JSON parse error 없음, 모든 키가 DESIGN_DOC.md와 일치
- Verify: 수동으로 `luajit -e 'require("json").decode(io.open("shared/characters.json"):read("*a"))'` 통과
- Files: `shared/characters.json` (신규)
- Estimated: ~80줄

### Task 2: constants.lua + gameplay_rules.json [상수 정리]

- [ ] `PHASE_CARD_SELECT` 제거, `PHASE_CHARACTER_SELECT` 추가
- [ ] 충전 관련 상수 추가 (CHARGE_PER_TURN 등, gameplay_rules.json에서 로드)
- [ ] `TURN_TIME_LIMIT_SEC` 30→20
- [ ] 싱글 전용 카드 관련 상수 정리 (제거 아님, 미사용 주석)
- Acceptance: `love .` 실행 시 에러 없음, 기존 페이즈 enum 충돌 없음
- Verify: `love .` 실행 → 로비 진입 가능
- Files: `constants.lua` (수정), `shared/gameplay_rules.json` (수정)
- Estimated: ~40줄

### Task 3: ui/charge_gauge.lua [충전 게이지 위젯]

- [ ] `ChargeGauge.new(params)` — 캐릭터 정보 + 충전값 받는 위젯
- [ ] 원형 게이지 + 퍼센트 숫자 + 초능력 버튼
- [ ] `update(dt, chargePercent, mouseX, mouseY)` — 애니메이션 + 호버
- [ ] `draw()` — 게이지 + 버튼 렌더링
- [ ] `mousepressed(mx, my, button)` — 버튼 클릭 감지
- [ ] 충전 100% 시 버튼 활성화 + 펄스 효과
- Acceptance: 단독 씬에서 충전 게이지가 렌더링되고 100% 시 버튼 활성화
- Verify: 임시 테스트 씬에서 수동 확인
- Files: `ui/charge_gauge.lua` (신규)
- Estimated: ~120줄

### Task 4: abilities.lua [초능력 효과 리팩터]

- [ ] 기존 카드 5종 효과 함수 유지 (멀티 대전용 백업)
- [ ] 초능력 4종 발동 함수 추가:
  - `executeShadowStep(match, playerIndex, targetX, targetY)`
  - `executeMeteor(match)`
  - `executeDivineShield(match, playerIndex)`
  - `executeComboFinisher(match, playerIndex)`
- [ ] `isAbilityReady(match, playerIndex)` → 충전 상태 확인
- [ ] `getAbilityDef(characterId)` → characters.json에서 조회
- Acceptance: 함수 시그니처가 match_scene.lua에서 호출 가능
- Verify: 단위 함수 호출로 nil 체크
- Files: `abilities.lua` (수정)
- Estimated: ~100줄

### Task 5: game_mechanics.lua [충전 상태 관리]

- [ ] `initChargeState(matchContext)` — 매치 시작 시 초기화
- [ ] `advanceTurnCharge(matchContext, playerIndex)` — 턴 시작 시 충전
- [ ] `onAllyOut(matchContext, playerIndex)` — 아군 아웃 시 추가 충전
- [ ] `canUseAbility(matchContext, playerIndex)` → bool
- [ ] `consumeCharge(matchContext, playerIndex)` — 사용 후 0% 리셋
- Acceptance: 충전값이 0→25→50→75→100 순으로 증가하고 -0% 리셋
- Verify: game_mechanics_test.lua (간단한 스크립트)에서 검증
- Files: `game_mechanics.lua` (수정)
- Estimated: ~60줄

### Task 6: scenes/character_select_scene.lua [캐릭터 선택]

- [ ] 4종 캐릭터 카드 표시 (초상화+이름+초능력 설명)
- [ ] 호버 시 하이라이트 + 상세 설명
- [ ] 클릭 시 선택 → 로비로 캐릭터 정보 전달
- [ ] BackButton (로비로 돌아가기)
- Acceptance: 선택한 캐릭터 ID가 lobby_scene 또는 match_scene에 전달됨
- Verify: 씬 전환 후 params 확인
- Files: `scenes/character_select_scene.lua` (신규)
- Estimated: ~150줄

### Task 7: scenes/match_scene.lua [메인 씬 통합]

- [ ] PHASE_CARD_SELECT 관련 코드 제거
- [ ] 초능력 충전 상태 추가 (`_chargePercent[1]`, `_chargePercent[2]`)
- [ ] ChargeGauge 위젯 연결 (하단 패널에 표시)
- [ ] 샷 이후 충전 업데이트 콜백
- [ ] 초능력 발동 버튼 → 서버 메시지 전송
- [ ] 서버에서 `ability_result` 수신 시 효과 적용
- [ ] 상대 초능력 발동 시 연출 표시
- Acceptance: 2클라이언트에서 캐릭터 선택→배치→턴→초능력→승패 완주
- Verify: 수동 2클라이언트 테스트
- Files: `scenes/match_scene.lua` (수정)
- Estimated: ~200줄 (주로 제거 + 추가)

### Task 8: server/src/room_do.ts [서버 로직]

- [ ] `CARD_SELECT` 페이즈 및 관련 상태 제거
- [ ] `character_select` 메시지 처리 추가
- [ ] `ability_action` 메시지 처리 추가 (검증 + 브로드캐스트)
- [ ] 충전 상태를 `snapshot`에 포함
- [ ] `turn_change` 시 충전값 증가 로직
- Acceptance: 서버가 초능력 액션을 수신하고 양 클라에 브로드캐스트
- Verify: `npx wrangler dev` + 클라이언트 연결 테스트
- Files: `server/src/room_do.ts` (수정)
- Estimated: ~100줄 (제거 + 추가)

### Task 9: server/src/abilities.ts [서버 초능력 검증]

- [ ] `validateAbilityAction(room, playerIndex, abilityId, target?)` → bool
- [ ] `applyAbilityEffect(room, playerIndex, abilityId, target?)` → EffectResult
- [ ] 각 초능력별 서버 측 효과 계산
- Acceptance: 서버에서 초능력 효과가 물리적으로 올바르게 적용됨
- Verify: `npx wrangler dev` + 유닛 테스트
- Files: `server/src/abilities.ts` (수정)
- Estimated: ~80줄

### Task 10: Integration & Polish [통합 마무리]

- [ ] app.lua 씬 라우팅 업데이트
- [ ] lobby_scene.lua에서 캐릭터 선택으로 연결
- [ ] i18n 키 추가 (한국어/영어)
- [ ] 불필요한 싱글플레이 참조 정리
- [ ] 전체 흐름 테스트: 선택→배치→턴→초능력→승패
- Acceptance: 룸 생성부터 승패까지 전체 플로우 완주
- Verify: 2클라이언트 end-to-end 수동 테스트
- Files: `app.lua`, `lobby_scene.lua`, `i18n/*.json` (수정)
- Estimated: ~50줄
