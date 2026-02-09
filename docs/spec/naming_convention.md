# LÖVE2D Lua 네이밍 & 주석 규칙

이 문서는 본 프로젝트의 **함수 / 변수 네이밍 규칙과 주석 작성 규칙**을 정의한다.  
ChatGPT 및 모든 협업자는 이 문서를 **항상 우선 기준**으로 따른다.

---

## 1. 네이밍 규칙 (간소화 버전)

### 1.1 케이스 규칙 (딱 3개)

| 대상 | 규칙 | 예시 |
|---|---|---|
| 변수 / 함수 | camelCase | `playerSpeed`, `update(dt)` |
| 테이블(모듈) | PascalCase | `Player`, `SceneManager` |
| 상수 | UPPER_SNAKE_CASE | `MAX_HP`, `TILE_SIZE` |

이 외의 케이스는 사용하지 않는다.

---

### 1.2 불리언 변수 규칙 (필수)

불리언은 반드시 아래 접두사 중 하나로 시작한다.

- `is`
- `has`
- `can`
- `should`

```lua
isAlive
hasKey
canMove
shouldRespawn
```

---

### 1.3 함수 네이밍

- 함수 이름은 **동사로 시작**
- 간결함 우선, 의미만 명확하면 충분

```lua
update(dt)
draw()
reset()
loadData()
handleInput()
```

- 입력/콜백: `onKeyPressed`, `onMousePressed`
- 내부 처리: `handleCollision`, `handleDamage`

---

### 1.4 컬렉션 변수

- 여러 개를 담는 변수는 가능하면 **복수형**
- 강제 규칙은 아님 (의미 전달이 우선)

```lua
players
enemies
bullets
```

---

### 1.5 단위 표기 규칙 (최소)

- **시간 관련 변수만 `Sec` 접미사 사용**

```lua
cooldownSec
elapsedSec
timerSec
```

---

### 1.6 내부 전용(private) 표기

Lua에는 private 개념이 없으므로 관례로 표시한다.

- 내부 전용 필드/함수는 `_`로 시작

```lua
self._state
self._timerSec

local function _clamp()
```

---

### 1.7 전역 사용 규칙

전역 변수는 원칙적으로 금지한다.  
아래 이름만 예외적으로 허용한다.

```lua
App
Assets
Config
SceneManager
```

해당 이름은 **의미와 역할을 변경하지 않는다.**

---

## 2. 파일 최상단 주석 규칙 (필수)

모든 Lua 파일은 아래 형식의 주석을 **파일 최상단에 반드시 포함**한다.

```lua
--[[
파일명: player.lua
모듈명: Player

역할:
- 플레이어 상태 관리
- 이동 및 입력 처리
- 그리기 담당

외부에서 사용 가능한 함수:
- Player.new(params)
- Player:update(dt)
- Player:draw()

주의:
- _로 시작하는 필드/함수는 내부 전용
]]
```

---

## 3. EmmyLua 사용 전제

본 프로젝트는 **EmmyLua(Language Server)** 사용을 전제로 한다.

- 심볼 검색 (Ctrl + T)
- 정의로 이동 (F12)
- 참조 찾기 (Shift + F12)
- 이름 변경 (F2)

을 통해 **함수/변수 트래킹은 IDE에 위임**한다.

---

## 4. 규칙 변경에 대하여

- 본 문서 수정 시, **모든 신규 코드부터 적용**
- 기존 코드 리팩토링은 필요 시 진행

---

## 요약

- 케이스 3개만 사용
- 불리언은 접두사 필수
- 함수는 동사로 시작
- 파일 최상단 주석은 필수
- 나머지는 EmmyLua가 해결한다
