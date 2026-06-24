local Live2D = require("live2d.core.live2d")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local Live2DFramework = require("live2d.framework.Live2DFramework")
local lapp_define = require("live2d.lapp_define")
local LAppModel = require("live2d.lapp_model")

local M = {
    Live2D = Live2D,
    Live2DGLWrapper = Live2DGLWrapper,
    Live2DFramework = Live2DFramework,
    MotionPriority = lapp_define.MotionPriority,
    LAppModel = LAppModel,
}

function M.init()
    Live2D.init()
end

function M.dispose()
    Live2D.dispose()
end

return M
