local ALive2DModel = require("live2d.core.alive2d_model")
local DrawParamOpenGL = require("live2d.core.graphics.draw_param_opengl")

local Live2DModelOpenGL = setmetatable({}, { __index = ALive2DModel })
Live2DModelOpenGL.__index = Live2DModelOpenGL

function Live2DModelOpenGL.new()
    local self = setmetatable(ALive2DModel.new(), Live2DModelOpenGL)
    self.drawParamGL = DrawParamOpenGL.new()
    return self
end

function Live2DModelOpenGL:resize(ww, wh)
    self.drawParamGL:resize(ww, wh)
end

function Live2DModelOpenGL:update()
    self.modelContext:update()
    self.modelContext:preDraw(self.drawParamGL)
end

function Live2DModelOpenGL:draw()
    self.modelContext:draw(self.drawParamGL)
end

function Live2DModelOpenGL:getDrawParam()
    return self.drawParamGL
end

function Live2DModelOpenGL:setMatrix(aH)
    self.drawParamGL:setMatrix(aH)
end

function Live2DModelOpenGL.loadModel(aI)
    local aH = Live2DModelOpenGL.new()
    ALive2DModel.loadModel_exe(aH, aI)
    return aH
end

function Live2DModelOpenGL:setTexture(aI, aH)
    if self.drawParamGL == nil then
        error("current gl is none")
    end
    self.drawParamGL:setTexture(aI, aH)
end

return Live2DModelOpenGL
