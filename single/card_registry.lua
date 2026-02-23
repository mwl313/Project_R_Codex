--[[
파일명: card_registry.lua
모듈명: CardRegistry

역할:
- 싱글플레이 카드 정의(이름/희귀도/태그/설명/파라미터)를 제공한다.
- 보상 선택 시 카드 후보 추출 로직을 제공한다.
]]

local CardRegistry = {}

local CARD_ORDER = {
  "rockfall",
  "shockwave",
  "invincible",
  "recruit",
  "agile",
  "guard_shell",
  "quick_reload",
  "stone_polish",
  "trick_bounce",
  "legend_overdrive"
}

local CARD_DEF_BY_ID = {
  rockfall = {
    id = "rockfall",
    nameKo = "낙석",
    rarity = "COMMON",
    mode = "MULTI_OK",
    tags = { "OBSTACLE", "CONTROL" },
    descKo = "보드에 장애물을 배치합니다.",
    params = {
      width = 100,
      height = 50,
      margin = 5
    }
  },
  shockwave = {
    id = "shockwave",
    nameKo = "충격파",
    rarity = "COMMON",
    mode = "MULTI_OK",
    tags = { "OFFENSE", "CONTROL" },
    descKo = "발사 알 충돌 시 주변에 충격파를 발생시킵니다.",
    params = {
      radiusMultiplier = 4,
      strength = 200
    }
  },
  invincible = {
    id = "invincible",
    nameKo = "무적",
    rarity = "RARE",
    mode = "MULTI_OK",
    tags = { "DEFENSE", "UTILITY" },
    descKo = "다음 상대 턴 동안 내 알이 밀려나지 않습니다.",
    params = {
      protectAfterTurnOffset = 1
    }
  },
  recruit = {
    id = "recruit",
    runtimeCardId = "reinforcement",
    nameKo = "신병",
    rarity = "COMMON",
    mode = "MULTI_OK",
    tags = { "UTILITY", "TRICK" },
    descKo = "새 알 1개를 배치합니다.",
    params = {
      lockSpawnedStoneForTurn = true
    }
  },
  agile = {
    id = "agile",
    nameKo = "날렵함",
    rarity = "RARE",
    mode = "MULTI_OK",
    tags = { "OFFENSE", "TRICK" },
    descKo = "이번 턴 발사 횟수를 늘립니다.",
    params = {
      shotBudget = 2
    }
  },
  guard_shell = {
    id = "guard_shell",
    nameKo = "수호막",
    rarity = "COMMON",
    mode = "SINGLE_ONLY",
    tags = { "DEFENSE", "UTILITY" },
    descKo = "다음 충돌 1회를 약화시키는 보호막을 부여합니다.",
    params = {
      reduceRatio = 0.4
    }
  },
  quick_reload = {
    id = "quick_reload",
    nameKo = "재장전",
    rarity = "COMMON",
    mode = "SINGLE_ONLY",
    tags = { "UTILITY", "TRICK" },
    descKo = "턴 종료 직후 카드 1장을 보충합니다.",
    params = {
      drawCount = 1
    }
  },
  stone_polish = {
    id = "stone_polish",
    nameKo = "연마",
    rarity = "COMMON",
    mode = "SINGLE_ONLY",
    tags = { "OFFENSE", "UTILITY" },
    descKo = "이번 턴 발사 파워 상한을 소폭 증가시킵니다.",
    params = {
      powerBonus = 80
    }
  },
  trick_bounce = {
    id = "trick_bounce",
    nameKo = "도약",
    rarity = "RARE",
    mode = "SINGLE_ONLY",
    tags = { "TRICK", "CONTROL" },
    descKo = "첫 충돌 후 추가 반사를 유도합니다.",
    params = {
      bonusRestitution = 0.1
    }
  },
  legend_overdrive = {
    id = "legend_overdrive",
    nameKo = "초월",
    rarity = "LEGENDARY",
    mode = "SINGLE_ONLY",
    tags = { "OFFENSE", "TRICK", "UTILITY" },
    descKo = "보스 전용 고등급 카드입니다.",
    params = {
      bonus = 1
    }
  }
}

local STARTER_CARD_ID_LIST = {
  "rockfall",
  "shockwave",
  "invincible",
  "recruit",
  "agile"
}

local SAVE_TO_RUNTIME_CARD_ID = {}
local RUNTIME_TO_SAVE_CARD_ID = {}
for _, cardId in ipairs(CARD_ORDER) do
  local cardDef = CARD_DEF_BY_ID[cardId]
  if cardDef then
    local runtimeCardId = tostring(cardDef.runtimeCardId or cardDef.id)
    SAVE_TO_RUNTIME_CARD_ID[cardDef.id] = runtimeCardId
    if not RUNTIME_TO_SAVE_CARD_ID[runtimeCardId] then
      RUNTIME_TO_SAVE_CARD_ID[runtimeCardId] = cardDef.id
    end
  end
end

local function copyCardDef(cardDef)
  local copied = {}
  for key, value in pairs(cardDef) do
    if type(value) == "table" then
      local nested = {}
      for nestedKey, nestedValue in pairs(value) do
        nested[nestedKey] = nestedValue
      end
      copied[key] = nested
    else
      copied[key] = value
    end
  end
  return copied
end

local function rngRandom(rng, minValue, maxValue)
  if rng and type(rng.random) == "function" then
    return rng:random(minValue, maxValue)
  end
  return math.random(minValue, maxValue)
end

function CardRegistry.getCard(cardId)
  local cardDef = CARD_DEF_BY_ID[tostring(cardId or "")]
  if not cardDef then
    return nil
  end
  return copyCardDef(cardDef)
end

function CardRegistry.listAll()
  local cardList = {}
  for _, cardId in ipairs(CARD_ORDER) do
    local cardDef = CARD_DEF_BY_ID[cardId]
    if cardDef then
      cardList[#cardList + 1] = copyCardDef(cardDef)
    end
  end
  return cardList
end

function CardRegistry.getStarterCardIds()
  local copied = {}
  for _, cardId in ipairs(STARTER_CARD_ID_LIST) do
    copied[#copied + 1] = cardId
  end
  return copied
end

function CardRegistry.getRewardChoices(isBoss, rng)
  local pool = {}
  for _, cardId in ipairs(CARD_ORDER) do
    local cardDef = CARD_DEF_BY_ID[cardId]
    if cardDef then
      if isBoss or cardDef.rarity ~= "LEGENDARY" then
        pool[#pool + 1] = cardId
      end
    end
  end

  local picked = {}
  local pickedSet = {}
  while #picked < 3 and #pool > 0 do
    local pickIndex = rngRandom(rng, 1, #pool)
    local pickedCardId = pool[pickIndex]
    table.remove(pool, pickIndex)
    if not pickedSet[pickedCardId] then
      pickedSet[pickedCardId] = true
      picked[#picked + 1] = copyCardDef(CARD_DEF_BY_ID[pickedCardId])
    end
  end

  if #picked < 3 then
    for _, cardId in ipairs(STARTER_CARD_ID_LIST) do
      if #picked >= 3 then
        break
      end
      if not pickedSet[cardId] then
        pickedSet[cardId] = true
        picked[#picked + 1] = copyCardDef(CARD_DEF_BY_ID[cardId])
      end
    end
  end

  return picked
end

function CardRegistry.toRuntimeCardId(cardId)
  local normalizedCardId = tostring(cardId or "")
  return SAVE_TO_RUNTIME_CARD_ID[normalizedCardId] or normalizedCardId
end

function CardRegistry.fromRuntimeCardId(runtimeCardId)
  local normalizedRuntimeId = tostring(runtimeCardId or "")
  return RUNTIME_TO_SAVE_CARD_ID[normalizedRuntimeId] or normalizedRuntimeId
end

return CardRegistry
