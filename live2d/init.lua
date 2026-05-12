local Live2D = require("live2d.core.live2d")
local Live2DGLWrapper = require("live2d.core.live2d_gl_wrapper")
local log = require("live2d.core.util.log.ut_log")
local Live2DFramework = require("live2d.framework.Live2DFramework")
local lapp_define = require("live2d.lapp_define")
local LAppModel = require("live2d.lapp_model")
local params = require("live2d.params")
local PlatformManager = require("live2d.platform_manager")

local M = {
    Live2D = Live2D,
    Live2DGLWrapper = Live2DGLWrapper,
    log = log,
    Live2DFramework = Live2DFramework,
    MotionGroup = lapp_define.MotionGroup,
    MotionPriority = lapp_define.MotionPriority,
    HitArea = lapp_define.HitArea,
    LAppModel = LAppModel,
    Parameter = params.Parameter,
    StandardParams = params.StandardParams,
    PlatformManager = PlatformManager,
}

function M.init()
    Live2D.init()
end

function M.clearBuffer()
    Live2D.clearBuffer()
end

function M.setLogEnable(v)
    log.setLogEnable(v)
end

function M.dispose()
    Live2D.dispose()
end

return M
