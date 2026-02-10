# SPEC_08_ASSET_AND_POLISHING

## 1. Asset Replacement Policy
- 모든 UI/카드/배경은 외부 이미지로 교체 가능해야 한다
- 코드에서는 이미지 경로만 참조한다
- 이미지 해상도 변경 시 로직 수정은 발생하지 않는다

## 2. UI Skinning
- 버튼/카드는 기본 사각형 구현 가능
- 이후 이미지 스킨으로 교체 가능하도록 추상화한다

## 3. Sound Hook System
- 모든 주요 게임 이벤트는 Sound Hook을 가진다
- 실제 사운드 파일은 assets/sounds 에 위치
- 사운드 미존재 시에도 게임은 정상 동작해야 한다

### 3.1 Runtime Contract (Implemented)
- Client dispatches hook IDs from major HTTP/WS/match lifecycle events.
- Sound lookup rule:
  - `assets/sounds/<hookId>.ogg`
  - `assets/sounds/<hookId>.wav`
  - `assets/sounds/<hookId>.mp3`
- Missing hook files are treated as no-op (never crash, no gameplay impact).
- Hook playback is managed in one place:
  - `managers/sound_manager.lua`

## 4. Future Polish Safety
- 연출(FX)은 게임 판정과 분리한다
- 네트워크 동기화와 무관한 연출은 클라이언트 전용으로 처리한다
