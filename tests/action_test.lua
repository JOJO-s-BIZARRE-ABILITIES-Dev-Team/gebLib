local now = 0
local hooks = {}
local world = {valid = true}

gebLib = {}

function isnumber(value) return type(value) == "number" end
function isfunction(value) return type(value) == "function" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function CurTime() return now end

hook = {}

function hook.Add(eventName, hookName, callback)
    hooks[eventName] = hooks[eventName] or {}
    hooks[eventName][hookName] = callback
end

function hook.Remove(eventName, hookName)
    if hooks[eventName] then hooks[eventName][hookName] = nil end
end

local function tick(time)
    now = time
    local callbacks = {}
    for _, callback in pairs(hooks.Think or {}) do
        callbacks[#callbacks + 1] = callback
    end
    for _, callback in ipairs(callbacks) do callback() end
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

assert(loadfile("lua/geblib/scheduled_action.lua"))()

do
    local calls = 0
    local action = gebLib.ScheduledAction.After(world, 2, function(current)
        calls = calls + 1
        assertEqual(current:IsPending(), false, "callback should observe a completed action")
    end)

    assertEqual(next(action), nil, "scheduled action handle should not expose lifecycle state")
    tick(1.99)
    assertEqual(calls, 0, "scheduled callback should wait for its delay")
    assertEqual(action:IsPending(), true, "action should remain pending before its delay")
    tick(2)
    assertEqual(calls, 1, "scheduled callback should run once")
    tick(10)
    assertEqual(calls, 1, "completed callback must not repeat")
    assertEqual(action:IsPending(), false, "completed action should not remain pending")
end

do
    now = 0
    local calls = 0
    local action = gebLib.ScheduledAction.After(world, 2, function() calls = calls + 1 end)

    tick(0.5)
    assertEqual(action:Pause(), true, "pending action should pause")
    tick(10)
    assertEqual(calls, 0, "paused action should not advance")
    assertEqual(action:Resume(), true, "paused action should resume")
    tick(11.49)
    assertEqual(calls, 0, "resumed action should retain elapsed time")
    tick(11.5)
    assertEqual(calls, 1, "resumed action should run after the remaining delay")
end

do
    now = 0
    local calls = 0
    local action = gebLib.ScheduledAction.After(world, 4, function() calls = calls + 1 end)

    tick(1)
    assertEqual(action:SetTimeScale(2), true, "pending action should accept a time scale")
    tick(2.49)
    assertEqual(calls, 0, "time scale should preserve work accrued at the old rate")
    tick(2.5)
    assertEqual(calls, 1, "time scale should accelerate the remaining delay")
end

do
    now = 0
    local owner = {valid = true}
    local calls = 0
    local action = gebLib.ScheduledAction.After(owner, 10, function() calls = calls + 1 end)

    assertEqual(action:Pause(), true, "pending action should pause before owner cleanup")
    owner.valid = false
    tick(1)
    assertEqual(calls, 0, "invalid owner should not receive its callback")
    assertEqual(action:IsPending(), false, "invalid owner should cancel its action")
    assertEqual(action:Cancel(), false, "cancel should be idempotent")
end

do
    now = 0
    local calls = 0
    local action = gebLib.ScheduledAction.After(world, 1, function() calls = calls + 1 end)

    assertEqual(action:Cancel(), true, "pending action should cancel")
    tick(2)
    assertEqual(calls, 0, "cancelled action should not run")
    assertEqual(action:IsPending(), false, "cancelled action should not remain pending")
end

print("scheduled actions: ok")
