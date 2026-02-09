# PHASE_03_CARD_SELECT_LOCAL_TEST

## 1) 서버 실행

```bash
npm run dev
```

## 2) 클라이언트 2개 실행

```powershell
love .
```

## 3) 시나리오

1. A 방 생성, B 방 참가 후 대기방에서 A가 `게임 시작` 클릭
2. 양쪽 `PLACEMENT_PRIVATE`에서 7개 배치 제출
3. `PLACEMENT_REVEAL` 5초 후 `CARD_SELECT` 진입 확인
4. 호스트는 2장 중 1장, 게스트는 3장 중 2장 선택 후 `선택 확정`
5. 양쪽 `match.cards.locked` 반영 확인
6. 양쪽 확정 후 `PLAYING` 단계 전환 확인
7. 한쪽이 선택하지 않고 15초 대기 시 자동 선택(front-first)으로 잠금되는지 확인

## 4) 실패 시 체크포인트

- `invalid_card_pick`:
  - 선택 개수(호스트 1/게스트 2), 중복 선택 여부 확인
- 카드 분배 미수신:
  - `match.cards.dealt` 이벤트 수신 확인
- 자동 선택 미동작:
  - `timers.phaseEndsAtMs`와 `CARD_PICK_SEC` 값 확인
