# PHASE_03_RESULT_LOCAL_TEST
Date: 2026-02-09

## 목적
- `RESULT -> REMATCH/LOBBY` 투표 및 전환 규칙을 수동 검증한다.

## 사전 조건
- 서버: `npm run dev` (`project_r` 루트)
- 클라이언트 2개 실행 후 `PLAYING`을 거쳐 `RESULT` 도달

## 시나리오
1. 한쪽에서 `재대결` 버튼 클릭 후, 상대는 미투표 상태로 대기한다.
2. `room.state.result.myVote/opponentVote`가 양쪽에 반영되는지 확인한다.
3. 상대도 `재대결` 클릭 시 `match.phaseChanged`가 `RESULT -> WAITING`으로 전환되는지 확인한다.
4. 매치 화면이 대기방 화면으로 복귀되고, 같은 룸 코드에서 다시 `게임 시작` 가능한지 확인한다.
5. `RESULT`에서 어느 한쪽이라도 `로비로` 클릭 시 양쪽 모두 `room.closed(reason=result_to_lobby)` 후 로비로 이동하는지 확인한다.

## 기대 결과
- `to_lobby`는 1표만으로 즉시 로비 복귀가 된다.
- `rematch`는 2명 모두 동의했을 때만 `WAITING`으로 복귀한다.
- 전환 중 크래시/멈춤 없이 poll 연결과 씬 전환이 정상 동작한다.
