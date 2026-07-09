--[[
파일명: effect_manager.lua
모듈명: EffectManager

역할:
- MatchScene에서 발생하는 임시 시각효과를 한 곳에서 관리한다.
- 현재 구현: 충격파(shockwave) 카드의 충돌 시 발생하는 원형 파동 이펙트.

사용 시나리오:
- 충격파 카드 사용 턴에서 "발사된 돌"이 벽/돌/장애물과 충돌할 때마다 파동 표시.
- 이펙트는 게임 규칙(판정)에 영향 주지 않고 렌더링만 담당.
]]

local EffectManager = {}
EffectManager.__index = EffectManager

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function EffectManager.new()
  local instance = {
    _effectList = {}
  }
  setmetatable(instance, EffectManager)
  return instance
end

local MAX_PARTICLES = 200

local function isTable(t)
  return type(t) == "table"
end

function EffectManager:clear()
  self._effectList = {}
  self._trailParticles = {}
end

-- 샷 트레일: stoneId를 추적하며 점점 작아지는 원형 파티클
-- 입자당 수명: 0.5s, 간격: 4px 마다 생성, 알파: 0.6→0
function EffectManager:addShotTrail(stoneId, stoneX, stoneY)
  if type(stoneId) ~= "string" or not isFiniteNumber(stoneX) or not isFiniteNumber(stoneY) then
    return
  end
  self._effectList[#self._effectList + 1] = {
    kind = "shot_trail",
    stoneId = stoneId,
    lastX = stoneX,
    lastY = stoneY,
    particles = {},
    spawnAccum = 0
  }
end

-- 충돌 이펙트: 방사형 파티클 (intensity=1.0 default)
-- 입자 수: intensity 비례 (8~20개), 속도: 100~300, 수명: 0.3s
function EffectManager:addCollisionEffect(x, y, intensity)
  if not isFiniteNumber(x) or not isFiniteNumber(y) then
    return
  end
  local particleCount = math.floor(8 + (tonumber(intensity) or 1.0) * 12)
  particleCount = math.min(particleCount, MAX_PARTICLES)
  local particles = {}
  for i = 1, particleCount do
    local angle = (math.pi * 2 / particleCount) * i + math.random() * 0.5
    local speed = 100 + math.random() * 200
    particles[#particles + 1] = {
      px = x,
      py = y,
      vx = math.cos(angle) * speed,
      vy = math.sin(angle) * speed,
      life = 0.3,
      maxLife = 0.3,
      radius = 2 + math.random() * 3
    }
  end
  self._effectList[#self._effectList + 1] = {
    kind = "collision",
    particles = particles
  }
end

-- 메테오: 보드 상단→중앙 빛줄기 + 충격파(기존 pulse 재활용) + 파편
-- 빛줄기: 세로줄 3개 (노랑/주황), 지속시간 1.0s
function EffectManager:addMeteorEffect()
  self._effectList[#self._effectList + 1] = {
    kind = "meteor",
    elapsed = 0,
    duration = 1.0
  }
end

-- 섀도우스텝: 출발점 원 축소 + 도착점 원 확대 + 잔상
-- 출발점: 보라색 원 축소 (radius: stone_radius→0, 0.3s)
-- 도착점: 보라색 원 확대 (radius: 0→stone_radius×2→stone_radius, 0.4s)
-- 잔상: 출발→도착 사이에 3개 페이드아웃 원
-- 색상: {0.55, 0.30, 0.85} 보라
function EffectManager:addShadowStepEffect(fromX, fromY, toX, toY, radius)
  if not isFiniteNumber(fromX) or not isFiniteNumber(fromY) or not isFiniteNumber(toX) or not isFiniteNumber(toY) then
    return
  end
  local r = radius or 20
  if not isFiniteNumber(r) or r <= 0 then
    r = 20
  end
  self._effectList[#self._effectList + 1] = {
    kind = "shadow_step",
    fromX = fromX,
    fromY = fromY,
    toX = toX,
    toY = toY,
    radius = r,
    elapsed = 0,
    duration = 0.5
  }
end

-- 디바인실드: 대상 알들에 노란색 반투명 실드 링 (회전)
-- 링 회전 (360°/2s), 알파: 0.4→0.25 펄스
-- 지속시간: 2턴 (durationSec 파라미터)
function EffectManager:addDivineShieldEffect(stones, durationSec)
  if not isTable(stones) or #stones == 0 then
    return
  end
  local dur = tonumber(durationSec) or 2
  local stoneData = {}
  for _, stone in ipairs(stones) do
    if isTable(stone) and isFiniteNumber(stone.x) and isFiniteNumber(stone.y) then
      stoneData[#stoneData + 1] = { x = stone.x, y = stone.y }
    end
  end
  if #stoneData == 0 then
    return
  end
  self._effectList[#self._effectList + 1] = {
    kind = "divine_shield",
    stones = stoneData,
    elapsed = 0,
    duration = dur
  }
end

-- 콤보피니셔: 대각선 슬래시라인 + 카메라 셰이크
-- 슬래시 라인: 대각선 2줄, 0.4s
-- 카메라 셰이크: 진폭 4px, 0.2s
-- 색상: {0.25, 0.60, 0.90} 파랑
function EffectManager:addComboFinisherEffect()
  self._effectList[#self._effectList + 1] = {
    kind = "combo_finisher",
    elapsed = 0,
    duration = 0.5,
    shakeElapsed = 0,
    shakeDuration = 0.2,
    shakeAmplitude = 4
  }
end

-- 충격파 카드 전용 시각효과:
-- 충격파 판정 반경(radius)과 동일한 최대 반경으로 확산하는 원형 파동을 생성한다.
function EffectManager:addShockwavePulse(canonicalX, canonicalY, radius)
  if not isFiniteNumber(canonicalX) or not isFiniteNumber(canonicalY) or not isFiniteNumber(radius) then
    return
  end
  local clampedRadius = math.max(0, radius)
  if clampedRadius <= 0 then
    return
  end
  self._effectList[#self._effectList + 1] = {
    kind = "shockwave",
    x = canonicalX,
    y = canonicalY,
    radius = clampedRadius,
    elapsed = 0,
    duration = 0.22
  }
end

function EffectManager:update(dt)
  local clampedDt = 0
  if isFiniteNumber(dt) then
    clampedDt = math.max(0, math.min(dt, 0.05))
  end

  for index = #self._effectList, 1, -1 do
    local effect = self._effectList[index]
    effect.elapsed = (effect.elapsed or 0) + clampedDt

    if effect.kind == "collision" then
      local allDead = true
      for _, p in ipairs(effect.particles) do
        p.life = p.life - clampedDt
        if p.life > 0 then
          allDead = false
          p.px = p.px + p.vx * clampedDt
          p.py = p.py + p.vy * clampedDt
        end
      end
      if allDead then
        table.remove(self._effectList, index)
      end
    elseif effect.kind == "shot_trail" then
      local particles = effect.particles
      if isTable(particles) then
        local allDead = true
        for _, p in ipairs(particles) do
          p.life = p.life - clampedDt
          if p.life > 0 then
            allDead = false
          end
        end
        if allDead then
          table.remove(self._effectList, index)
        end
      else
        table.remove(self._effectList, index)
      end
    elseif effect.kind == "combo_finisher" then
      effect.shakeElapsed = (effect.shakeElapsed or 0) + clampedDt
      if effect.elapsed >= effect.duration then
        table.remove(self._effectList, index)
      end
    else
      if effect.elapsed >= (effect.duration or 0.5) then
        table.remove(self._effectList, index)
      end
    end
  end
end

function EffectManager:getCameraShake()
  for _, effect in ipairs(self._effectList) do
    if effect.kind == "combo_finisher" then
      local shakeElapsed = effect.shakeElapsed or 0
      if shakeElapsed < effect.shakeDuration then
        local progress = shakeElapsed / effect.shakeDuration
        local amplitude = effect.shakeAmplitude * (1 - progress)
        local offsetX = (math.random() * 2 - 1) * amplitude
        local offsetY = (math.random() * 2 - 1) * amplitude
        return offsetX, offsetY
      end
    end
  end
  return 0, 0
end

function EffectManager:draw(boardX, boardY, canonicalToLocalFn)
  if type(canonicalToLocalFn) ~= "function" then
    return
  end

  for _, effect in ipairs(self._effectList) do
    if effect.kind == "shockwave" then
      local progress = math.min(1, effect.elapsed / effect.duration)
      local pulseRadius = math.max(1, effect.radius * progress)
      local alpha = (1 - progress) * 0.72
      local lineWidth = 2 + (1 - progress) * 2
      local localX, localY = canonicalToLocalFn(effect.x, effect.y)
      local worldX = boardX + localX
      local worldY = boardY + localY
      love.graphics.setLineWidth(lineWidth)
      love.graphics.setColor(0.22, 0.80, 1.00, alpha)
      love.graphics.circle("line", worldX, worldY, pulseRadius)
      love.graphics.setColor(0.22, 0.80, 1.00, alpha * 0.20)
      love.graphics.circle("fill", worldX, worldY, pulseRadius * 0.28)
      love.graphics.setLineWidth(1)
    elseif effect.kind == "shot_trail" then
      self:_drawShotTrail(boardX, boardY, canonicalToLocalFn, effect)
    elseif effect.kind == "collision" then
      self:_drawCollision(boardX, boardY, canonicalToLocalFn, effect)
    elseif effect.kind == "meteor" then
      self:_drawMeteor(boardX, boardY, canonicalToLocalFn, effect)
    elseif effect.kind == "shadow_step" then
      self:_drawShadowStep(boardX, boardY, canonicalToLocalFn, effect)
    elseif effect.kind == "divine_shield" then
      self:_drawDivineShield(boardX, boardY, canonicalToLocalFn, effect)
    elseif effect.kind == "combo_finisher" then
      self:_drawComboFinisher(boardX, boardY, canonicalToLocalFn, effect)
    end
  end
end

function EffectManager:_drawShotTrail(boardX, boardY, canonicalToLocalFn, effect)
  for _, p in ipairs(effect.particles or {}) do
    if p.life > 0 then
      local localX, localY = canonicalToLocalFn(p.px, p.py)
      local worldX = boardX + localX
      local worldY = boardY + localY
      local prog = 1 - (p.life / p.maxLife)
      local alpha = (1 - prog) * 0.6
      local r = math.max(1, p.radius * (1 - prog * 0.6))
      love.graphics.setColor(0.40, 0.60, 1.00, alpha)
      love.graphics.circle("fill", worldX, worldY, r)
    end
  end
end

function EffectManager:_drawCollision(boardX, boardY, canonicalToLocalFn, effect)
  for _, p in ipairs(effect.particles) do
    if p.life > 0 then
      local localX, localY = canonicalToLocalFn(p.px, p.py)
      local worldX = boardX + localX
      local worldY = boardY + localY
      local prog = 1 - (p.life / p.maxLife)
      local alpha = (1 - prog) * 0.8
      love.graphics.setColor(1.00, 0.85, 0.40, alpha)
      love.graphics.circle("fill", worldX, worldY, math.max(1, p.radius * (1 - prog * 0.5)))
    end
  end
end

function EffectManager:_drawMeteor(boardX, boardY, canonicalToLocalFn, effect)
  local progress = math.min(1, effect.elapsed / effect.duration)
  local centerX = Constants.BOARD_W * 0.5
  local localCX, localCY = canonicalToLocalFn(centerX, Constants.BOARD_H * 0.5)
  local wcx = boardX + localCX
  local wcy = boardY + localCY

  local alpha = (1 - progress) * 0.7
  local topY = boardY + localCY - Constants.BOARD_H * 0.5 - 40
  for i = -1, 1 do
    local xOff = i * 12
    local la = alpha * (1 - math.abs(i) * 0.3)
    love.graphics.setLineWidth(3 - math.abs(i))
    love.graphics.setColor(1.00, 0.70 + i * 0.1, 0.10, la)
    love.graphics.line(wcx + xOff - 4, topY, wcx + xOff, wcy - 20)
    love.graphics.line(wcx + xOff, wcy - 20, wcx + xOff + 4, wcy)
  end

  local pp = math.max(0, math.min(1, (progress - 0.1) / 0.8))
  if pp > 0 then
    local pr = math.max(1, 120 * pp)
    local pa = (1 - pp) * 0.5
    love.graphics.setLineWidth(2 + (1 - pp) * 2)
    love.graphics.setColor(1.00, 0.65, 0.10, pa)
    love.graphics.circle("line", wcx, wcy, pr)
    love.graphics.setColor(1.00, 0.65, 0.10, pa * 0.15)
    love.graphics.circle("fill", wcx, wcy, pr * 0.25)
    love.graphics.setLineWidth(1)
  end

  if progress < 0.5 then
    local fa = (1 - progress * 2) * 0.8
    for i = 1, 6 do
      local angle = (math.pi * 2 / 6) * i + progress * 2
      local dist = 30 + progress * 80
      love.graphics.setColor(1.00, 0.60, 0.10, fa * 0.7)
      love.graphics.circle("fill", wcx + math.cos(angle) * dist, wcy + math.sin(angle) * dist, math.max(1, 4 - progress * 3))
    end
  end
end

function EffectManager:_drawShadowStep(boardX, boardY, canonicalToLocalFn, effect)
  local progress = math.min(1, effect.elapsed / effect.duration)
  local purp = { 0.55, 0.30, 0.85 }

  if effect.elapsed <= 0.3 then
    local dp = effect.elapsed / 0.3
    local dr = math.max(0, effect.radius * (1 - dp))
    local da = (1 - dp) * 0.7
    local dlx, dly = canonicalToLocalFn(effect.fromX, effect.fromY)
    dlx = boardX + dlx; dly = boardY + dly
    love.graphics.setColor(purp[1], purp[2], purp[3], da)
    love.graphics.circle("line", dlx, dly, dr)
    love.graphics.setColor(purp[1], purp[2], purp[3], da * 0.3)
    love.graphics.circle("fill", dlx, dly, dr * 0.5)
  end

  if effect.elapsed <= 0.4 then
    local ap = effect.elapsed / 0.4
    local ar = effect.radius * 2 * ap
    local aa = 0.7 * ap
    local alx, aly = canonicalToLocalFn(effect.toX, effect.toY)
    alx = boardX + alx; aly = boardY + aly
    love.graphics.setColor(purp[1], purp[2], purp[3], aa)
    love.graphics.circle("line", alx, aly, ar)
  elseif effect.elapsed > 0.4 then
    local sp = (effect.elapsed - 0.4) / 0.1
    local ar = math.max(effect.radius, effect.radius * 2 * (1 - sp * 0.5))
    local aa = 0.7 * (1 - sp)
    local alx, aly = canonicalToLocalFn(effect.toX, effect.toY)
    alx = boardX + alx; aly = boardY + aly
    love.graphics.setColor(purp[1], purp[2], purp[3], aa)
    love.graphics.circle("line", alx, aly, ar)
  end

  if progress < 0.4 then
    local ga = (1 - progress * 2.5) * 0.35
    for i = 1, 3 do
      local t = i / 4
      local gx = effect.fromX + (effect.toX - effect.fromX) * t
      local gy = effect.fromY + (effect.toY - effect.fromY) * t
      local glx, gly = canonicalToLocalFn(gx, gy)
      glx = boardX + glx; gly = boardY + gly
      love.graphics.setColor(purp[1], purp[2], purp[3], ga * (1 - i * 0.2))
      love.graphics.circle("fill", glx, gly, effect.radius * (0.6 + i * 0.1))
    end
  end
end

function EffectManager:_drawDivineShield(boardX, boardY, canonicalToLocalFn, effect)
  local pa = 0.4 - (0.15 * (1 + math.sin(effect.elapsed * math.pi * 2)) * 0.5)
  local angle = effect.elapsed * math.pi
  for _, sd in ipairs(effect.stones) do
    local sx, sy = canonicalToLocalFn(sd.x, sd.y)
    local wsx = boardX + sx
    local wsy = boardY + sy
    local sr = 22 + 4 * math.sin(effect.elapsed * math.pi * 3)
    love.graphics.setLineWidth(2.5)
    love.graphics.setColor(1.00, 0.85, 0.20, pa)
    love.graphics.circle("line", wsx, wsy, sr)
    for i = 1, 4 do
      local a = angle + (math.pi * 2 / 4) * i
      love.graphics.setColor(1.00, 0.90, 0.30, pa * 0.6)
      love.graphics.circle("fill", wsx + math.cos(a) * sr, wsy + math.sin(a) * sr, 3)
    end
    love.graphics.setLineWidth(1)
  end
end

function EffectManager:_drawComboFinisher(boardX, boardY, _canonicalToLocalFn, effect)
  local progress = math.min(1, effect.elapsed / 0.4)
  if progress < 1 then
    local alpha = (1 - progress) * 0.8
    local halfW = 200
    local halfH = 120
    local cx = boardX + Constants.BOARD_W * 0.5
    local cy = boardY + Constants.BOARD_H * 0.5
    love.graphics.setLineWidth(3 + (1 - progress) * 3)
    love.graphics.setColor(0.25, 0.60, 0.90, alpha)
    love.graphics.line(cx - halfW, cy - halfH, cx + halfW, cy + halfH)
    love.graphics.line(cx - halfW, cy + halfH, cx + halfW, cy - halfH)
    love.graphics.setLineWidth(1)
  end
end

return EffectManager
