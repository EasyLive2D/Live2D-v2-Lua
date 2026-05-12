local Id = require("live2d.core.id.id")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")

local Live2D = {}

Live2D.L2D_OUTSIDE_PARAM_AVAILABLE = false
Live2D.clippingMaskBufferSize = 256
Live2D.frameBuffers = {}
Live2D.__glContext = {}
Live2D.__firstInit = true

function Live2D.init()
    if Live2D.__firstInit then
        Live2D.__firstInit = false
    end
end

function Live2D.clearBuffer()
    Live2DGLWrapper.clearColor(0, 0, 0, 0)
    Live2DGLWrapper.clear(Live2DGLWrapper.COLOR_BUFFER_BIT)
end

function Live2D.dispose()
    Id.releaseStored()
end

return Live2D
