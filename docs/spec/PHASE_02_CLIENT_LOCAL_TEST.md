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

1. 클라이언트 A 로비에서 닉네임 입력 후 `적용`
2. 클라이언트 B 로비에서 다른 닉네임 입력 후 `적용`
3. A에서 `방 생성` 클릭
4. B에서 `방 찾기` 클릭 후 A의 roomCode 입력, `참가`
5. 양쪽 대기방에서 아래 확인
   - `server.welcome` 반영(role 표시)
   - `room.state` 반영(host/guest 연결 상태 표시)
   - 채팅 송수신
6. B에서 `나가기`
   - A 화면에 guest left 반영
7. A에서 `나가기`
   - room closed 처리 후 로비 복귀

## 4) 실패 시 체크포인트

- WS 연결 실패:
  - 서버 실행 여부 확인
  - `ws://127.0.0.1:8787` 접속 경로 확인
- HTTP 실패:
  - `/room/create`, `/room/join` 응답 JSON 확인
- 채팅 미수신:
  - `client.chat.send` payload 구조 확인
  - 서버 `chat.denied` reason 확인

## 5) 한글 폰트 확인 (5줄)
- 로비에서 한글 버튼 텍스트(싱글플레이어/방 생성/방 찾기 등)가 깨지지 않는지 확인
- 로비 닉네임 입력칸에 `노조미` 입력 후 정상 표시 확인
- 방 생성/참가 후 대기방 채팅에 한글 메시지 송신/표시 확인
- `assets/fonts/NotoSansKR-Regular.ttf`를 임시로 빼고 실행 시 경고 문구 + 기본 폰트 폴백 확인
