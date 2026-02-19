--[[
파일명: nine_slice.lua
모듈명: NineSlice

역할:
- 9-slice PNG를 월드 좌표 기준으로 안전하게 렌더링한다.
- (image, insets) 조합별 quad를 캐시해 매 프레임 할당을 피한다.

외부에서 사용 가능한 함수:
- NineSlice.new(image, insetsTable)
- nineSlice:draw(x, y, w, h, opts)

주의:
- 폭/높이가 insets 합보다 작으면 최소 크기로 clamp 렌더링한다.
]]

local NineSlice = {}
NineSlice.__index = NineSlice

local quadCacheByImage = setmetatable({}, { __mode = "k" })

local function toNonNegativeInteger(value, fallback)
  local numberValue = tonumber(value)
  if not numberValue then
    return fallback or 0
  end
  if numberValue < 0 then
    return 0
  end
  return math.floor(numberValue + 0.5)
end

local function normalizeInsets(image, insets)
  local imageW, imageH = image:getDimensions()
  local left = toNonNegativeInteger(insets and (insets.l or insets.left), 0)
  local top = toNonNegativeInteger(insets and (insets.t or insets.top), 0)
  local right = toNonNegativeInteger(insets and (insets.r or insets.right), 0)
  local bottom = toNonNegativeInteger(insets and (insets.b or insets.bottom), 0)

  left = math.min(left, imageW)
  right = math.min(right, imageW - left)
  top = math.min(top, imageH)
  bottom = math.min(bottom, imageH - top)

  return {
    l = left,
    t = top,
    r = right,
    b = bottom
  }
end

local function getCacheKey(insets)
  return table.concat({
    tostring(insets.l or 0),
    tostring(insets.t or 0),
    tostring(insets.r or 0),
    tostring(insets.b or 0)
  }, ":")
end

local function createCachedSlices(image, insets)
  local imageW, imageH = image:getDimensions()
  local centerW = imageW - insets.l - insets.r
  local centerH = imageH - insets.t - insets.b

  local slices = {
    imageW = imageW,
    imageH = imageH,
    left = insets.l,
    top = insets.t,
    right = insets.r,
    bottom = insets.b,
    centerW = centerW,
    centerH = centerH,
    minDrawW = insets.l + insets.r,
    minDrawH = insets.t + insets.b,
    quadTL = nil,
    quadT = nil,
    quadTR = nil,
    quadL = nil,
    quadC = nil,
    quadR = nil,
    quadBL = nil,
    quadB = nil,
    quadBR = nil
  }

  if insets.l > 0 and insets.t > 0 then
    slices.quadTL = love.graphics.newQuad(0, 0, insets.l, insets.t, imageW, imageH)
  end
  if centerW > 0 and insets.t > 0 then
    slices.quadT = love.graphics.newQuad(insets.l, 0, centerW, insets.t, imageW, imageH)
  end
  if insets.r > 0 and insets.t > 0 then
    slices.quadTR = love.graphics.newQuad(imageW - insets.r, 0, insets.r, insets.t, imageW, imageH)
  end
  if insets.l > 0 and centerH > 0 then
    slices.quadL = love.graphics.newQuad(0, insets.t, insets.l, centerH, imageW, imageH)
  end
  if centerW > 0 and centerH > 0 then
    slices.quadC = love.graphics.newQuad(insets.l, insets.t, centerW, centerH, imageW, imageH)
  end
  if insets.r > 0 and centerH > 0 then
    slices.quadR = love.graphics.newQuad(imageW - insets.r, insets.t, insets.r, centerH, imageW, imageH)
  end
  if insets.l > 0 and insets.b > 0 then
    slices.quadBL = love.graphics.newQuad(0, imageH - insets.b, insets.l, insets.b, imageW, imageH)
  end
  if centerW > 0 and insets.b > 0 then
    slices.quadB = love.graphics.newQuad(insets.l, imageH - insets.b, centerW, insets.b, imageW, imageH)
  end
  if insets.r > 0 and insets.b > 0 then
    slices.quadBR = love.graphics.newQuad(imageW - insets.r, imageH - insets.b, insets.r, insets.b, imageW, imageH)
  end

  return slices
end

local function getCachedSlices(image, insets)
  local cacheByInsets = quadCacheByImage[image]
  if not cacheByInsets then
    cacheByInsets = {}
    quadCacheByImage[image] = cacheByInsets
  end

  local cacheKey = getCacheKey(insets)
  local cached = cacheByInsets[cacheKey]
  if cached then
    return cached
  end

  local created = createCachedSlices(image, insets)
  cacheByInsets[cacheKey] = created
  return created
end

local function drawQuad(image, quad, drawX, drawY, drawW, drawH, sourceW, sourceH)
  if not quad then
    return
  end
  if drawW <= 0 or drawH <= 0 or sourceW <= 0 or sourceH <= 0 then
    return
  end

  love.graphics.draw(image, quad, drawX, drawY, 0, drawW / sourceW, drawH / sourceH)
end

function NineSlice.new(image, insetsTable)
  if not image then
    return nil
  end

  local normalizedInsets = normalizeInsets(image, insetsTable)
  local cachedSlices = getCachedSlices(image, normalizedInsets)

  local instance = {
    _image = image,
    _slices = cachedSlices
  }
  return setmetatable(instance, NineSlice)
end

function NineSlice:draw(x, y, w, h, opts)
  local drawX = tonumber(x) or 0
  local drawY = tonumber(y) or 0
  local rawW = tonumber(w) or 0
  local rawH = tonumber(h) or 0
  local slices = self._slices
  local image = self._image

  local drawW = math.max(rawW, slices.minDrawW)
  local drawH = math.max(rawH, slices.minDrawH)

  local left = slices.left
  local top = slices.top
  local right = slices.right
  local bottom = slices.bottom
  local centerW = drawW - left - right
  local centerH = drawH - top - bottom

  local bodyX = drawX + left
  local bodyY = drawY + top
  local rightX = drawX + drawW - right
  local bottomY = drawY + drawH - bottom

  local function drawBody(offsetX, offsetY)
    drawQuad(image, slices.quadTL, drawX + offsetX, drawY + offsetY, left, top, left, top)
    drawQuad(image, slices.quadT, bodyX + offsetX, drawY + offsetY, centerW, top, slices.centerW, top)
    drawQuad(image, slices.quadTR, rightX + offsetX, drawY + offsetY, right, top, right, top)
    drawQuad(image, slices.quadL, drawX + offsetX, bodyY + offsetY, left, centerH, left, slices.centerH)
    drawQuad(image, slices.quadC, bodyX + offsetX, bodyY + offsetY, centerW, centerH, slices.centerW, slices.centerH)
    drawQuad(image, slices.quadR, rightX + offsetX, bodyY + offsetY, right, centerH, right, slices.centerH)
    drawQuad(image, slices.quadBL, drawX + offsetX, bottomY + offsetY, left, bottom, left, bottom)
    drawQuad(image, slices.quadB, bodyX + offsetX, bottomY + offsetY, centerW, bottom, slices.centerW, bottom)
    drawQuad(image, slices.quadBR, rightX + offsetX, bottomY + offsetY, right, bottom, right, bottom)
  end

  local drawOpts = opts or nil
  if drawOpts and drawOpts.shadow then
    local shadow = drawOpts.shadow
    local shadowDx = tonumber(shadow.dx) or 2
    local shadowDy = tonumber(shadow.dy) or 2
    local shadowAlpha = tonumber(shadow.alpha) or 0.28
    if shadowAlpha > 0 then
      love.graphics.setColor(0, 0, 0, shadowAlpha)
      drawBody(shadowDx, shadowDy)
    end
  end

  local color = drawOpts and drawOpts.color or nil
  if type(color) == "table" then
    local red = tonumber(color[1]) or 1
    local green = tonumber(color[2]) or 1
    local blue = tonumber(color[3]) or 1
    local alpha = tonumber(color[4]) or 1
    love.graphics.setColor(red, green, blue, alpha)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  drawBody(0, 0)
end

return NineSlice

