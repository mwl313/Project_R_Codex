--[[
파일명: conf.lua
모듈명: Conf

역할:
- LÖVE 초기 설정
- 기본 창 크기 및 저장 identity 설정

외부에서 사용 가능한 함수:
- love.conf(t)

주의:
- identity는 project_r로 고정
]]

function love.conf(t)
  t.identity = "project_r"
  t.version = "11.5"
  t.window.title = "ProjectR - Phase 2"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.minwidth = 960
  t.window.minheight = 540
end
