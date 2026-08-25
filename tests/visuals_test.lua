local now = 0
local nextEntityId = 0
local failCreation = false
local scheduledTimers = {}
local blendCalls = {}
local emitters = {}

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
local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Add(other)
    self.x = self.x + other.x
    self.y = self.y + other.y
    self.z = self.z + other.z
end
function Vector(x, y, z) return setmetatable({x = x, y = y, z = z}, vectorMeta) end
function VectorRand(minimum, maximum)
    return Vector(maximum, minimum, maximum)
end
vector_origin = Vector(0, 0, 0)
angle_zero = {}
color_white = {r = 255, g = 255, b = 255, a = 255}
RENDERMODE_TRANSCOLOR = 1
kRenderFxFadeFast = 6
math.Rand = math.Rand or function(minimum, maximum) return (minimum + maximum) / 2 end

timer = {}
function timer.Remove(name) scheduledTimers[name] = nil end
function timer.Create(name, delay, repetitions, callback)
    scheduledTimers[name] = {delay = delay, repetitions = repetitions, callback = callback}
end

render = {}
function render.SetBlend(blend) blendCalls[#blendCalls + 1] = blend end

function ParticleEmitter(position)
    local emitter = {position = position, particles = {}, finished = false}
    emitters[#emitters + 1] = emitter

    function emitter:Add(material, particlePosition)
        local particle = {material = material, position = particlePosition}
        self.particles[#self.particles + 1] = particle
        function particle:SetDieTime(value) self.dieTime = value end
        function particle:SetStartAlpha(value) self.startAlpha = value end
        function particle:SetEndAlpha(value) self.endAlpha = value end
        function particle:SetStartSize(value) self.startSize = value end
        function particle:SetEndSize(value) self.endSize = value end
        function particle:SetColor(r, g, b) self.color = {r = r, g = g, b = b} end
        function particle:SetVelocity(value) self.velocity = value end
        function particle:SetGravity(value) self.gravity = value end
        function particle:SetCollide(value) self.collide = value end
        function particle:SetLighting(value) self.lighting = value end
        function particle:SetRoll(value) self.roll = value end
        function particle:SetRollDelta(value) self.rollDelta = value end
        function particle:SetBounce(value) self.bounce = value end
        return particle
    end

    function emitter:Finish() self.finished = true end
    return emitter
end

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
    function entity:SetRenderMode(mode) self.renderMode = mode end
    function entity:SetRenderFX(effect) self.renderFX = effect end
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
    local position = Vector(1, 2, 3)
    local gravity = Vector(0, 0, -300)
    local emitted = Visuals.CreateDebrisBurst("effects/fleck", position, 1000, {
        lifetime = 4,
        size = 3,
        endSize = 1,
        speed = 10,
        spin = 90,
        velocity = Vector(1, 2, 3),
        gravity = gravity,
        collide = false,
        lighting = true,
        color = {r = 10, g = 20, b = 30, a = 200},
    })

    local emitter = emitters[#emitters]
    local particle = emitter.particles[1]
    assertEqual(emitted, 1000, "particle debris count")
    assertEqual(#emitter.particles, 1000, "particle allocation count")
    assertEqual(emitter.finished, true, "particle emitter should finish")
    assertEqual(Visuals.GetDebrisCount(), 0, "particle debris should not create entities")
    assertEqual(particle.material, "effects/fleck", "particle material")
    assertEqual(particle.dieTime, 4, "particle lifetime")
    assertEqual(particle.startAlpha, 200, "particle alpha")
    assertEqual(particle.endAlpha, 0, "particle fade")
    assertEqual(particle.startSize, 3, "particle size")
    assertEqual(particle.endSize, 1, "particle end size")
    assertEqual(particle.velocity.x, 11, "particle velocity x")
    assertEqual(particle.velocity.y, -8, "particle velocity y")
    assertEqual(particle.velocity.z, 13, "particle velocity z")
    assertEqual(particle.gravity, gravity, "particle gravity")
    assertEqual(particle.collide, false, "particle collision")
    assertEqual(particle.lighting, true, "particle lighting")
    assertEqual(particle.bounce, nil, "non-colliding particles should skip bounce")

    assertEqual(Visuals.CreateDebrisBurst("effects/fleck", position, 1), 1, "default particle burst")
    local defaultParticle = emitters[#emitters].particles[1]
    assertEqual(defaultParticle.collide, true, "particle collision default")
    assertNear(defaultParticle.bounce, 0.35, 0.0001, "particle bounce default")
    assertEqual(defaultParticle.lighting, false, "particle lighting default")
    assertEqual(Visuals.CreateDebrisBurst("", position, 1000), 0, "empty particle material")
    assertEqual(Visuals.CreateDebrisBurst("effects/fleck", position, 0), 0, "empty particle burst")
end

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
    assertEqual(debris.RenderOverride, nil, "native fade should stay on the engine draw path")
    assertEqual(debris.renderMode, RENDERMODE_TRANSCOLOR, "native fade render mode")
    assertEqual(debris.renderFX, kRenderFxFadeFast, "native fade effect")
    assertNear(scheduledTimers[timerName].delay, 1, 0.0001, "expiry timer after fade starts")
    assertEqual(debris.drawCount, 0, "native fade should not draw through Lua")
    assertEqual(#blendCalls, 0, "native fade should not touch global blend")

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
    assertEqual(short.RenderOverride, nil, "fade start should retain engine rendering")
    assertEqual(short.renderFX, kRenderFxFadeFast, "fade start should install native render FX")
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
