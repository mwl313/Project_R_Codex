# Spec: LOVE.js 웹 빌드 파이프라인

## Objective
LÖVE2D 프로젝트를 LOVE.js로 컴파일해 브라우저에서 실행 가능한 웹 빌드 파이프라인을 구축한다.
Phase 2 itch.io 데모 출시를 위한 선행 작업.

## Tech Stack
- LOVE.js (11.x 호환)
- Node.js (기존 서버 인프라 재활용)
- Makefile 또는 shell script

## Build Pipeline

```
ProjectR/ (LÖVE2D)
    │
    ▼
love.js (Emscripten-packaged LÖVE)
    │
    ▼
HTML + JS + data bundle
    │
    ▼
itch.io / static hosting
```

## 구현 내용

### 1. 빌드 스크립트 (`tools/build_web.sh`)
- love.js 릴리즈 다운로드 (또는 npm 패키지)
- 프로젝트를 .love 파일로 패키징
- love.js로 웹 번들 생성
- 출력: `build/web/` 디렉토리

### 2. 버전 관리
- `.gitignore`에 `build/web/` 추가
- 최종 빌드 결과물만 exports로 복사

### 3. 주의사항
- LOVE.js는 shader, FFI, luasocket 미지원
- 기존 net/ws_client.lua가 Emscripten 환경에서 작동하는지 확인
- WebSocket으로 자동 전환 필요
- love.filesystem 동작 차이 확인

## Commands
```bash
# 빌드
cd ~/Haven_v0.5/home/projects/ProjectR
bash tools/build_web.sh

# 결과 확인
python3 -m http.server 3100 -d build/web/
# → http://127.0.0.1:3100
```

## Files
- `tools/build_web.sh` (신규)
- `.gitignore` (수정)
- `net/` 네트워크 모듈 (웹 호환성 확인)

## Success Criteria
- [ ] `bash tools/build_web.sh` 실행 시 `build/web/` 생성됨
- [ ] 로컬 HTTP 서버로 로비 화면 진입 가능
- [ ] WebSocket 연결 시도 확인 (서버 없어도 UI 표시)
