-- runtime_optimization_test.lua - allocation-sensitive runtime helpers
package.path = package.path .. ";./?.lua;./?/init.lua"

local Id = require("live2d.core.id.id")
local ModelContext = require("live2d.core.model_context")
local L2DMatrix44 = require("live2d.framework.matrix.l2d_matrix44")
local ClippingManagerOpenGL = require("live2d.core.graphics.clipping_manager_opengl")

local passed, total = 0, 0
local function check(name, ok, msg)
    total = total + 1
    if ok then
        passed = passed + 1
        print("[PASS] " .. name)
    else
        print("[FAIL] " .. name .. ": " .. (msg or "unknown"))
    end
end

local context = ModelContext.new({})
local id = Id.getID("ParamOptimizationTest")
local index = context:getParamIndex(id)
check("parameter lookup cache returns same index", context:getParamIndex(id) == index)
Id.releaseStored()
check("parameter cache accepts reinterned id", context:getParamIndex(Id.getID("ParamOptimizationTest")) == index)
check("parameter cache does not duplicate values", #context.paramValues == 1)

local function close(a, b)
    return math.abs(a - b) < 1e-9
end

local matrix = L2DMatrix44.new()
matrix:multTranslate(2, 3)
matrix:multScale(4, 5)
local values = matrix:getArray()
check("specialized matrix transforms preserve multiplication", close(values[1], 4)
    and close(values[6], 5) and close(values[13], 8) and close(values[14], 15))

local a = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }
local identity = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
L2DMatrix44.mul(identity, a, a)
local alias_ok = true
for i = 1, 16 do alias_ok = alias_ok and a[i] == i end
check("matrix multiplication remains alias safe", alias_ok)

local framebuffer_creations = 0
local clipping = ClippingManagerOpenGL.new({
    setChannelFlagAsColor = function() end,
    createFramebuffer = function() framebuffer_creations = framebuffer_creations + 1 end,
})
clipping:init({}, {}, {})
check("unmasked moc skips clipping framebuffer", framebuffer_creations == 0)

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed ~= total then os.exit(1) end
print("ALL TESTS PASSED!")
