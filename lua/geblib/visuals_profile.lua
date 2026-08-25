local function createDebrisProfile(Visuals, getDebris)
    local Profile = {}
    local HOOK_NAME = "gebLib.Visuals.DebrisProfile"
    local CALLBACK_NAME = "gebLib.Visuals.DebrisProfile"
    local MAX_FRAME_TIME = 0.25
    local COMPOSITION_SAMPLE_INTERVAL = 0.25
    local clock = SysTime or os.clock

    local function newData()
        return {
            startedAt = clock(),
            impacts = {
                calls = 0, spawned = 0,
                requestedModels = 0, requestedProps = 0, requestedParticles = 0,
                totalTime = 0, maxTime = 0,
                planTime = 0, waterCheckTime = 0, materialTime = 0,
                countTime = 0, preparationTime = 0, surfaceTime = 0,
                loopTime = 0, loopMathTime = 0, placementMathTime = 0,
                placementTime = 0, hullTraceTime = 0, lineTraceTime = 0,
                pointCheckTime = 0,
                hullTraces = 0, lineTraces = 0, pointChecks = 0,
                hullRejected = 0, placementRejected = 0,
                modelsConfigured = 0, propsConfigured = 0, physicsReady = 0,
                modelSelectTime = 0, modelCreateTime = 0, modelSetupTime = 0,
                modelPositionTime = 0, modelAngleTime = 0, modelScaleTime = 0,
                modelMaterialTime = 0, modelShadowTime = 0,
                propCreateTime = 0, propSetupTime = 0, propTransformTime = 0,
                propPositionTime = 0, propAngleTime = 0, propScaleTime = 0,
                propMaterialTime = 0, propShadowTime = 0,
                propCollisionTime = 0, propSpawnTime = 0, propActivateTime = 0,
                physicsTime = 0, physicsLookupTime = 0,
                physicsVelocityTime = 0, physicsMaterialTime = 0,
                particleTime = 0, smokeTime = 0,
                smokeCreateTime = 0, smokeSetupTime = 0,
                abLegacyProps = 0, abLegacyTime = 0, abLegacyPhysics = 0,
                abOptimizedProps = 0, abOptimizedTime = 0, abOptimizedPhysics = 0,
            },
            creations = {
                requests = 0, models = 0, props = 0, failed = 0,
                totalTime = 0, maxTime = 0, factoryTime = 0,
                materialTime = 0, limitTime = 0, evictions = 0,
                lifetimeTime = 0, callbackTime = 0, growthTime = 0,
                heapTime = 0, scheduleTime = 0, peakActive = 0,
            },
            bursts = {
                calls = 0, requestedParticles = 0, particles = 0,
                failed = 0, failedParticles = 0,
                totalTime = 0, maxTime = 0, planTime = 0,
                emitterTime = 0, addTime = 0, velocityTime = 0,
                setupTime = 0, finishTime = 0,
            },
            water = {
                calls = 0, requestedParticles = 0, spawned = 0,
                totalTime = 0, maxTime = 0, planTime = 0,
                directionTime = 0, sprayTime = 0, dropletTime = 0,
                mistTime = 0, effectsTime = 0, effectCalls = 0,
                effectSpawned = 0,
            },
            waves = {
                created = 0, completed = 0, cancelled = 0,
                requestedSteps = 0, steps = 0, skipped = 0, spawned = 0,
                planTime = 0, schedulerCalls = 0, schedulerTime = 0,
                stepTime = 0, maxStepTime = 0, positionTime = 0,
                floorTime = 0, floorTraceTime = 0, waterCheckTime = 0,
                surfaceTime = 0, colorTime = 0,
                callbackCalls = 0, callbackTime = 0,
                modelPathTime = 0, waterSteps = 0, waterTime = 0,
                propRequests = 0, props = 0,
                propCreateTime = 0, propSetupTime = 0,
                propTransformTime = 0, propSpawnTime = 0,
                propActivateTime = 0, propPhysicsTime = 0,
                modelRequests = 0, models = 0,
                modelCreateTime = 0, modelSetupTime = 0,
            },
            lifecycle = {
                scheduleCalls = 0, scheduleTime = 0,
                timerCreates = 0, timerRemoves = 0,
                timerFires = 0, timerTime = 0,
                fadeTransitions = 0, expirations = 0, invalidDropped = 0,
                removeCallbacks = 0, removeTime = 0,
                manualRemovals = 0, clearCalls = 0, cleared = 0,
                fadeDrawCalls = 0, fadeDrawTime = 0, maxFadeDrawTime = 0,
            },
            frames = {
                count = 0, totalTime = 0, minTime = math.huge, maxTime = 0,
                over33ms = 0, over50ms = 0,
                excludedPauses = 0, excludedPauseTime = 0, longestPause = 0,
                histogram = {}, buckets = {},
            },
            composition = {
                samples = 0, scanTime = 0,
                totalActive = 0, totalModels = 0,
                totalPhysics = 0, totalAwake = 0,
                totalSleeping = 0, totalFading = 0,
                maxActive = 0, maxModels = 0,
                maxPhysics = 0, maxAwake = 0,
                maxSleeping = 0, maxFading = 0,
            },
        }
    end

    local data = newData()
    local active = false
    local compareInitialization = false
    local compareLegacyNext = true
    local lastFrameAt
    local nextCompositionSampleAt

    function Profile.Now()
        return clock()
    end

    function Profile.IsActive()
        return active
    end

    function Profile.Data()
        return data
    end

    function Profile.RecordDuration(stats, key, startedAt)
        local elapsed = clock() - startedAt
        stats[key] = stats[key] + elapsed
        return elapsed
    end

    function Profile.FinishImpact(stats, startedAt, spawned)
        local elapsed = clock() - startedAt
        stats.spawned = stats.spawned + spawned
        stats.totalTime = stats.totalTime + elapsed
        if elapsed > stats.maxTime then stats.maxTime = elapsed end
    end

    function Profile.TakeInitializationCohort()
        if not active or not compareInitialization then return nil end
        local legacy = compareLegacyNext
        compareLegacyNext = not compareLegacyNext
        return legacy
    end

    local function frameBucket(count)
        if count == 0 then return "0" end
        if count < 100 then return "1-99" end
        if count < 250 then return "100-249" end
        if count < 500 then return "250-499" end
        if count < 1000 then return "500-999" end
        return "1000+"
    end

    local function sampleComposition(now)
        if nextCompositionSampleAt and now < nextCompositionSampleAt then return end
        nextCompositionSampleAt = now + COMPOSITION_SAMPLE_INTERVAL

        local startedAt = clock()
        local debris = getDebris()
        local models, physicsCount, awake, sleeping, fading = 0, 0, 0, 0, 0

        for index = 1, #debris do
            local entity = debris[index]
            if IsValid(entity) then
                if entity.gebLib_DebrisFadePending == nil and entity.gebLib_DebrisExpiresAt then
                    fading = fading + 1
                end
                local physics = entity:GetPhysicsObject()
                if IsValid(physics) then
                    physicsCount = physicsCount + 1
                    if physics.IsAsleep and physics:IsAsleep() then
                        sleeping = sleeping + 1
                    else
                        awake = awake + 1
                    end
                else
                    models = models + 1
                end
            end
        end

        local composition = data.composition
        composition.samples = composition.samples + 1
        composition.scanTime = composition.scanTime + clock() - startedAt
        composition.totalActive = composition.totalActive + #debris
        composition.totalModels = composition.totalModels + models
        composition.totalPhysics = composition.totalPhysics + physicsCount
        composition.totalAwake = composition.totalAwake + awake
        composition.totalSleeping = composition.totalSleeping + sleeping
        composition.totalFading = composition.totalFading + fading
        composition.maxActive = math.max(composition.maxActive, #debris)
        composition.maxModels = math.max(composition.maxModels, models)
        composition.maxPhysics = math.max(composition.maxPhysics, physicsCount)
        composition.maxAwake = math.max(composition.maxAwake, awake)
        composition.maxSleeping = math.max(composition.maxSleeping, sleeping)
        composition.maxFading = math.max(composition.maxFading, fading)
    end

    local function sampleFrame()
        if system and system.HasFocus and not system.HasFocus() then
            lastFrameAt = nil
            return
        end

        local now = clock()
        if not lastFrameAt then
            lastFrameAt = now
            return
        end

        local elapsed = now - lastFrameAt
        lastFrameAt = now
        if elapsed <= 0 then return end

        sampleComposition(now)

        local frames = data.frames
        if elapsed > MAX_FRAME_TIME then
            frames.excludedPauses = frames.excludedPauses + 1
            frames.excludedPauseTime = frames.excludedPauseTime + elapsed
            frames.longestPause = math.max(frames.longestPause, elapsed)
            return
        end

        frames.count = frames.count + 1
        frames.totalTime = frames.totalTime + elapsed
        frames.minTime = math.min(frames.minTime, elapsed)
        frames.maxTime = math.max(frames.maxTime, elapsed)
        if elapsed >= 1 / 30 then frames.over33ms = frames.over33ms + 1 end
        if elapsed >= 0.05 then frames.over50ms = frames.over50ms + 1 end

        local bucketMs = math.min(math.max(math.floor(elapsed * 1000 + 0.5), 0), 250)
        frames.histogram[bucketMs] = (frames.histogram[bucketMs] or 0) + 1

        local bucketName = frameBucket(#getDebris())
        local bucket = frames.buckets[bucketName]
        if not bucket then
            bucket = {count = 0, totalTime = 0, maxTime = 0}
            frames.buckets[bucketName] = bucket
        end
        bucket.count = bucket.count + 1
        bucket.totalTime = bucket.totalTime + elapsed
        bucket.maxTime = math.max(bucket.maxTime, elapsed)
    end

    function Profile.SetActive(enabled)
        enabled = enabled == true
        if active == enabled then return end
        active = enabled
        lastFrameAt = nil
        nextCompositionSampleAt = nil

        if enabled then
            if hook and hook.Add then hook.Add("Think", HOOK_NAME, sampleFrame) end
            if gebLib.PrintDebug then gebLib.PrintDebug("debris profiler enabled") end
        else
            compareInitialization = false
            compareLegacyNext = true
            if hook and hook.Remove then hook.Remove("Think", HOOK_NAME) end
        end
    end

    local function profilePrint(message)
        print("[gebLib.Visuals] " .. message)
    end

    local function milliseconds(seconds)
        return string.format("%.3f ms", seconds * 1000)
    end

    local function percentileFrameTime(frames, percentile)
        if frames.count == 0 then return 0 end
        local target = math.ceil(frames.count * percentile)
        local seen = 0
        for value = 0, 250 do
            seen = seen + (frames.histogram[value] or 0)
            if seen >= target then return value / 1000 end
        end
        return frames.maxTime
    end

    function Profile.Reset()
        if not active then
            profilePrint("run geblib_developer_debugmode 1 before using the debris profiler")
            return false
        end
        data = newData()
        lastFrameAt = nil
        nextCompositionSampleAt = nil
        profilePrint("debris profile reset")
        return true
    end

    function Profile.Report()
        if not active then
            profilePrint("run geblib_developer_debugmode 1 before using the debris profiler")
            return false
        end

        local elapsed = math.max(clock() - data.startedAt, 0)
        local impacts = data.impacts
        local creations = data.creations
        local bursts = data.bursts
        local water = data.water
        local waves = data.waves
        local lifecycle = data.lifecycle
        local frames = data.frames
        local composition = data.composition
        local impactDivisor = math.max(impacts.calls, 1)
        local debris = getDebris()
        local activeModels, activePhysics, sleepingPhysics, fading = 0, 0, 0, 0

        for index = 1, #debris do
            local entity = debris[index]
            if IsValid(entity) then
                if entity.gebLib_DebrisFadePending == nil and entity.gebLib_DebrisExpiresAt then
                    fading = fading + 1
                end
                local physics = entity:GetPhysicsObject()
                if IsValid(physics) then
                    activePhysics = activePhysics + 1
                    if physics.IsAsleep and physics:IsAsleep() then sleepingPhysics = sleepingPhysics + 1 end
                else
                    activeModels = activeModels + 1
                end
            end
        end

        profilePrint("debris profile: " .. string.format("%.1f", elapsed) .. " seconds")
        profilePrint("timing note: parent totals include child measurements; compare leaf averages directly")
        profilePrint("timing note: fine instrumentation adds clock overhead during debris creation")
        profilePrint(
            "initialization path: "
                .. (compareInitialization and "alternating legacy/optimized A/B" or "optimized")
        )
        profilePrint(
            "active: " .. #debris .. " total, " .. activeModels .. " models, "
                .. activePhysics .. " physics (" .. sleepingPhysics .. " asleep), "
                .. fading .. " fading"
        )
        profilePrint(
            "impacts: " .. impacts.calls .. " calls, " .. impacts.spawned
                .. " objects/particles spawned, "
                .. milliseconds(impacts.totalTime / impactDivisor) .. " average, "
                .. milliseconds(impacts.maxTime) .. " maximum"
        )
        profilePrint(
            "impact preparation averages: plan " .. milliseconds(impacts.planTime / impactDivisor)
                .. ", water " .. milliseconds(impacts.waterCheckTime / impactDivisor)
                .. ", material " .. milliseconds(impacts.materialTime / impactDivisor)
                .. ", counts " .. milliseconds(impacts.countTime / impactDivisor)
                .. ", remaining setup " .. milliseconds(impacts.preparationTime / impactDivisor)
        )
        profilePrint(
            "requested: " .. impacts.requestedModels .. " models, " .. impacts.requestedProps
                .. " props, " .. impacts.requestedParticles .. " particles"
        )
        profilePrint(
            "impact averages: surface " .. milliseconds(impacts.surfaceTime / impactDivisor)
                .. ", placement " .. milliseconds(impacts.placementTime / impactDivisor)
                .. ", loop " .. milliseconds(impacts.loopTime / impactDivisor)
                .. ", loop math " .. milliseconds(impacts.loopMathTime / impactDivisor)
                .. ", placement math " .. milliseconds(impacts.placementMathTime / impactDivisor)
        )
        profilePrint(
            "impact model averages: select " .. milliseconds(impacts.modelSelectTime / impactDivisor)
                .. ", model create " .. milliseconds(impacts.modelCreateTime / impactDivisor)
                .. ", model setup " .. milliseconds(impacts.modelSetupTime / impactDivisor)
        )
        profilePrint(
            "impact averages: prop create " .. milliseconds(impacts.propCreateTime / impactDivisor)
                .. ", prop setup " .. milliseconds(impacts.propSetupTime / impactDivisor)
                .. ", physics " .. milliseconds(impacts.physicsTime / impactDivisor)
                .. ", particles " .. milliseconds(impacts.particleTime / impactDivisor)
                .. ", smoke " .. milliseconds(impacts.smokeTime / impactDivisor)
        )
        local modelDivisor = math.max(impacts.modelsConfigured, 1)
        local propDivisor = math.max(impacts.propsConfigured, 1)
        profilePrint(
            "model setup per model: position " .. milliseconds(impacts.modelPositionTime / modelDivisor)
                .. ", angles " .. milliseconds(impacts.modelAngleTime / modelDivisor)
                .. ", scale " .. milliseconds(impacts.modelScaleTime / modelDivisor)
                .. ", material " .. milliseconds(impacts.modelMaterialTime / modelDivisor)
                .. ", shadows " .. milliseconds(impacts.modelShadowTime / modelDivisor)
        )
        profilePrint(
            "prop setup per prop: position " .. milliseconds(impacts.propPositionTime / propDivisor)
                .. ", angles " .. milliseconds(impacts.propAngleTime / propDivisor)
                .. ", scale " .. milliseconds(impacts.propScaleTime / propDivisor)
                .. ", material " .. milliseconds(impacts.propMaterialTime / propDivisor)
                .. ", shadows " .. milliseconds(impacts.propShadowTime / propDivisor)
                .. ", collision " .. milliseconds(impacts.propCollisionTime / propDivisor)
        )
        profilePrint(
            "prop initialization per prop: Spawn " .. milliseconds(impacts.propSpawnTime / propDivisor)
                .. ", Activate " .. milliseconds(impacts.propActivateTime / propDivisor)
                .. ", physics lookup " .. milliseconds(impacts.physicsLookupTime / propDivisor)
                .. ", velocity " .. milliseconds(impacts.physicsVelocityTime / propDivisor)
                .. ", material " .. milliseconds(impacts.physicsMaterialTime / propDivisor)
                .. ", ready " .. impacts.physicsReady .. "/" .. impacts.propsConfigured
        )
        profilePrint(
            "placement: " .. impacts.hullTraces .. " hull traces, " .. impacts.lineTraces
                .. " line traces, " .. impacts.pointChecks .. " point checks, "
                .. impacts.hullRejected .. " hull rejects, " .. impacts.placementRejected
                .. " pre-creation rejects"
        )
        profilePrint(
            "placement per query: hull "
                .. milliseconds(impacts.hullTraceTime / math.max(impacts.hullTraces, 1))
                .. ", line " .. milliseconds(impacts.lineTraceTime / math.max(impacts.lineTraces, 1))
                .. ", point " .. milliseconds(impacts.pointCheckTime / math.max(impacts.pointChecks, 1))
        )
        profilePrint(
            "smoke averages: create " .. milliseconds(impacts.smokeCreateTime / impactDivisor)
                .. ", setup " .. milliseconds(impacts.smokeSetupTime / impactDivisor)
        )

        if impacts.abLegacyProps > 0 or impacts.abOptimizedProps > 0 then
            local legacyAverage = impacts.abLegacyTime / math.max(impacts.abLegacyProps, 1)
            local optimizedAverage = impacts.abOptimizedTime / math.max(impacts.abOptimizedProps, 1)
            profilePrint(
                "initialization A/B legacy: " .. impacts.abLegacyProps .. " props, "
                    .. milliseconds(legacyAverage) .. " each, " .. impacts.abLegacyPhysics
                    .. "/" .. impacts.abLegacyProps .. " physics ready"
            )
            profilePrint(
                "initialization A/B optimized: " .. impacts.abOptimizedProps .. " props, "
                    .. milliseconds(optimizedAverage) .. " each, " .. impacts.abOptimizedPhysics
                    .. "/" .. impacts.abOptimizedProps .. " physics ready"
            )
            profilePrint(
                "initialization A/B legacy minus optimized: "
                    .. milliseconds(legacyAverage - optimizedAverage) .. " per prop"
            )
        end

        local creationCount = creations.models + creations.props
        profilePrint(
            "entity requests: " .. creations.models .. " models, " .. creations.props
                .. " props, " .. creations.failed .. " failures, "
                .. milliseconds(creations.totalTime / math.max(creationCount, 1))
                .. " full-path average, " .. milliseconds(creations.maxTime) .. " maximum, "
                .. creations.peakActive .. " peak active"
        )
        local creationDivisor = math.max(creations.requests, 1)
        profilePrint(
            "entity request averages: factory " .. milliseconds(creations.factoryTime / creationDivisor)
                .. ", material " .. milliseconds(creations.materialTime / creationDivisor)
                .. ", limit " .. milliseconds(creations.limitTime / creationDivisor)
                .. ", lifetime " .. milliseconds(creations.lifetimeTime / creationDivisor)
                .. ", callback " .. milliseconds(creations.callbackTime / creationDivisor)
        )
        profilePrint(
            "entity request averages: growth " .. milliseconds(creations.growthTime / creationDivisor)
                .. ", heap " .. milliseconds(creations.heapTime / creationDivisor)
                .. ", scheduling " .. milliseconds(creations.scheduleTime / creationDivisor)
                .. ", " .. creations.evictions .. " limit evictions"
        )
        profilePrint(
            "particle bursts: " .. bursts.calls .. " calls, " .. bursts.particles
                .. "/" .. bursts.requestedParticles .. " particles, "
                .. bursts.failed .. " emitter failures, " .. bursts.failedParticles
                .. " particle failures, "
                .. milliseconds(bursts.totalTime / math.max(bursts.calls, 1))
                .. " average, " .. milliseconds(bursts.maxTime) .. " maximum"
        )
        local burstDivisor = math.max(bursts.calls, 1)
        local requestedParticleDivisor = math.max(bursts.requestedParticles, 1)
        local emittedParticleDivisor = math.max(bursts.particles, 1)
        profilePrint(
            "particle burst averages: plan " .. milliseconds(bursts.planTime / burstDivisor)
                .. ", emitter " .. milliseconds(bursts.emitterTime / burstDivisor)
                .. ", finish " .. milliseconds(bursts.finishTime / burstDivisor)
                .. "; per requested particle add " .. milliseconds(bursts.addTime / requestedParticleDivisor)
                .. ", per emitted velocity " .. milliseconds(bursts.velocityTime / emittedParticleDivisor)
                .. ", setup " .. milliseconds(bursts.setupTime / emittedParticleDivisor)
        )
        if water.calls > 0 then
            local waterDivisor = math.max(water.calls, 1)
            profilePrint(
                "water debris: " .. water.calls .. " calls, " .. water.spawned .. " spawned, "
                    .. water.requestedParticles .. " particles requested, "
                    .. milliseconds(water.totalTime / waterDivisor) .. " average, "
                    .. milliseconds(water.maxTime) .. " maximum"
            )
            profilePrint(
                "water averages: plan " .. milliseconds(water.planTime / waterDivisor)
                    .. ", direction " .. milliseconds(water.directionTime / waterDivisor)
                    .. ", spray " .. milliseconds(water.sprayTime / waterDivisor)
                    .. ", droplets " .. milliseconds(water.dropletTime / waterDivisor)
                    .. ", mist " .. milliseconds(water.mistTime / waterDivisor)
                    .. ", engine effects " .. milliseconds(water.effectsTime / waterDivisor)
                    .. " (" .. water.effectSpawned .. "/" .. water.effectCalls .. ")"
            )
        end
        if waves.created > 0 or waves.steps > 0 then
            local waveDivisor = math.max(waves.created, 1)
            local stepDivisor = math.max(waves.steps, 1)
            local modelPathDivisor = math.max(waves.propRequests + waves.modelRequests, 1)
            local propDivisor = math.max(waves.propRequests, 1)
            local modelDivisor = math.max(waves.modelRequests, 1)
            local waterStepDivisor = math.max(waves.waterSteps, 1)
            profilePrint(
                "debris waves: " .. waves.created .. " created, " .. waves.completed
                    .. " completed, " .. waves.cancelled .. " cancelled, "
                    .. waves.steps .. "/" .. waves.requestedSteps .. " steps, "
                    .. waves.skipped .. " skipped, " .. waves.spawned .. " spawned"
            )
            profilePrint(
                "wave averages: plan " .. milliseconds(waves.planTime / waveDivisor)
                    .. ", scheduler " .. milliseconds(waves.schedulerTime / math.max(waves.schedulerCalls, 1))
                    .. "; per step total " .. milliseconds(waves.stepTime / stepDivisor)
                    .. ", maximum " .. milliseconds(waves.maxStepTime)
            )
            profilePrint(
                "wave per step: position " .. milliseconds(waves.positionTime / stepDivisor)
                    .. ", floor " .. milliseconds(waves.floorTime / stepDivisor)
                    .. " (trace " .. milliseconds(waves.floorTraceTime / stepDivisor)
                    .. ", water " .. milliseconds(waves.waterCheckTime / stepDivisor)
                    .. ", surface " .. milliseconds(waves.surfaceTime / stepDivisor)
                    .. ", color " .. milliseconds(waves.colorTime / stepDivisor) .. ")"
            )
            profilePrint(
                "wave per step: model path " .. milliseconds(waves.modelPathTime / stepDivisor)
                    .. " per step, " .. milliseconds(waves.modelPathTime / modelPathDivisor)
                    .. " per lookup; water spawn " .. milliseconds(waves.waterTime / waterStepDivisor)
                    .. " per water step"
            )
            profilePrint(
                "wave props: " .. waves.props .. "/" .. waves.propRequests
                    .. ", per request create " .. milliseconds(waves.propCreateTime / propDivisor)
                    .. ", setup " .. milliseconds(waves.propSetupTime / propDivisor)
                    .. ", transform " .. milliseconds(waves.propTransformTime / propDivisor)
                    .. ", Spawn " .. milliseconds(waves.propSpawnTime / propDivisor)
                    .. ", Activate " .. milliseconds(waves.propActivateTime / propDivisor)
                    .. ", physics " .. milliseconds(waves.propPhysicsTime / propDivisor)
            )
            profilePrint(
                "wave models: " .. waves.models .. "/" .. waves.modelRequests
                    .. ", per request create " .. milliseconds(waves.modelCreateTime / modelDivisor)
                    .. ", setup " .. milliseconds(waves.modelSetupTime / modelDivisor)
                    .. "; callbacks " .. waves.callbackCalls .. ", "
                    .. milliseconds(waves.callbackTime / math.max(waves.callbackCalls, 1)) .. " each"
            )
        end
        profilePrint(
            "lifecycle: " .. lifecycle.scheduleCalls .. " schedules ("
                .. milliseconds(lifecycle.scheduleTime / math.max(lifecycle.scheduleCalls, 1))
                .. " each), " .. lifecycle.timerCreates .. " timer creates, "
                .. lifecycle.timerRemoves .. " timer removals"
        )
        profilePrint(
            "lifecycle events: " .. lifecycle.timerFires .. " timer fires ("
                .. milliseconds(lifecycle.timerTime / math.max(lifecycle.timerFires, 1))
                .. " each), " .. lifecycle.fadeTransitions .. " fades, "
                .. lifecycle.expirations .. " expirations, " .. lifecycle.invalidDropped
                .. " invalid drops, " .. lifecycle.removeCallbacks .. " removal callbacks"
        )
        profilePrint(
            "lifecycle removals: " .. lifecycle.manualRemovals .. " manual/limit removals, "
                .. lifecycle.clearCalls .. " clears (" .. lifecycle.cleared .. " entities), "
                .. milliseconds(lifecycle.removeTime / math.max(lifecycle.removeCallbacks, 1))
                .. " per removal callback"
        )
        profilePrint(
            "fade rendering: " .. lifecycle.fadeDrawCalls .. " draws, "
                .. milliseconds(lifecycle.fadeDrawTime / math.max(lifecycle.fadeDrawCalls, 1))
                .. " average, " .. milliseconds(lifecycle.maxFadeDrawTime) .. " maximum"
        )

        if composition.samples > 0 then
            local compositionDivisor = composition.samples
            profilePrint(
                "composition samples: " .. composition.samples .. ", averages "
                    .. string.format("%.1f", composition.totalActive / compositionDivisor) .. " active, "
                    .. string.format("%.1f", composition.totalModels / compositionDivisor) .. " models, "
                    .. string.format("%.1f", composition.totalPhysics / compositionDivisor) .. " physics ("
                    .. string.format("%.1f", composition.totalAwake / compositionDivisor) .. " awake, "
                    .. string.format("%.1f", composition.totalSleeping / compositionDivisor) .. " asleep), "
                    .. string.format("%.1f", composition.totalFading / compositionDivisor) .. " fading"
            )
            profilePrint(
                "composition peaks: " .. composition.maxActive .. " active, "
                    .. composition.maxModels .. " models, " .. composition.maxPhysics
                    .. " physics (" .. composition.maxAwake .. " awake, "
                    .. composition.maxSleeping .. " asleep), " .. composition.maxFading
                    .. " fading; scan " .. milliseconds(composition.scanTime / compositionDivisor)
                    .. " average"
            )
        end

        if frames.count == 0 then
            profilePrint("frames: no samples")
        else
            local averageFrameTime = frames.totalTime / frames.count
            local onePercentFrameTime = percentileFrameTime(frames, 0.99)
            local onePercentLow = onePercentFrameTime > 0 and 1 / onePercentFrameTime or 0
            profilePrint(
                "frames: " .. frames.count .. " samples, "
                    .. string.format("%.1f", 1 / averageFrameTime) .. " average FPS, "
                    .. string.format("%.1f", onePercentLow) .. " 1% low FPS, "
                    .. milliseconds(frames.maxTime) .. " longest, " .. frames.over33ms
                    .. " over 33 ms, " .. frames.over50ms .. " over 50 ms"
            )

            local order = {"0", "1-99", "100-249", "250-499", "500-999", "1000+"}
            for index = 1, #order do
                local name = order[index]
                local bucket = frames.buckets[name]
                if bucket and bucket.count > 0 then
                    profilePrint(
                        "  " .. name .. " active: " .. bucket.count .. " frames, "
                            .. string.format("%.1f", bucket.count / bucket.totalTime)
                            .. " average FPS, " .. milliseconds(bucket.maxTime) .. " longest"
                    )
                end
            end
        end

        if frames.excludedPauses > 0 then
            profilePrint(
                "excluded pauses: " .. frames.excludedPauses .. " frames over "
                    .. math.floor(MAX_FRAME_TIME * 1000) .. " ms, "
                    .. milliseconds(frames.excludedPauseTime) .. " total, "
                    .. milliseconds(frames.longestPause) .. " longest"
            )
        end
        return true
    end

    function Profile.SetInitializationComparison(enabled)
        if not active then
            profilePrint("run geblib_developer_debugmode 1 before using the debris profiler")
            return false
        end
        compareInitialization = enabled == true
        compareLegacyNext = true
        Profile.Reset()
        profilePrint("initialization A/B " .. (compareInitialization and "enabled" or "disabled"))
        return true
    end

    Visuals.ResetDebrisProfile = Profile.Reset
    Visuals.ReportDebrisProfile = Profile.Report
    Visuals.SetDebrisInitializationComparison = Profile.SetInitializationComparison
    Visuals.IsDebrisProfileActive = Profile.IsActive

    if hook and hook.Remove then hook.Remove("Think", HOOK_NAME) end
    if cvars and cvars.RemoveChangeCallback then
        cvars.RemoveChangeCallback("geblib_developer_debugmode", CALLBACK_NAME)
    end
    if cvars and cvars.AddChangeCallback then
        cvars.AddChangeCallback("geblib_developer_debugmode", function(_, _, value)
            local numeric = tonumber(value)
            Profile.SetActive(numeric and numeric ~= 0 or value == "true")
        end, CALLBACK_NAME)
    end
    if concommand and concommand.Add then
        concommand.Add("geblib_debris_profile_report", function() Profile.Report() end)
        concommand.Add("geblib_debris_profile_reset", function() Profile.Reset() end)
        concommand.Add("geblib_debris_profile_compare_init", function(_, _, arguments)
            local value = arguments and arguments[1]
            local numeric = tonumber(value)
            Profile.SetInitializationComparison(numeric and numeric ~= 0 or value == "true")
        end)
    end

    Profile.SetActive(gebLib.DebugMode and gebLib.DebugMode())
    return Profile
end

return createDebrisProfile
