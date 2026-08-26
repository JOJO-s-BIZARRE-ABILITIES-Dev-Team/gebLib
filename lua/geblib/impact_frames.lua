if SERVER then return end

-- Reusable impact-frame interface. Addons register their own authored
-- sequences and presets before playing them:
-- gebLib.ImpactFrames.Play("addon.heavy", {
--     AnchorPosition = hitPos,
--     WorldDirection = punchDirection,
--     SubjectEntity = attacker,
--     TargetEntity = victim
-- })

gebLib.ImpactFrames = gebLib.ImpactFrames or {}

local impactFrames = gebLib.ImpactFrames
local activeFrames = {}
local nextFrameId = 0
local postHookName = "gebLib.ImpactFrames.PostProcess"
local overlayHookName = "gebLib.ImpactFrames.Overlay"
local paleBlue = Color(224, 244, 250)
local blueInk = Color(10, 29, 43)
local impactFramesEnabled = CreateClientConVar(
    "geblib_impact_frames",
    "1",
    true,
    false,
    "Enable impact frames",
    0,
    1
)

local loadInternal = include or function(path)
    return assert(loadfile("lua/" .. path))()
end

local Renderer = loadInternal("geblib/impact_frames_render.lua")

impactFrames.Presets = impactFrames.Presets or {}
impactFrames.Sequences = impactFrames.Sequences or {}

local function CopyOptions(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function CopySequence(source)
    local result = {}
    for index = 1, #source do
        assert(istable(source[index]), "Impact-frame exposure must be a table")
        result[index] = CopyOptions(source[index])
    end
    return result
end

local function AddUniqueEntity(result, seen, entity)
    if not IsValid(entity) or entity == game.GetWorld() or seen[entity] then return end
    seen[entity] = true
    table.insert(result, entity)
end

local function BuildEntityList(primary, extras)
    local result = {}
    local seen = {}

    AddUniqueEntity(result, seen, primary)
    for _, entity in ipairs(extras or {}) do
        AddUniqueEntity(result, seen, entity)
    end

    return result
end

local function FinishInstance(instance)
    if instance.Finished then return end
    instance.Finished = true

    if instance.OnFinish then
        local ok, err = pcall(instance.OnFinish, instance.Id)
        if not ok then ErrorNoHalt("[gebLib] Impact-frame callback failed: " .. tostring(err) .. "\n") end
    end
end

local function RemoveExpiredFrames(now)
    local expired = {}
    for index = #activeFrames, 1, -1 do
        local instance = activeFrames[index]
        local durationElapsed = now - instance.StartTime >= instance.Duration
        local finalExposureRendered = instance.LastExposureIndex == #instance.Sequence
        local renderStalled = not instance.LastExposureTime or now - instance.LastExposureTime > 0.15
        if durationElapsed and (finalExposureRendered or renderStalled) then
            table.remove(activeFrames, index)
            table.insert(expired, instance)
        end
    end

    for _, instance in ipairs(expired) do FinishInstance(instance) end
end

local function GetDominantInstance(now)
    RemoveExpiredFrames(now)

    local dominant
    for _, instance in ipairs(activeFrames) do
        if not dominant
            or instance.Priority > dominant.Priority
            or instance.Priority == dominant.Priority and instance.StartTime > dominant.StartTime then
            dominant = instance
        end
    end

    return dominant
end

local function RemoveHooksIfIdle()
    if #activeFrames > 0 then return end
    hook.Remove("RenderScreenspaceEffects", postHookName)
    hook.Remove("DrawOverlay", overlayHookName)
end

local function DrawPostProcess()
    local now = SysTime()
    local instance = GetDominantInstance(now)
    if not instance then RemoveHooksIfIdle() return end
    Renderer.DrawPostProcess(instance, now)
end

local function DrawOverlay()
    local now = SysTime()
    local instance = GetDominantInstance(now)
    if not instance then RemoveHooksIfIdle() return end
    Renderer.DrawOverlay(instance, now)
end

function impactFrames.RegisterSequence(name, exposures)
    assert(isstring(name) and name ~= "", "Impact-frame sequence name must be a non-empty string")
    assert(istable(exposures) and #exposures > 0, "Impact-frame sequence must contain exposures")
    impactFrames.Sequences[name] = CopySequence(exposures)
end

function impactFrames.RegisterPreset(name, options)
    assert(isstring(name) and name ~= "", "Impact-frame preset name must be a non-empty string")
    assert(istable(options), "Impact-frame preset options must be a table")
    impactFrames.Presets[name] = CopyOptions(options)
end

function impactFrames.Play(presetName, overrides)
    if impactFramesEnabled and not impactFramesEnabled:GetBool() then return nil end

    if istable(presetName) then
        overrides = presetName
        presetName = "default"
    end

    presetName = presetName or "default"
    local preset = impactFrames.Presets[presetName]
    assert(preset, "Unknown impact-frame preset: " .. tostring(presetName))

    local options = CopyOptions(preset)
    for key, value in pairs(overrides or {}) do options[key] = value end

    local sequence = istable(options.Sequence) and options.Sequence or impactFrames.Sequences[options.Sequence or presetName]
    assert(istable(sequence) and #sequence > 0, "Impact-frame preset has no sequence: " .. tostring(presetName))
    sequence = CopySequence(sequence)

    local priority = tonumber(options.Priority) or 0
    local channel = options.Channel or "fullscreen_impact"
    if not options.Force then
        for _, active in ipairs(activeFrames) do
            if active.Channel == channel and active.Priority > priority then return nil end
        end
    end

    local replaced = {}
    for index = #activeFrames, 1, -1 do
        local active = activeFrames[index]
        if active.Channel == channel then
            table.remove(activeFrames, index)
            table.insert(replaced, active)
        end
    end

    local totalWeight = 0
    for _, exposure in ipairs(sequence) do
        totalWeight = totalWeight + math.max(0.01, tonumber(exposure.Weight) or 1)
    end

    nextFrameId = nextFrameId + 1
    local instance = {
        Id = nextFrameId,
        StartTime = SysTime(),
        Duration = math.max(0.05, tonumber(options.Duration) or 0.16),
        Intensity = math.Clamp(tonumber(options.Intensity) or 1, 0.25, 3),
        LineCount = math.Clamp(math.floor(tonumber(options.LineCount) or 72), 12, 180),
        FocusX = math.Clamp(tonumber(options.FocusX) or 0.5, -0.25, 1.25),
        FocusY = math.Clamp(tonumber(options.FocusY) or 0.5, -0.25, 1.25),
        AnchorEntity = options.AnchorEntity,
        AnchorBone = options.AnchorBone,
        AnchorOffset = options.AnchorOffset,
        AnchorPosition = options.AnchorPosition,
        WorldPosition = options.WorldPosition,
        WorldDirection = options.WorldDirection,
        Rotation = tonumber(options.Rotation) or 0,
        FrameJitter = math.Clamp(tonumber(options.FrameJitter) or 1, 0, 3),
        Paper = options.Paper or paleBlue,
        Ink = options.Ink or blueInk,
        OnFinish = options.OnFinish,
        Priority = priority,
        Channel = channel,
        Sequence = sequence,
        TotalWeight = totalWeight,
        AttackerEntities = BuildEntityList(options.SubjectEntity, options.SubjectEntities),
        VictimEntities = BuildEntityList(options.TargetEntity, options.TargetEntities),
        RandomState = math.floor(tonumber(options.Seed) or nextFrameId * 7919) % 4294967296
    }


    Renderer.Prepare(instance)
    table.insert(activeFrames, instance)
    hook.Add("RenderScreenspaceEffects", postHookName, DrawPostProcess)
    hook.Add("DrawOverlay", overlayHookName, DrawOverlay)
    for _, active in ipairs(replaced) do FinishInstance(active) end
    return instance.Id
end

function impactFrames.Stop(id)
    for index = #activeFrames, 1, -1 do
        if activeFrames[index].Id == id then
            local instance = table.remove(activeFrames, index)
            FinishInstance(instance)
            break
        end
    end

    RemoveHooksIfIdle()
end

function impactFrames.StopAll()
    local stopped = {}
    for index = #activeFrames, 1, -1 do
        table.insert(stopped, activeFrames[index])
        activeFrames[index] = nil
    end

    for _, instance in ipairs(stopped) do FinishInstance(instance) end

    RemoveHooksIfIdle()
end

function impactFrames.GetActiveCount()
    RemoveExpiredFrames(SysTime())
    RemoveHooksIfIdle()
    return #activeFrames
end


function impactFrames.IsShaderAvailable()
    return Renderer.IsShaderAvailable()
end
