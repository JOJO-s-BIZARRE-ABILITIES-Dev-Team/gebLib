local now = 0
local nextEntityId = 0
local failCreation = false
local scheduledTimers = {}
local blendCalls = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertNear(actual, expected, tolerance, message)
    if math.abs(actual - expected) > tolerance then
        error((message or "values differ") .. ": expected " .. expected .. ", got " .. actual, 2)
    end
end

function isnumber(value) return type(value) == "number" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function CurTime() return now end

NULL = {valid = false}
vector_origin = {}
angle_zero = {}

timer = {}
function timer.Remove(name) scheduledTimers[name] = nil end
function timer.Create(name, delay, repetitions, callback)
    scheduledTimers[name] = {delay = delay, repetitions = repetitions, callback = callback}
end

render = {}
function render.SetBlend(blend) blendCalls[#blendCalls + 1] = blend end

local function newEntity(clientProp)
    nextEntityId = nextEntityId + 1
    local entity = {
        id = nextEntityId,
        valid = true,
        clientProp = clientProp,
        modelScale = 1.5,
        scaleCalls = {},
        removeCallbacks = {},
        drawCount = 0,
    }

    function entity:GetModelScale() return self.modelScale end
    function entity:SetModelScale(scale, duration)
        self.modelScale = scale
        self.scaleCalls[#self.scaleCalls + 1] = {scale = scale, duration = duration}
    end
    function entity:CallOnRemove(name, callback) self.removeCallbacks[name] = callback end
    function entity:DrawModel() self.drawCount = self.drawCount + 1 end
    function entity:Remove()
        if not self.valid then return end
        self.valid = false
        for _, callback in pairs(self.removeCallbacks) do callback(self) end
    end

    return entity
end

ents = {}
function ents.CreateClientProp()
    if failCreation then return NULL end
    return newEntity(true)
end
function ents.CreateClientside() return NULL end

function ClientsideModel()
    if failCreation then return NULL end
    return newEntity(false)
end

gebLib = {}
dofile("lua/geblib/visuals.lua")

local Visuals = gebLib.Visuals
local timerName = "gebLib.Visuals.Debris"

do
    local debris = Visuals.CreateDebris("model", false, 5)
    assertEqual(Visuals.GetDebrisCount(), 1, "active debris count")
    assertEqual(#debris.scaleCalls, 2, "render-only debris should use one engine transition")
    assertEqual(debris.scaleCalls[1].scale, 0, "growth start scale")
    assertEqual(debris.scaleCalls[1].duration, 0, "growth start is immediate")
    assertEqual(debris.scaleCalls[2].scale, 1.5, "growth target scale")
    assertEqual(debris.scaleCalls[2].duration, 0.25, "growth transition duration")
    assertNear(scheduledTimers[timerName].delay, 4, 0.0001, "fade timer")
    assertEqual(debris.RenderOverride, nil, "full-opacity debris should stay on the engine draw path")

    now = 4
    scheduledTimers[timerName].callback()
    assertEqual(type(debris.RenderOverride), "function", "fade should install the render override")
    assertNear(scheduledTimers[timerName].delay, 1, 0.0001, "expiry timer after fade starts")
    debris.RenderOverride(debris)
    assertEqual(debris.drawCount, 1, "full-opacity draw")
    assertEqual(#blendCalls, 0, "full-opacity draws should not touch global blend")

    now = 4.5
    debris.RenderOverride(debris)
    assertEqual(debris.drawCount, 2, "fading draw")
    assertNear(blendCalls[1], 0.5, 0.0001, "fade blend")
    assertEqual(blendCalls[2], 1, "blend restoration")

    Visuals.ClearDebris()
    assertEqual(Visuals.GetDebrisCount(), 0, "clear debris count")
    assertEqual(IsValid(debris), false, "clear should remove entities")
    assertEqual(scheduledTimers[timerName], nil, "clear should stop the scheduler")
end

do
    now = 10
    local long = Visuals.CreateDebris("long", false, 10)
    local short = Visuals.CreateDebris("short", true, 2)
    assertEqual(#short.scaleCalls, 0, "physical client props should not animate their scale")
    assertNear(scheduledTimers[timerName].delay, 1, 0.0001, "earliest fade should lead the heap")

    now = 11
    scheduledTimers[timerName].callback()
    assertEqual(IsValid(short), true, "fade start should retain debris")
    assertEqual(type(short.RenderOverride), "function", "fade start should install rendering")
    assertEqual(Visuals.GetDebrisCount(), 2, "fade start should retain the active count")
    assertNear(scheduledTimers[timerName].delay, 1, 0.0001, "fading debris expiry")

    now = 12
    scheduledTimers[timerName].callback()
    assertEqual(IsValid(short), false, "due debris should expire")
    assertEqual(IsValid(long), true, "later debris should remain")
    assertEqual(Visuals.GetDebrisCount(), 1, "expiry should update the active count")
    assertNear(scheduledTimers[timerName].delay, 7, 0.0001, "next fade should be scheduled")

    long:Remove()
    assertEqual(Visuals.GetDebrisCount(), 0, "external removal should unregister debris")
    assertEqual(scheduledTimers[timerName], nil, "external removal should stop an empty scheduler")
end

do
    now = 20
    Visuals.MaxDebris = 2
    local first = Visuals.CreateDebris("first", false, 10)
    local second = Visuals.CreateDebris("second", false, 20)
    local third = Visuals.CreateDebris("third", false, 30)

    assertEqual(IsValid(first), false, "the soonest-expiring debris should be evicted at the cap")
    assertEqual(IsValid(second), true, "later debris should survive cap eviction")
    assertEqual(IsValid(third), true, "new debris should be registered")
    assertEqual(Visuals.GetDebrisCount(), 2, "debris cap")

    failCreation = true
    assertEqual(Visuals.CreateDebris("invalid", false, 1), NULL, "failed model creation")
    assertEqual(Visuals.GetDebrisCount(), 2, "failed creation should not evict valid debris")
    failCreation = false

    Visuals.RemoveDebris(second)
    assertEqual(IsValid(second), false, "manual removal")
    assertEqual(Visuals.GetDebrisCount(), 1, "manual removal count")
    Visuals.ClearDebris()
end

do
    now = 0
    Visuals.MaxDebris = 1024
    for index = 1, 100 do
        local lifetime = index * 37 % 100 + 1
        Visuals.CreateDebris("heap", false, lifetime)
    end

    for expired = 1, 100 do
        local scheduled = scheduledTimers[timerName]
        assert(scheduled, "heap should retain its next expiry")
        assertNear(scheduled.delay, 1, 0.0001, "heap expiry order")
        now = now + scheduled.delay
        scheduled.callback()
        assertEqual(Visuals.GetDebrisCount(), 100 - expired, "heap expiry count")
    end

    assertEqual(scheduledTimers[timerName], nil, "heap should stop after its final expiry")
end

do
    local debris = Visuals.CreateDebris("reload", false, 10)
    dofile("lua/geblib/visuals.lua")
    assertEqual(IsValid(debris), false, "hot reload should remove debris owned by the old scheduler")
    assertEqual(Visuals.GetDebrisCount(), 0, "hot reload should start with an empty scheduler")
end

print("visuals: ok")
