if SERVER then return end

local Visuals = gebLib.Visuals
local emitters = {}
local HOOK_NAME = "gebLib.Visuals.ParticleEmitters"

local function removeEmitter(key, record)
    record = record or emitters[key]
    if record and record.Emitter and record.Emitter:IsValid() then
        record.Emitter:Finish()
    end
    emitters[key] = nil
end

local function stopWhenEmpty()
    if next(emitters) == nil then hook.Remove("Think", HOOK_NAME) end
end

local function maintainEmitters()
    local now = CurTime()
    for key, record in pairs(emitters) do
        local emitter = record.Emitter
        if not emitter or not emitter:IsValid() then
            emitters[key] = nil
        elseif now > record.LastUse + record.IdleTime
            and emitter:GetNumActiveParticles() == 0 then
            removeEmitter(key, record)
        end
    end
    stopWhenEmpty()
end

function Visuals.AcquireParticleEmitter(key, position, use3D, idleTime)
    if not isstring(key) or key == "" then
        error("particle emitter key must be a non-empty string", 2)
    end

    use3D = use3D == true
    idleTime = math.max(tonumber(idleTime) or 1, 0)
    local record = emitters[key]
    if record and record.Use3D ~= use3D then
        removeEmitter(key, record)
        record = nil
    end

    if not record or not record.Emitter or not record.Emitter:IsValid() then
        local emitter = ParticleEmitter(position or vector_origin, use3D)
        if not emitter then return nil end
        record = {Emitter = emitter, Use3D = use3D}
        emitters[key] = record
    else
        record.Emitter:SetPos(position or vector_origin)
    end

    record.LastUse = CurTime()
    record.IdleTime = idleTime
    hook.Add("Think", HOOK_NAME, maintainEmitters)
    return record.Emitter
end

function Visuals.ReleaseParticleEmitter(key)
    if not emitters[key] then return false end
    removeEmitter(key)
    stopWhenEmpty()
    return true
end

function Visuals.ClearParticleEmitters()
    while next(emitters) do
        local key, record = next(emitters)
        removeEmitter(key, record)
    end
    hook.Remove("Think", HOOK_NAME)
end

hook.Add("ShutDown", HOOK_NAME, Visuals.ClearParticleEmitters)
