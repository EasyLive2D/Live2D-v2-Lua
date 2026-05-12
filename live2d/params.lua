local StandardParams = {
    ParamAngleX = "PARAM_ANGLE_X",
    ParamAngleY = "PARAM_ANGLE_Y",
    ParamAngleZ = "PARAM_ANGLE_Z",
    ParamEyeLOpen = "PARAM_EYE_L_OPEN",
    ParamEyeROpen = "PARAM_EYE_R_OPEN",
    ParamEyeLSmile = "PARAM_EYE_L_SMILE",
    ParamEyeRSmile = "PARAM_EYE_R_SMILE",
    ParamEyeBallX = "PARAM_EYE_BALL_X",
    ParamEyeBallY = "PARAM_EYE_BALL_Y",
    ParamEyeBallForm = "PARAM_EYE_BALL_FORM",
    ParamBrowLX = "PARAM_BROW_L_X",
    ParamBrowLY = "PARAM_BROW_L_Y",
    ParamBrowLAngle = "PARAM_BROW_L_ANGLE",
    ParamBrowLForm = "PARAM_BROW_L_FORM",
    ParamBrowRX = "PARAM_BROW_R_X",
    ParamBrowRY = "PARAM_BROW_R_Y",
    ParamBrowRAngle = "PARAM_BROW_R_ANGLE",
    ParamBrowRForm = "PARAM_BROW_R_FORM",
    ParamMouthOpenY = "PARAM_MOUTH_OPEN_Y",
    ParamMouthForm = "PARAM_MOUTH_FORM",
    ParamSmile = "PARAM_SMILE",
    ParamTere = "PARAM_TERE",
    ParamBodyAngleX = "PARAM_BODY_ANGLE_X",
    ParamBodyAngleZ = "PARAM_BODY_ANGLE_Z",
    ParamBreath = "PARAM_BREATH",
    ParamHairFront = "PARAM_HAIR_FRONT",
    ParamHairSide = "PARAM_HAIR_SIDE",
    ParamHairBack = "PARAM_HAIR_BACK",
    ParamHairFuwa = "PARAM_HAIR_FUWA",
    ParamShoulderX = "PARAM_SHOULDER_X",
    ParamBustX = "PARAM_BUST_X",
    ParamBustY = "PARAM_BUST_Y",
    ParamBaseX = "PARAM_BASE_X",
    ParamBaseY = "PARAM_BASE_Y",
}

local Parameter = {}
Parameter.__index = Parameter

Parameter.TYPE_INNER = 0
Parameter.TYPE_OUTER = 1

function Parameter.new()
    local self = setmetatable({}, Parameter)
    self.id = ""
    self.type = 0
    self.value = 0
    self.max = 0
    self.min = 0
    self.default = 0
    return self
end

return {
    StandardParams = StandardParams,
    Parameter = Parameter,
}
