--[[
파일명: main.lua
모듈명: Main

역할:
- LÖVE 진입점
- App 업데이트/렌더 및 입력 콜백 연결

외부에서 사용 가능한 함수:
- love.load()
- love.update(dt)
- love.draw()
- love.mousepressed(x, y, button)
- love.keypressed(key)
- love.textinput(text)
- love.textedited(text, start, length)
- love.resize(w, h)
- love.quit()

주의:
- 입력 좌표 변환은 App 내부에서 처리한다
]]

local Constants = require("constants")
local RenderScale = require("managers.render_scale")
local FontManager = require("assets.font_manager")
local App = require("app")

local app
local renderScale

function love.load()
  math.randomseed(os.time())
  love.keyboard.setKeyRepeat(true)
  FontManager.loadFonts()
  love.graphics.setFont(FontManager.getFont("ui"))

  renderScale = RenderScale.new(Constants.BASE_WORLD_W, Constants.BASE_WORLD_H)
  app = App.new(renderScale)
end

function love.update(dt)
  app:update(dt)
end

function love.draw()
  renderScale:beginDraw()
  app:draw()
  renderScale:endDraw()
end

function love.mousepressed(x, y, button)
  app:mousepressed(x, y, button)
end

function love.keypressed(key)
  app:keypressed(key)
end

function love.textinput(text)
  app:textinput(text)
end

function love.textedited(text, start, length)
  app:textedited(text, start, length)
end

function love.resize(w, h)
  app:resize(w, h)
end

function love.quit()
  app:shutdown()
end
