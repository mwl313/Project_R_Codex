# Spec: 초능력 컷신 & 이펙트

## Objective
Phase 2 폴리시 — 4종 초능력 발동 시 시각적 연출을 구현한다.
기존 `effects/effect_manager.lua`와 `ui/cutscene_manager.lua`를 확장.

## 구현 내용

### 1. 샷 트레일 (`effects/effect_manager.lua` 확장)
- `addShotTrail(stoneId)` — 샷 발사 시 궤적을 따라 점점 작아지는 원형 파티클
- `updateTrails(dt)` — 프레임마다 트레일 입자 이동·감쇠
- 입자당 수명: 0.5s, 간격: 4px 마다 생성, 알파: 0.6→0

### 2. 충돌 이펙트 (`effects/effect_manager.lua` 확장)
- `addCollisionEffect(x, y, intensity)` — 충돌 지점 방사형 파티클
- 기존 `resolveStoneCollision` / `resolveObstacleCollision` 호출 지점에 연결
- 입자 수: intensity 비례 (8~20개), 속도: 100~300, 수명: 0.3s

### 3. 초능력별 이펙트

#### 3a. 메테오 (arch_mage)
- 빛줄기: 보드 상단 → 중앙으로 세로줄 3개 (노랑/주황)
- 충격파: 기존 `addShockwavePulse()` 재활용 (×1.5 반경)
- 운석 잔해: 장애물 생성 시 6방향 파편 파티클
- 지속시간: 1.0s

#### 3b. 섀도우스텝 (night_lord)
- 출발점: 보라색 원 축소 (radius: stone_radius→0, 0.3s)
- 도착점: 보라색 원 확대 (radius: 0→stone_radius×2→stone_radius, 0.4s)
- 잔상: 출발→도착 사이에 3개 페이드아웃 원
- 색상: `{0.55, 0.30, 0.85}` 보라

#### 3c. 디바인실드 (paladin)
- 내 알 7개에 노란색 반투명 실드 링 추가
- 링 회전 (360°/2s), 알파: 0.4→0.25 펄스
- 지속시간: 2턴 (invincibleTurnByPlayer 기준)
- 충돌 시 방패 반짝임 (알파 0.8로 0.15s)

#### 3d. 콤보피니셔 (aran)
- 첫 샷 아웃 시: 슬래시 라인 (대각선 2줄, 0.4s) + 카메라 셰이크 (진폭 4px, 0.2s)
- 두 번째 샷: 파워 1.5배 표시 (UI에 "×1.5" 텍스트 0.5s)
- 색상: `{0.25, 0.60, 0.90}` 파랑

### 4. 컷신 매니저 확장 (선택)
- 초능력 발동 시 0.5s 프리즈 → 이펙트 재생 → 게임 계속
- 기존 `cutscene_manager.lua`는 카드 컷신용 — 초능력 모드 추가

## Files
| 파일 | 변경 | 
|------|------|
| `effects/effect_manager.lua` | 신규 메서드 4개 추가 (trail, collision, ability effects) |
| `abilities.lua` | `executeAbility` → 각 능력 실행 시 이펙트 호출 연결 |
| `match_scene.lua` | 컷신/이펙트 호출 지점 추가 |

## Success Criteria
- [ ] 샷 발사 시 궤적 트레일 표시
- [ ] 알 충돌 시 파티클 이펙트
- [ ] 메테오: 빛줄기 + 충격파 + 파편
- [ ] 섀도우스텝: 텔레포트 원 이펙트
- [ ] 디바인실드: 실드 링 + 충돌 반짝임
- [ ] 콤보피니셔: 슬래시 + 카메라 셰이크
