--[[
파일명: god_relic_defs.lua
모듈명: GodRelicDefs

역할:
- 싱글 웨이브 전용 갓 유물 정의/확률/튜닝 상수를 관리한다.
- 추후 밸런스 수정 시 이 파일만 수정하면 되도록 데이터 중심으로 유지한다.
]]

local GodRelicDefs = {}

GodRelicDefs.GOD_CHANCE = 0.03

GodRelicDefs.ID_ACTION_POWER = "action_power"
GodRelicDefs.ID_INFINITE_POWER = "infinite_power"
GodRelicDefs.ID_SAFETY = "safety"
GodRelicDefs.ID_PRECISION_CONTROL = "precision_control"
GodRelicDefs.ID_PIERCING_SHOT = "piercing_shot"

GodRelicDefs.LIST = {
  {
    id = GodRelicDefs.ID_ACTION_POWER,
    nameKo = "행동력",
    descKo = "턴당 행동수(샷 수)가 증가합니다.",
    stackable = true,
    type = "turn_action_plus",
    perStack = 1,
    weight = 1
  },
  {
    id = GodRelicDefs.ID_INFINITE_POWER,
    nameKo = "무한동력",
    descKo = "매 턴 시작 시 덱에서 카드를 추가로 드로우합니다.",
    stackable = true,
    type = "turn_draw",
    perStack = 1,
    weight = 1
  },
  {
    id = GodRelicDefs.ID_SAFETY,
    nameKo = "세이프티",
    descKo = "내 알이 경계에 닿으면 아웃되지 않고 벽처럼 반사됩니다.",
    stackable = false,
    type = "safety_wall",
    perStack = 0,
    weight = 1
  },
  {
    id = GodRelicDefs.ID_PRECISION_CONTROL,
    nameKo = "정밀 제어",
    descKo = "조준 중 예상 반사선을 추가로 표시합니다.",
    stackable = true,
    type = "aim_bounce_preview",
    perStack = 1,
    weight = 1
  },
  {
    id = GodRelicDefs.ID_PIERCING_SHOT,
    nameKo = "관통샷",
    descKo = "턴당 일정 횟수 첫 충돌에서 속도 손실을 무시합니다.",
    stackable = true,
    type = "pierce_first_collision",
    perStack = 1,
    weight = 1
  }
}

GodRelicDefs._byId = {}
for _, relic in ipairs(GodRelicDefs.LIST) do
  GodRelicDefs._byId[relic.id] = relic
end

function GodRelicDefs.getById(godRelicId)
  return GodRelicDefs._byId[tostring(godRelicId or "")]
end

return GodRelicDefs
