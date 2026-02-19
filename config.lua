--[[
파일명: config.lua
모듈명: Config

역할:
- 클라이언트 전역 런타임 설정 플래그를 보관한다.
]]

local Config = {
  -- false = 레거시 사각형 UI
  -- true = 9-slice UI 스킨
  UI_USE_NINESLICE = false
}

return Config

