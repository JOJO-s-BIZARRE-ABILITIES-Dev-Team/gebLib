local function installDebrisWave(Visuals, Runtime, Surface, Config, Profile)
    local previous = gebLib._VisualsWaveState
    if previous then
        Runtime.Unregister(previous.scheduler)
        for index = 1, #previous.waves do previous.waves[index].Active = false end
    end

    local state = {waves = {}, scheduler = {}}
    gebLib._VisualsWaveState = state
    Visuals.ActiveDebrisWaves = nil

    local activeDebrisWaves = state.waves
    local waveScheduler = state.scheduler
    local surfaceMaterialAt = Surface.MaterialAt
    local profileClock = Profile and Profile.Now or SysTime or os.clock

local function profileWaves()
    if not Profile or not Profile.IsActive() then return end
    return Profile.Data().waves
end

local function recordDuration(stats, key, startedAt)
    if not stats then return 0 end
    return Profile.RecordDuration(stats, key, startedAt)
end

local DebrisWave = {}
DebrisWave.__index = DebrisWave

local function waveNumber(value, fallback, minimum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then value = fallback end
    if minimum then value = math.max(value, minimum) end
    return value
end

local function waveCallback(callback, wave, label, ...)
    if type(callback) ~= "function" then return true end
    local stats = profileWaves()
    local startedAt = stats and profileClock()
    if stats then stats.callbackCalls = stats.callbackCalls + 1 end
    local ok, result = Runtime.Invoke(
        wave,
        "Debris Wave " .. label,
        callback,
        function(current)
            if current.Active then current:Cancel() end
        end,
        wave,
        ...
    )
    if stats then recordDuration(stats, "callbackTime", startedAt) end
    return ok, result
end

local function removeActiveWave(wave)
    local index = wave.ActiveIndex
    if not index then return end

    local count = #activeDebrisWaves
    local last = activeDebrisWaves[count]
    activeDebrisWaves[count] = nil
    wave.ActiveIndex = nil

    if index < count then
        activeDebrisWaves[index] = last
        last.ActiveIndex = index
    end
end

local function finishDebrisWave(wave, cancelled)
    if not wave.Active then return end

    wave.Active = false
    removeActiveWave(wave)
    local stats = profileWaves()
    if stats then
        if cancelled then
            stats.cancelled = stats.cancelled + 1
        else
            stats.completed = stats.completed + 1
        end
    end
    if cancelled then
        waveCallback(wave.OnCancel, wave, "cancel callback")
    else
        waveCallback(wave.OnComplete, wave, "complete callback")
    end
end

local function waveModelPath(wave, step, physical, materialType)
    if type(wave.ModelPath) == "function" then
        local ok, path = waveCallback(
            wave.ModelPath,
            wave,
            "model callback",
            step,
            physical,
            materialType
        )
        return ok and path or nil
    end
    if type(wave.ModelPath) == "string" and wave.ModelPath ~= "" then return wave.ModelPath end
    return Visuals.GetImpactDebrisModel(materialType or wave.MaterialType)
end

local function waveAngle(config, wave, step)
    if type(config.angles) == "function" then
        local ok, angles = waveCallback(config.angles, wave, "angle callback", step)
        return ok and angles or angle_zero
    end
    return config.angles or AngleRand()
end

local function waveScale(config)
    local minimum = waveNumber(config.scaleMin, 1, 0)
    local maximum = waveNumber(config.scaleMax, minimum, minimum)
    return math.Rand(minimum, maximum)
end

local function impactTouchesWater(position, normal)
    if not util or not util.PointContents or not bit or not bit.band or not CONTENTS_WATER then return false end

    local surfaceNormal = normal or vector_up
    local contents = util.PointContents(position)
    if bit.band(contents, CONTENTS_WATER) ~= 0 then return true end

    contents = util.PointContents(position - surfaceNormal * 4)
    return bit.band(contents, CONTENTS_WATER) ~= 0
end

local function traceDebrisWaveFloor(wave, position, stats)
    local floor = wave.FloorConfig
    if not floor then return position, wave.Material, wave.MaterialType, wave.PhysicsMaterial end

    local trace = floor.Trace
    trace.Hit = false
    trace.HitSky = false
    trace.HitNoDraw = false
    trace.HitPos = nil
    trace.HitNormal = nil
    trace.HitTexture = nil
    trace.MatType = nil

    local traceData = floor.TraceData
    traceData.start = position + vector_up * floor.StartHeight
    traceData.endpos = position - vector_up * floor.Depth
    local traceStartedAt = stats and profileClock()
    util.TraceLine(traceData)
    if stats then recordDuration(stats, "floorTraceTime", traceStartedAt) end

    local normal = trace.HitNormal
    if not trace.Hit
        or not trace.HitPos
        or not normal
        or (floor.RejectSky and trace.HitSky)
        or (floor.RejectNoDraw and trace.HitNoDraw)
        or normal:Dot(vector_up) < floor.MinNormalZ
    then
        return nil, nil, nil, nil, trace
    end

    local waterCheckStartedAt = stats and profileClock()
    local traceMaterialType = trace.MatType
    if traceMaterialType ~= MAT_SLOSH and impactTouchesWater(trace.HitPos, normal) then
        traceMaterialType = MAT_SLOSH
    end
    if stats then recordDuration(stats, "waterCheckTime", waterCheckStartedAt) end
    local surfaceStartedAt = stats and profileClock()
    local sampledMaterial, materialType = surfaceMaterialAt(
        trace.HitPos,
        normal,
        trace.HitTexture,
        traceMaterialType,
        false
    )
    if stats then recordDuration(stats, "surfaceTime", surfaceStartedAt) end
    local surfaceColor
    if sampledMaterial == nil
        and wave.Material == nil
        and materialType ~= MAT_SLOSH
        and floor.ColorFallback
        and render
        and render.GetSurfaceColor
    then
        local colorStartedAt = stats and profileClock()
        local colorVector = render.GetSurfaceColor(traceData.start, traceData.endpos)
        if colorVector then
            surfaceColor = Color(
                math.Clamp(math.floor(colorVector.x * 255 + 0.5), 0, 255),
                math.Clamp(math.floor(colorVector.y * 255 + 0.5), 0, 255),
                math.Clamp(math.floor(colorVector.z * 255 + 0.5), 0, 255)
            )
        end
        if stats then recordDuration(stats, "colorTime", colorStartedAt) end
    end
    local material = sampledMaterial or wave.Material

    return trace.HitPos + normal * floor.Offset,
        material,
        materialType,
        Visuals.GetImpactPhysicsMaterial(materialType),
        trace,
        surfaceColor
end

local function finishWaveStepProfile(stats, startedAt, wave, spawnedBefore, skipped)
    if not stats then return end
    local elapsed = recordDuration(stats, "stepTime", startedAt)
    stats.maxStepTime = math.max(stats.maxStepTime, elapsed)
    stats.spawned = stats.spawned + wave.Spawned - spawnedBefore
    if skipped then stats.skipped = stats.skipped + 1 end
end

local function finishDebrisWaveStep(wave, step, position, floorTrace)
    local event = wave.Events and wave.Events[step]
    if not waveCallback(event, wave, "event " .. step, step) then return false end
    return waveCallback(wave.OnStep, wave, "step callback", step, position, floorTrace)
end

local function spawnDebrisWaveStep(wave, step)
    local stats = profileWaves()
    local stepStartedAt = stats and profileClock()
    local spawnedBefore = wave.Spawned
    if stats then stats.steps = stats.steps + 1 end

    local positionStartedAt = stats and profileClock()
    local lateral
    if wave.IntegerSpread then
        local spread = math.floor(wave.Spread)
        lateral = math.random(-spread, spread)
    else
        lateral = math.Rand(-wave.Spread, wave.Spread)
    end

    local projectedPosition = wave.Origin
        + wave.Direction * (wave.DistanceStep * step)
        + wave.SpreadAxis * lateral
    if stats then recordDuration(stats, "positionTime", positionStartedAt) end

    local floorStartedAt = stats and profileClock()
    local position, material, materialType, physicsMaterial, floorTrace, surfaceColor =
        traceDebrisWaveFloor(wave, projectedPosition, stats)
    if stats then recordDuration(stats, "floorTime", floorStartedAt) end

    if not position then
        wave.Skipped = wave.Skipped + 1
        finishDebrisWaveStep(wave, step, nil, floorTrace)
        finishWaveStepProfile(stats, stepStartedAt, wave, spawnedBefore, true)
        return
    end

    if materialType == MAT_SLOSH then
        if wave.WaterConfig ~= false then
            local waterStartedAt = stats and profileClock()
            if stats then stats.waterSteps = stats.waterSteps + 1 end
            local waterConfig = wave.WaterConfig
            local waterStrength = waveNumber(waterConfig.strength, 22, 1)
            wave.Spawned = wave.Spawned + Visuals.CreateWaterDebris(
                position,
                floorTrace and floorTrace.HitNormal or vector_up,
                waterStrength,
                waterConfig
            )
            if stats then recordDuration(stats, "waterTime", waterStartedAt) end
        end
        finishDebrisWaveStep(wave, step, position, floorTrace)
        finishWaveStepProfile(stats, stepStartedAt, wave, spawnedBefore, false)
        return
    end

    local propConfig = wave.PropConfig
    if propConfig then
        if stats then stats.propRequests = stats.propRequests + 1 end
        local modelPathStartedAt = stats and profileClock()
        local propModelPath = waveModelPath(wave, step, true, materialType)
        if stats then recordDuration(stats, "modelPathTime", modelPathStartedAt) end
        local propCreateStartedAt = stats and profileClock()
        local prop = Visuals.CreateDebris(
            propModelPath,
            true,
            wave.Lifetime,
            wave.PreserveCount,
            material
        )
        if stats then recordDuration(stats, "propCreateTime", propCreateStartedAt) end
        if IsValid(prop) then
            if stats then stats.props = stats.props + 1 end
            local propSetupStartedAt = stats and profileClock()
            local transformStartedAt = stats and profileClock()
            if surfaceColor then prop:SetColor(surfaceColor) end
            prop:SetPos(position + (propConfig.offset or vector_origin))
            prop:SetAngles(waveAngle(propConfig, wave, step))
            prop:SetModelScale(waveScale(propConfig), 0)
            prop:SetCollisionGroup(propConfig.collisionGroup or COLLISION_GROUP_DEBRIS or 3)
            if stats then recordDuration(stats, "propTransformTime", transformStartedAt) end
            if propConfig.spawn ~= false then
                local spawnStartedAt = stats and profileClock()
                prop:Spawn()
                if stats then recordDuration(stats, "propSpawnTime", spawnStartedAt) end
            end
            if propConfig.activate ~= false then
                local activateStartedAt = stats and profileClock()
                prop:Activate()
                if stats then recordDuration(stats, "propActivateTime", activateStartedAt) end
            end

            local physicsStartedAt = stats and profileClock()
            local physics = prop:GetPhysicsObject()
            if IsValid(physics) then
                local velocity = propConfig.velocity or vector_origin
                local velocityJitter = waveNumber(propConfig.velocityJitter, 0, 0)
                if velocityJitter > 0 then velocity = velocity + VectorRand() * velocityJitter end
                physics:SetVelocity(velocity)

                local angularVelocity = propConfig.angularVelocity
                if isnumber(angularVelocity) then
                    physics:SetAngleVelocity(VectorRand() * angularVelocity)
                elseif angularVelocity then
                    physics:SetAngleVelocity(angularVelocity)
                end
                physics:SetMaterial(propConfig.physicsMaterial or physicsMaterial)
            end
            if stats then
                recordDuration(stats, "propPhysicsTime", physicsStartedAt)
                recordDuration(stats, "propSetupTime", propSetupStartedAt)
            end

            wave.Spawned = wave.Spawned + 1
            if not waveCallback(propConfig.setup, wave, "prop setup callback", prop, step) then
                finishWaveStepProfile(stats, stepStartedAt, wave, spawnedBefore, false)
                return
            end
        end
    end

    local modelConfig = wave.ModelConfig
    if modelConfig then
        if stats then stats.modelRequests = stats.modelRequests + 1 end
        local modelPathStartedAt = stats and profileClock()
        local modelPath = waveModelPath(wave, step, false, materialType)
        if stats then recordDuration(stats, "modelPathTime", modelPathStartedAt) end
        local modelCreateStartedAt = stats and profileClock()
        local model = Visuals.CreateDebris(
            modelPath,
            false,
            wave.Lifetime,
            wave.PreserveCount,
            material
        )
        if stats then recordDuration(stats, "modelCreateTime", modelCreateStartedAt) end
        if IsValid(model) then
            if stats then stats.models = stats.models + 1 end
            local modelSetupStartedAt = stats and profileClock()
            if surfaceColor then model:SetColor(surfaceColor) end
            model:SetPos(position + (modelConfig.offset or vector_origin))
            model:SetAngles(waveAngle(modelConfig, wave, step))
            model:SetModelScale(waveScale(modelConfig), 0)
            if stats then recordDuration(stats, "modelSetupTime", modelSetupStartedAt) end
            wave.Spawned = wave.Spawned + 1
            if not waveCallback(modelConfig.setup, wave, "model setup callback", model, step) then
                finishWaveStepProfile(stats, stepStartedAt, wave, spawnedBefore, false)
                return
            end
        end
    end

    finishDebrisWaveStep(wave, step, position, floorTrace)
    finishWaveStepProfile(stats, stepStartedAt, wave, spawnedBefore, false)
end

local function processDebrisWaves()
    local stats = profileWaves()
    local startedAt = stats and profileClock()
    if stats then stats.schedulerCalls = stats.schedulerCalls + 1 end
    local now = CurTime()
    local activeIndex = #activeDebrisWaves

    while activeIndex >= 1 do
        local wave = activeDebrisWaves[activeIndex]
        if not wave.Active then
            removeActiveWave(wave)
        elseif not wave.PausedAt and now >= wave.StartAt then
            if not wave.Started then
                wave.Started = true
                waveCallback(wave.OnStart, wave, "start callback")
            end

            if wave.Active then
                local dueStep = wave.Count
                if wave.Interval > 0 then
                    dueStep = math.min(math.floor((now - wave.StartAt) / wave.Interval) + 1, wave.Count)
                end

                local processed = 0
                while wave.Active and wave.NextStep <= dueStep and processed < wave.MaxStepsPerFrame do
                    local step = wave.NextStep
                    wave.NextStep = step + 1
                    spawnDebrisWaveStep(wave, step)
                    processed = processed + 1
                end

                if wave.Active and wave.NextStep > wave.Count then finishDebrisWave(wave, false) end
            end
        end

        activeIndex = activeIndex - 1
    end

    if stats then recordDuration(stats, "schedulerTime", startedAt) end
    return #activeDebrisWaves > 0
end

local function failWaveScheduler()
    for index = #activeDebrisWaves, 1, -1 do
        finishDebrisWave(activeDebrisWaves[index], true)
    end
end

function DebrisWave:IsActive()
    return self.Active == true
end

function DebrisWave:GetProgress()
    if self.Count == 0 then return 1 end
    return math.Clamp((self.NextStep - 1) / self.Count, 0, 1)
end

function DebrisWave:GetSpawnedCount()
    return self.Spawned
end

function DebrisWave:GetSkippedCount()
    return self.Skipped
end

function DebrisWave:Pause()
    if self.Active and not self.PausedAt then self.PausedAt = CurTime() end
    return self
end

function DebrisWave:Resume()
    if self.Active and self.PausedAt then
        self.StartAt = self.StartAt + CurTime() - self.PausedAt
        self.PausedAt = nil
    end
    return self
end

function DebrisWave:Cancel()
    finishDebrisWave(self, true)
end

function Visuals.CreateDebrisWave(options)
    local stats = profileWaves()
    local planStartedAt = stats and profileClock()
    local plan = Config.Wave(options)
    if stats then recordDuration(stats, "planTime", planStartedAt) end
    if not plan then return end

    if stats then
        stats.created = stats.created + 1
        stats.requestedSteps = stats.requestedSteps + plan.Count
    end

    local wave = setmetatable(plan, DebrisWave)
    wave.ActiveIndex = #activeDebrisWaves + 1
    activeDebrisWaves[wave.ActiveIndex] = wave

    Runtime.Register(
        waveScheduler,
        "Debris Wave scheduler",
        processDebrisWaves,
        failWaveScheduler,
        failWaveScheduler
    )
    return wave
end

    return state
end

return installDebrisWave
