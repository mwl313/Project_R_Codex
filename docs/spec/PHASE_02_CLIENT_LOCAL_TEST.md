# PHASE_02_CLIENT_LOCAL_TEST

## 1) 서버 실행

```bash
npm run dev
```

서버 주소: `http://127.0.0.1:8787`

## 2) 클라이언트 실행

프로젝트 루트(`project_r`)를 LÖVE로 실행한다.

예시(Windows):

```powershell
love .
```

같은 방법으로 클라이언트를 2개 실행한다.

## 3) 테스트 시나리오

1. 클라이언트 A 로비에서 `닉네임 변경` 클릭 -> 오버레이(70%)에서 닉네임 입력 후 `저장`
2. 클라이언트 B 로비에서 동일하게 다른 닉네임 저장
3. A에서 `방 생성` 클릭
4. B에서 `방 찾기` 클릭 후 A의 roomCode 입력, `참가`
5. 양쪽 대기방에서 아래 확인
   - Long-Poll 첫 응답의 `server.welcome` 반영(role 표시)
   - Long-Poll 이벤트의 `room.state` 반영(host/guest 연결 상태 표시)
   - 채팅 송수신
6. B에서 `나가기`
   - A 화면에 guest left 반영
7. A에서 `나가기`
   - room closed 처리 후 로비 복귀
8. 로비에서 `환경설정` 오버레이를 열고
   - `디스플레이 모드` 드롭다운 저장
   - `언어 설정` 드롭다운 저장
   후 재실행해 설정 유지 확인

## 4) 실패 시 체크포인트

- WS 연결 실패:
  - `/room/poll` 응답(JSON) 확인
  - 클라이언트 `serverEnv`가 로컬(`http://127.0.0.1:8787`)인지 확인
- HTTP 실패:
  - `/room/create`, `/room/join`, `/room/send`, `/room/poll` 응답 JSON 확인
- 채팅 미수신:
  - `client.chat.send` payload 구조 확인
  - 서버 `chat.denied` reason 확인

## 5) 한글 폰트 확인 (5줄)
- 로비에서 한글 버튼 텍스트(싱글플레이어/방 생성/방 찾기 등)가 깨지지 않는지 확인
- 로비 `닉네임 변경` 오버레이에서 `노조미` 입력 후 정상 표시 확인
- 방 생성/참가 후 대기방 채팅에 한글 메시지 송신/표시 확인
- `assets/fonts/MulmaruMono.ttf`를 임시로 빼고 실행 시 경고 문구 + 기본 폰트 폴백 확인
- 환경설정에서 언어를 `English`로 저장 후 로비/대기방 주요 UI 텍스트가 영문으로 바뀌는지 확인
