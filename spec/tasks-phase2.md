# Tasks: 초능력 알까기 Phase 2 — 폴리시 (애셋 불필요)

## Dependency Order (의존성 낮은 순)

```
Task 1: LOVE.js 웹 빌드
    │
Task 2: 초능력 컷신·이펙트 (effect_manager.lua, abilities.lua)
    │
    ├─→ Task 3: 승패 기록 (match_scene.lua, utils, 새 씬)
    │       └─→ lobby_scene.lua (버튼 추가)
    │
    └─→ Task 4: 튜토리얼 씬 (app.lua, lobby_scene.lua)
```

## Task List

### Task 1: LOVE.js 웹 빌드 파이프라인 [Infra]
- [ ] `tools/build_web.sh` — love.js 다운로드 + .love 패키징 + 웹 번들
- [ ] `.gitignore` — `build/web/` 추가
- [ ] 웹 호환성 확인 (WebSocket, love.filesystem)
- Spec: `spec/lovejs-spec.md`
- Estimated: ~50줄 (shell script)

### Task 2: 초능력 컷신·이펙트 [Visual]
- [ ] `effects/effect_manager.lua` — addShotTrail, addCollisionEffect, addMeteorEffect, addShadowStepEffect, addDivineShieldEffect, addComboFinisherEffect
- [ ] `abilities.lua` — 각 execute 함수에 이펙트 호출 연결
- [ ] `match_scene.lua` — 샷/충돌 지점에 이펙트 호출 추가
- Spec: `spec/effects-spec.md`
- Estimated: ~200줄

### Task 3: 승패 기록 [Data]
- [ ] `utils/match_history.lua` — load, save, stats
- [ ] `scenes/record_scene.lua` — 전적 UI
- [ ] `scenes/match_scene.lua` — 결과 저장 호출
- [ ] `scenes/lobby_scene.lua` — 전적 버튼
- [ ] `app.lua` — record_scene 등록
- Spec: `spec/match-history-spec.md`
- Estimated: ~250줄

### Task 4: 튜토리얼 씬 [Onboarding]
- [ ] `scenes/tutorial_scene.lua` — 5단계 튜토리얼
- [ ] `app.lua` — 씬 등록
- [ ] `scenes/lobby_scene.lua` — 튜토리얼 버튼
- Spec: `spec/tutorial-spec.md`
- Estimated: ~250줄
