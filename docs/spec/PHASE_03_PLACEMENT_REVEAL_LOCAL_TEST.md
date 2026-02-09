# PHASE_03_PLACEMENT_REVEAL_LOCAL_TEST

## 1) 서버 실행

```bash
npm run dev
```

## 2) 클라이언트 2개 실행

```powershell
love .
```

## 3) 시나리오

1. A: `방 생성` -> 대기방 진입
2. B: `방 찾기`로 참가 -> 대기방 진입
3. A(호스트): `게임 시작` 클릭
4. 양쪽 `Match` 씬 전환 확인 (`PLACEMENT_PRIVATE`)
5. 각자 7개 클릭 배치 후 `배치 제출` 클릭
6. 양쪽 `PLACEMENT_REVEAL` 10초 표시 + 상대/내 배치 동시 표시 확인
7. 10초 후 `CARD_SELECT` 단계 진입 메시지 확인

## 4) 실패 시 체크포인트

- `not_in_phase`:
  - 잘못된 phase에서 배치 제출했는지 확인
- `invalid_placement`:
  - 7개 미만/초과, 진영 위반, 최소거리 위반 여부 확인
- 공개 타이머 미전환:
  - `match.placement.revealStart`, `match.phaseChanged` 수신 여부 확인
