--[[
파일명: sound_manager.lua
모듈명: SoundManager

역할:
- 주요 게임 이벤트 사운드 훅을 중앙에서 관리한다.
- 사운드 파일이 없어도 절대 크래시하지 않고 no-op으로 동작한다.

외부에서 사용 가능한 함수:
- SoundManager.new()
- SoundManager:setEnabled(isEnabled)
- SoundManager:setMasterVolume(volume)
- SoundManager:playHook(hookId)
- SoundManager:stopAll()

주의:
- 사운드 경로는 `assets/sounds/<hookId>.(ogg|wav|mp3)` 규칙을 따른다.
]]

local SoundManager = {}
SoundManager.__index = SoundManager

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function isSoundRuntimeAvailable()
  return love and love.audio and love.filesystem and love.audio.newSource ~= nil and love.audio.play ~= nil
end

function SoundManager.new()
  local instance = {
    _isEnabled = true,
    _masterVolume = 0.65,
    _sourceByHookId = {},
    _warnedKeySet = {}
  }
  return setmetatable(instance, SoundManager)
end

function SoundManager:setEnabled(isEnabled)
  self._isEnabled = isEnabled ~= false
end

function SoundManager:setMasterVolume(volume)
  if type(volume) ~= "number" then
    return
  end
  self._masterVolume = clamp(volume, 0, 1)
end

function SoundManager:warnOnce(warnKey, message)
  if self._warnedKeySet[warnKey] then
    return
  end
  self._warnedKeySet[warnKey] = true
  print("[SoundManager] " .. tostring(message))
end

function SoundManager:findSoundPathByHook(hookId)
  local candidateList = {
    string.format("assets/sounds/%s.ogg", hookId),
    string.format("assets/sounds/%s.wav", hookId),
    string.format("assets/sounds/%s.mp3", hookId)
  }
  for _, path in ipairs(candidateList) do
    if love.filesystem.getInfo(path) then
      return path
    end
  end
  return nil
end

function SoundManager:getSourceByHook(hookId)
  local cached = self._sourceByHookId[hookId]
  if cached ~= nil then
    if cached == false then
      return nil
    end
    return cached
  end

  if not isSoundRuntimeAvailable() then
    self._sourceByHookId[hookId] = false
    self:warnOnce("runtime_unavailable", "audio runtime unavailable, sound hooks disabled")
    return nil
  end

  local soundPath = self:findSoundPathByHook(hookId)
  if not soundPath then
    self._sourceByHookId[hookId] = false
    return nil
  end

  local isOk, sourceOrError = pcall(love.audio.newSource, soundPath, "static")
  if not isOk or not sourceOrError then
    self._sourceByHookId[hookId] = false
    self:warnOnce("load_" .. hookId, "failed to load " .. tostring(soundPath) .. ": " .. tostring(sourceOrError))
    return nil
  end

  pcall(sourceOrError.setVolume, sourceOrError, self._masterVolume)
  self._sourceByHookId[hookId] = sourceOrError
  return sourceOrError
end

function SoundManager:playHook(hookId)
  if not self._isEnabled then
    return false
  end
  if type(hookId) ~= "string" or hookId == "" then
    return false
  end

  local source = self:getSourceByHook(hookId)
  if not source then
    return false
  end

  local isCloneOk, clonedSource = pcall(function()
    return source:clone()
  end)
  if isCloneOk and clonedSource then
    pcall(clonedSource.setVolume, clonedSource, self._masterVolume)
    local isPlayOk = pcall(love.audio.play, clonedSource)
    return isPlayOk
  end

  local isFallbackOk = pcall(function()
    source:stop()
    source:play()
  end)
  return isFallbackOk
end

function SoundManager:stopAll()
  if not isSoundRuntimeAvailable() then
    return
  end
  pcall(love.audio.stop)
end

return SoundManager
