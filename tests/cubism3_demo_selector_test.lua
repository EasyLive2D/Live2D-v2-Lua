-- cubism3_demo_selector_test.lua - demo expression/motion selector behavior
package.path = package.path .. ";./?.lua;./?/init.lua"

local selector_module = require("live2d.cubism3.demo_selector")

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

local selector = selector_module.new({
    motions = {
        { label = "Idle #1" },
        { label = "Tap #2" },
    },
    expressions = {
        { label = "exp_smile04" },
        { label = "exp_sad01" },
    },
})

local motion_rect = selector:motion_rect()
local expression_rect = selector:expression_rect()
check("motion selector starts at top-left", motion_rect.x == 16 and motion_rect.y == 16)
check("expression selector sits below motion selector", expression_rect.x == motion_rect.x
    and expression_rect.y > motion_rect.y + motion_rect.height)

local chosen_motion
local hit, item, index = selector:handle_click(20, 20, function(selected, selected_index)
    chosen_motion = selected.label .. ":" .. tostring(selected_index)
end)
check("motion button click selects first motion", hit == "motion"
    and item.label == "Idle #1"
    and index == 1
    and chosen_motion == "Idle #1:1")
check("motion label shows selected motion", selector:motion_label() == "Motion: Idle #1")

selector:handle_click(20, 20)
check("motion selector cycles to next motion", selector:motion_label() == "Motion: Tap #2")

local chosen_expression
hit, item, index = selector:handle_click(expression_rect.x + 4, expression_rect.y + 4, function() end,
    function(selected, selected_index)
        chosen_expression = selected.label .. ":" .. tostring(selected_index)
    end)
check("expression button click selects first expression", hit == "expression"
    and item.label == "exp_smile04"
    and index == 1
    and chosen_expression == "exp_smile04:1")
check("expression label shows selected expression", selector:expression_label() == "Expression: exp_smile04")

hit = selector:handle_click(400, 400)
check("outside click is ignored by selector", hit == nil)

local empty_selector = selector_module.new()
check("empty selector labels are stable", empty_selector:motion_label() == "Motion: none"
    and empty_selector:expression_label() == "Expression: none")

print(string.format("\n=== Results: %d/%d passed ===", passed, total))
if passed == total then
    print("ALL TESTS PASSED!")
    os.exit(0)
else
    print("SOME TESTS FAILED!")
    os.exit(1)
end
