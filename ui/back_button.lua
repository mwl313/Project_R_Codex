--[[
파일명: back_button.lua
모듈명: BackButton

역할:
- 씬 공통 좌상단 뒤로 버튼 스타일을 통일한다.

외부에서 사용 가능한 함수:
- BackButton.new(label, onClick)
]]

local Button = require("ui.button")

local BackButton = {}

function BackButton.new(label, onClick)
  return Button.new({
    x = 20,
    y = 16,
    w = 160,
    h = 40,
    label = label,
    onClick = onClick
  })
end

return BackButton

