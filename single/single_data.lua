--[[
파일명: single_data.lua
모듈명: SingleData

역할:
- 싱글 캠페인 SSOT JSON 로더 엔트리포인트.
- 아직 게임플레이에 강결합하지 않고, 안전한 데이터 접근 지점만 제공한다.
]]

local SingleCampaignRulesLoader = require("single.single_campaign_rules_loader")
local RewardTablesLoader = require("single.reward_tables_loader")
local EncountersLoader = require("single.encounters_loader")
local AiProfilesLoader = require("single.ai_profiles_loader")
local RelicRulesLoader = require("single.relic_rules_loader")
local MapTemplatesLoader = require("single.map_templates_loader")

local SingleData = {}

function SingleData.load()
  return {
    rules = SingleCampaignRulesLoader.load(),
    rewards = RewardTablesLoader.load(),
    encounters = EncountersLoader.load(),
    ai = AiProfilesLoader.load(),
    relics = RelicRulesLoader.load(),
    mapTemplates = MapTemplatesLoader.load()
  }
end

return SingleData
