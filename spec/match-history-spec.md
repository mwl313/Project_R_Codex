# Spec: 승패 기록 (Match History)

## Objective
Phase 2 폴리시 — 대전 결과를 로컬에 저장하고 UI로 확인할 수 있게 한다.
로비 화면에 전적 패널을 추가.

## 데이터 구조

### 저장 파일
- 경로: `love.filesystem.getSaveDirectory() .. "/match_history.json"`
- 최대 50경기 보관 (FIFO)
- 포맷:

```json
{
  "records": [
    {
      "date": "2026-07-09T12:34:56+09:00",
      "myCharacter": "night_lord",
      "opponentCharacter": "arch_mage",
      "result": "win",
      "opponentNickname": "Player2",
      "myRemainingStones": 3,
      "opponentRemainingStones": 0,
      "turnCount": 8,
      "myAbilityUsed": true
    }
  ],
  "stats": {
    "totalGames": 42,
    "wins": 23,
    "losses": 19,
    "winRate": 0.5476,
    "characterStats": {
      "night_lord": { "played": 12, "wins": 7 },
      "arch_mage": { "played": 10, "wins": 6 },
      "paladin": { "played": 8, "wins": 4 },
      "aran": { "played": 12, "wins": 6 }
    }
  }
}
```

## 구현 내용

### 1. 데이터 저장 모듈 (`utils/match_history.lua` 신규)
- `loadHistory()` → records[], stats
- `saveRecord(record)` → JSON append + stats recalc
- `getStats()` → stats table
- `getRecentRecords(n)` → 최근 n경기
- 최대 50경기 초과 시 오래된 것부터 제거

### 2. 매치 결과 저장 (`match_scene.lua` 수정)
- `PHASE_RESULT` 진입 시 승패 정보 수집
- `myCharacter`, `opponentCharacter`, `result`, `opponentNickname`, 남은 알 개수, 턴 수, 초능력 사용 여부
- `MatchHistory.saveRecord(...)` 호출

### 3. 전적 UI (`scenes/record_scene.lua` 신규)
- 간단한 통계 패널 (승률, 캐릭터별 전적)
- 최근 10경기 리스트 (날짜, 매치업, 결과)

### 4. 로비 연결 (`scenes/lobby_scene.lua` 수정)
- 로비에 "전적" 버튼 추가 → record_scene으로 이동

## Files
| 파일 | 변경 |
|------|------|
| `utils/match_history.lua` | 신규 |
| `scenes/record_scene.lua` | 신규 |
| `scenes/match_scene.lua` | 결과 저장 로직 추가 (~15줄) |
| `scenes/lobby_scene.lua` | "전적" 버튼 추가 (~10줄) |
| `app.lua` | record_scene 씬 등록 |

## Success Criteria
- [ ] 대전 종료 후 `match_history.json`에 기록 저장
- [ ] 로비에서 전적 화면 진입 가능
- [ ] 최근 10경기 리스트 표시
- [ ] 캐릭터별 승률 통계 표시
- [ ] 50경기 초과 시 오래된 기록 자동 정리
