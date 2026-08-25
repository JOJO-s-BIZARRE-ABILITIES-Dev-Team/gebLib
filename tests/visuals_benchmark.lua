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
local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Add(other)
    self.x = self.x + other.x
    self.y = self.y + other.y
    self.z = self.z + other.z
end
function Vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vectorMeta) end
function VectorRand(minimum, maximum) return Vector(maximum, minimum, maximum) end
vector_origin = Vector(0, 0, 0)
angle_zero = {}
color_white = {r = 255, g = 255, b = 255, a = 255}
RENDERMODE_TRANSCOLOR = 1
kRenderFxFadeFast = 6
math.Rand = math.Rand or function(minimum, maximum) return (minimum + maximum) / 2 end

timer = {}
function timer.Remove(name) scheduledTimers[name] = nil end
function timer.Create(name, delay, repetitions, callback)
    scheduledTimers[name] = {at = now + delay, repetitions = repetitions, callback = callback}
end

hook = {}
function hook.Add(eventName, hookName, callback) hooks[eventName] = callback end

render = {SetBlend = function() end}

local particleMethods = {}
function particleMethods:SetDieTime() end
function particleMethods:SetStartAlpha() end
function particleMethods:SetEndAlpha() end
function particleMethods:SetStartSize() end
function particleMethods:SetEndSize() end
function particleMethods:SetColor() end
function particleMethods:SetVelocity() end
function particleMethods:SetGravity() end
function particleMethods:SetCollide() end
function particleMethods:SetLighting() end
function particleMethods:SetRoll() end
function particleMethods:SetRollDelta() end
function particleMethods:SetBounce() end
local particleMeta = {__index = particleMethods}

local function newParticle() return setmetatable({}, particleMeta) end

function ParticleEmitter()
    local emitter = {}
    function emitter:Add() return newParticle() end
    function emitter:Finish() end
    return emitter
end

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
    function entity:SetRenderMode(mode) self.renderMode = mode end
    function entity:SetRenderFX(effect) self.renderFX = effect end
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
if arg and arg[3] == "-" then
    assert(load(io.read("*a"), "@lua/geblib/visuals.lua"))()
else
    dofile((arg and arg[3]) or "lua/geblib/visuals.lua")
end

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
local timerName = "gebLib.Visuals.Debris"

local function runDueTimers()
    while true do
        local pending = scheduledTimers[timerName]
        if not pending or pending.at > now then return end
        scheduledTimers[timerName] = nil
        pending.callback()
    end
end

now = lifetime - 1
local fadeStarted = os.clock()
runDueTimers()
local fadeElapsed = os.clock() - fadeStarted

local renderOverrides = {}
local nativeFades = 0
for index = 1, #entities do
    local entity = entities[index]
    if IsValid(entity) and entity.RenderOverride then
        renderOverrides[#renderOverrides + 1] = entity
    end
    if IsValid(entity) and entity.renderFX == kRenderFxFadeFast then nativeFades = nativeFades + 1 end
end

local visibleStarted = os.clock()
for frame = 1, frameCount do
    for index = 1, #renderOverrides do
        local entity = renderOverrides[index]
        entity.RenderOverride(entity)
    end
end
local visibleElapsed = os.clock() - visibleStarted
local visibleCallbacks = #renderOverrides * frameCount

now = lifetime
local expireStarted = os.clock()
runDueTimers()
if hooks.Think then hooks.Think() end
local expireElapsed = os.clock() - expireStarted

local burstElapsed
local emitted = 0
if gebLib.Visuals.CreateDebrisBurst then
    local burstStarted = os.clock()
    emitted = gebLib.Visuals.CreateDebrisBurst("effects/fleck", vector_origin, debrisCount, {
        collide = false,
    })
    burstElapsed = os.clock() - burstStarted
end

print("gebLib debris local Lua benchmark")
print(string.format("%d debris created in %.3f ms", debrisCount, createElapsed * 1000))
print(string.format("%d idle frames in %.3f ms", frameCount, idleElapsed * 1000))
print(string.format(
    "%d Lua fade render callbacks in %.3f ms",
    visibleCallbacks,
    visibleElapsed * 1000
))
print(string.format("%d native entity fades started", nativeFades))
print(string.format("fade scheduling completed in %.3f ms", fadeElapsed * 1000))
print(string.format("%d debris expired in %.3f ms", debrisCount, expireElapsed * 1000))
if burstElapsed then
    print(string.format("%d particle debris emitted in %.3f ms", emitted, burstElapsed * 1000))
end
print(string.format(
    "%d active before expiry, %d after, %d SetModelScale calls",
    activeBeforeExpiry,
    activeCount(),
    scaleCalls
))
