local debrisCount = tonumber(arg and arg[1]) or 5000
local frameCount = tonumber(arg and arg[2]) or 600
local now = 0
local scaleCalls = 0
local nextEntityId = 0
local hooks = {}
local scheduledTimers = {}
local entities = {}

function isnumber(value) return type(value) == "number" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function CurTime() return now end
function FrameTime() return 1 / 60 end
function Lerp(fraction, from, to) return from + (to - from) * fraction end

math.Clamp = math.Clamp or function(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end
math.ease = math.ease or {}
math.ease.InOutSine = math.ease.InOutSine or function(value)
    return -(math.cos(math.pi * value) - 1) / 2
end

NULL = {valid = false}
vector_origin = {}
angle_zero = {}

timer = {}
function timer.Remove(name) scheduledTimers[name] = nil end
function timer.Create(name, delay, repetitions, callback)
    scheduledTimers[name] = {at = now + delay, repetitions = repetitions, callback = callback}
end

hook = {}
function hook.Add(eventName, hookName, callback) hooks[eventName] = callback end

render = {SetBlend = function() end}

local function newEntity()
    nextEntityId = nextEntityId + 1
    local entity = {
        id = nextEntityId,
        valid = true,
        modelScale = 1,
        removeCallbacks = {},
    }
    entities[#entities + 1] = entity

    function entity:GetModelScale() return self.modelScale end
    function entity:SetModelScale(scale)
        self.modelScale = scale
        scaleCalls = scaleCalls + 1
    end
    function entity:CallOnRemove(name, callback) self.removeCallbacks[name] = callback end
    function entity:DrawModel() end
    function entity:Remove()
        if not self.valid then return end
        self.valid = false
        for _, callback in pairs(self.removeCallbacks) do callback(self) end
    end
    return entity
end

ents = {
    CreateClientProp = function() return newEntity() end,
    CreateClientside = function() return NULL end,
}
function ClientsideModel() return newEntity() end

gebLib = {Visuals = {MaxDebris = debrisCount}}
dofile("lua/geblib/visuals.lua")

collectgarbage("collect")
local createStarted = os.clock()
local lifetime = math.max(60, frameCount / 60 + 60)
for index = 1, debrisCount do
    gebLib.Visuals.CreateDebris("benchmark", false, lifetime)
end
local createElapsed = os.clock() - createStarted

local idleStarted = os.clock()
for frame = 1, frameCount do
    now = frame / 60
    if hooks.Think then hooks.Think() end
end
local idleElapsed = os.clock() - idleStarted

local function activeCount()
    if gebLib.Visuals.GetDebrisCount then return gebLib.Visuals.GetDebrisCount() end

    local active = 0
    for entity in pairs(gebLib.Visuals.ActiveDebris) do
        if IsValid(entity) then active = active + 1 end
    end
    return active
end

local activeBeforeExpiry = activeCount()
now = lifetime
local expireStarted = os.clock()
local expiryTimer = scheduledTimers["gebLib.Visuals.Debris"]
if expiryTimer then
    expiryTimer.callback()
elseif hooks.Think then
    hooks.Think()
end
local expireElapsed = os.clock() - expireStarted

print("gebLib debris local Lua benchmark")
print(string.format("%d debris created in %.3f ms", debrisCount, createElapsed * 1000))
print(string.format("%d idle frames in %.3f ms", frameCount, idleElapsed * 1000))
print(string.format("%d debris expired in %.3f ms", debrisCount, expireElapsed * 1000))
print(string.format(
    "%d active before expiry, %d after, %d SetModelScale calls",
    activeBeforeExpiry,
    activeCount(),
    scaleCalls
))
