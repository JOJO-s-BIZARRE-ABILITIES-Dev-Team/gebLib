local now = 0
local hooks = {}
local world = {valid = true}

gebLib = {}

function isnumber(value) return type(value) == "number" end
function isstring(value) return type(value) == "string" end
function isfunction(value) return type(value) == "function" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function CurTime() return now end

game = {
    GetWorld = function() return world end,
}

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

local function testTimelineAndRepetition()
    local events = {start = 0, middle = 0, finish = 0, remove = 0}
    local action = gebLib.Action.New(world, 2)

    action:OnStart(function() events.start = events.start + 1 end)
    action:AddEvent("middle", 0.5, function() events.middle = events.middle + 1 end)
    action:SetEnd(function() events.finish = events.finish + 1 end)
    action:OnRemove(function() events.remove = events.remove + 1 end)

    assertEqual(action:Start(1, 1), true, "action should start")
    tick(0.5)
    assertEqual(events.middle, 0, "delay should postpone events")
    tick(1.5)
    assertEqual(events.middle, 1, "event should run in the first cycle")
    tick(3)
    assertEqual(events.finish, 1, "end event should run in the first cycle")
    tick(3.5)
    assertEqual(events.middle, 2, "event should reload for the repeated cycle")
    tick(5)

    assertEqual(events.start, 1, "start callback should run once")
    assertEqual(events.finish, 2, "end event should run once per cycle")
    assertEqual(events.remove, 1, "remove callback should run once")
    assertEqual(action.Removed, true, "completed action should remove itself")
end

local function testPauseAndResume()
    local eventCount = 0
    local action = gebLib.Action.New(2)
    action:AddEvent("event", 1, function() eventCount = eventCount + 1 end)

    now = 0
    action:Start()
    tick(0.5)
    assertEqual(action:Pause(), true, "playing action should pause")
    tick(10)
    assertEqual(eventCount, 0, "paused time should not advance the action")
    assertEqual(action:Resume(), true, "paused action should resume")
    tick(10.4)
    assertEqual(eventCount, 0, "resume should retain elapsed action time")
    tick(10.5)
    assertEqual(eventCount, 1, "event should run after the remaining delay")
    action:Stop()
end

local function testInvalidEntityCleanup()
    local entity = {valid = true}
    local action = gebLib.Action.New(entity, 10)
    action:Start()
    entity.valid = false
    tick(1)
    assertEqual(action.Removed, true, "invalid owner should remove its action")
end

local function testStartCallbackCanPause()
    local eventCount = 0
    local action = gebLib.Action.New(world, 1)
    action:AddEvent("event", 0.5, function() eventCount = eventCount + 1 end)
    action:OnStart(function(current) current:Pause() end)

    now = 0
    assertEqual(action:Start(), true, "start callback should be able to pause")
    tick(5)
    assertEqual(eventCount, 0, "start-paused action should not advance")
    action:Resume()
    tick(5.5)
    assertEqual(eventCount, 1, "start-paused action should resume normally")
    action:Stop()
end

assert(loadfile("lua/includes/geblib_action.lua"))()
testTimelineAndRepetition()
testPauseAndResume()
testInvalidEntityCleanup()
testStartCallbackCanPause()

print("actions: ok")
