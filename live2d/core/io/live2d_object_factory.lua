local RotationDeformer = require("live2d.core.deformer.roation_deformer")
local WarpDeformer = require("live2d.core.deformer.warp_deformer")
local Mesh = require("live2d.core.draw.mesh")
local ModelImpl = require("live2d.core.model.model_impl")
local Avatar = require("live2d.core.model.avatar")
local PartsData = require("live2d.core.model.part")
local PivotManager = require("live2d.core.param.pivot_manager")
local ParamPivots = require("live2d.core.param.param_pivots")
local ParamDefFloat = require("live2d.core.param.param_def_float")
local ParamDefSet = require("live2d.core.param.param_def_set")

local Live2DObjectFactory = {}

function Live2DObjectFactory.create(clsNo)
    if clsNo < 100 then
        if clsNo == 65 then
            return WarpDeformer.new()
        elseif clsNo == 66 then
            return PivotManager.new()
        elseif clsNo == 67 then
            return ParamPivots.new()
        elseif clsNo == 68 then
            return RotationDeformer.new()
        elseif clsNo == 69 then
            return RotationDeformer.AffineEnt.new()
        elseif clsNo == 70 then
            return Mesh.new()
        end
    elseif clsNo < 150 then
        if clsNo == 131 then
            return ParamDefFloat.new()
        elseif clsNo == 133 then
            return PartsData.new()
        elseif clsNo == 136 then
            return ModelImpl.new()
        elseif clsNo == 137 then
            return ParamDefSet.new()
        elseif clsNo == 142 then
            return Avatar.new()
        end
    end
    error("Unknown class ID: " .. tostring(clsNo))
end

return Live2DObjectFactory
