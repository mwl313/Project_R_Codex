--[[
파일명: abilities/special.lua
모듈명: AbilitySpecial

역할:
- 장기 지속/룰 변경형 능력 확장 지점.
- 1차 구현에서는 no-op 훅만 제공한다.
]]

local AbilitySpecial = {}

function AbilitySpecial.onTurnStart(_scene, _playerIndex)
end

function AbilitySpecial.onTurnEnd(_scene, _playerIndex)
end

function AbilitySpecial.onShotPrepare(_scene, _shotParams)
end

function AbilitySpecial.onShotResolved(_scene, _shotResult)
end

function AbilitySpecial.onStoneOut(_scene, _stone, _cause)
end

return AbilitySpecial
