package.path = package.path .. ";./?.lua;./?/init.lua"

local Live2DFramework = require("live2d.framework.Live2DFramework")
local PlatformManager = require("live2d.platform_manager")
local L2DExpressionMotion = require("live2d.framework.motion.l2d_expression_motion")

Live2DFramework.setPlatformManager(PlatformManager.new())

local passed = 0
local total = 0

local function check(name, ok, msg)
    total = total + 1
    if ok then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. ": " .. (msg or "unknown"))
    end
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then error(err) end
    local data = f:read("*a")
    f:close()
    return data
end

local motion = L2DExpressionMotion.loadJson(read_all("resources/Rana/expressions/exp_smile01.exp3.json"))

check("Rana exp3 parameters are parsed", #motion.paramList == 50, "expected 50, got " .. tostring(#motion.paramList))
check("FadeInTime is converted to milliseconds", motion.fadeInMSec == 1000, "got " .. tostring(motion.fadeInMSec))
check("FadeOutTime is converted to milliseconds", motion.fadeOutMSec == 1000, "got " .. tostring(motion.fadeOutMSec))

local by_id = {}
for _, param in ipairs(motion.paramList) do
    by_id[param.id] = param
end

check("numeric Blend 1 maps to Add", by_id["Paramsmile01"] and by_id["Paramsmile01"].type == L2DExpressionMotion.TYPE_ADD)
check("numeric Blend 2 maps to Multiply", by_id["ParamEyeLOpen"] and by_id["ParamEyeLOpen"].type == L2DExpressionMotion.TYPE_MULT)

local calls = {}
local model = {
    addToParamFloat = function(_, id, value, weight)
        calls[#calls + 1] = { op = "add", id = id, value = value, weight = weight }
    end,
    multParamFloat = function(_, id, value, weight)
        calls[#calls + 1] = { op = "mult", id = id, value = value, weight = weight }
    end,
    setParamFloat = function(_, id, value, weight)
        calls[#calls + 1] = { op = "set", id = id, value = value, weight = weight }
    end,
}

motion:updateParamExe(model, 0, 0.5, nil)

local called = {}
for _, call in ipairs(calls) do
    called[call.id] = call
end

check("Add blend is applied during playback", called["Paramsmile01"] and called["Paramsmile01"].op == "add")
check("Multiply blend is applied during playback", called["ParamEyeLOpen"] and called["ParamEyeLOpen"].op == "mult")
check("Playback forwards expression weight", called["Paramsmile01"] and called["Paramsmile01"].weight == 0.5)

local overwrite = L2DExpressionMotion.loadJson([[{
  "Type": "Live2D Expression",
  "Parameters": [{ "Id": "ParamOverwrite", "Value": 0.25, "Blend": 3 }]
}]])
overwrite:updateParamExe(model, 0, 1.0, nil)
local last_call = calls[#calls]
check("numeric Blend 3 maps to Overwrite", last_call and last_call.op == "set" and last_call.id == "ParamOverwrite")

local immediate = L2DExpressionMotion.loadJson([[{
  "Type": "Live2D Expression",
  "FadeInTime": 0,
  "FadeOutTime": 0,
  "Parameters": []
}]])
check("exp3 zero FadeInTime stays immediate", immediate.fadeInMSec == 0, "got " .. tostring(immediate.fadeInMSec))
check("exp3 zero FadeOutTime stays immediate", immediate.fadeOutMSec == 0, "got " .. tostring(immediate.fadeOutMSec))

local legacy = L2DExpressionMotion.loadJson([[{
  "fade_in": 500,
  "fade_out": 600,
  "params": [
    { "id": "ParamLegacyAdd", "val": 0.8, "def": 0.3, "calc": "add" },
    { "id": "ParamLegacyMult", "val": 2.0, "def": 4.0, "calc": "mult" },
    { "id": "ParamLegacySet", "val": 0.7, "calc": "set" }
  ]
}]])
check("legacy fade_in remains milliseconds", legacy.fadeInMSec == 500)
check("legacy fade_out remains milliseconds", legacy.fadeOutMSec == 600)
check("legacy add subtracts default", math.abs(legacy.paramList[1].value - 0.5) < 0.0001)
check("legacy multiply divides default", math.abs(legacy.paramList[2].value - 0.5) < 0.0001)
check("legacy set keeps absolute value", legacy.paramList[3].value == 0.7)

print(string.format("\n%d/%d tests passed", passed, total))
if passed ~= total then
    os.exit(1)
end
