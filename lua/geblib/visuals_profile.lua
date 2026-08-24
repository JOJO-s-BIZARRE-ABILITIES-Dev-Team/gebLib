local function createDebrisProfile(Visuals, getDebris)
    local Profile = {}
    local HOOK_NAME = "gebLib.Visuals.DebrisProfile"
    local CALLBACK_NAME = "gebLib.Visuals.DebrisProfile"
    local MAX_FRAME_TIME = 0.25
    local clock = SysTime or os.clock

    local function newData()
        return {
            startedAt = clock(),
            impacts = {
                calls = 0, spawned = 0,
                requestedModels = 0, requestedProps = 0, requestedParticles = 0,
                totalTime = 0, maxTime = 0, surfaceTime = 0, placementTime = 0,
                hullTraces = 0, lineTraces = 0, pointChecks = 0,
                hullRejected = 0, placementRejected = 0,
                modelCreateTime = 0, modelSetupTime = 0,
                propCreateTime = 0, propSetupTime = 0, propTransformTime = 0,
                propCollisionTime = 0, propSpawnTime = 0, propActivateTime = 0,
                physicsTime = 0, particleTime = 0, smokeTime = 0,
                abLegacyProps = 0, abLegacyTime = 0, abLegacyPhysics = 0,
                abOptimizedProps = 0, abOptimizedTime = 0, abOptimizedPhysics = 0,
            },
            creations = {
                models = 0, props = 0, failed = 0,
                totalTime = 0, maxTime = 0, peakActive = 0,
            },
            bursts = {
                calls = 0, particles = 0, failed = 0, totalTime = 0, maxTime = 0,
            },
            frames = {
                count = 0, totalTime = 0, minTime = math.huge, maxTime = 0,
                over33ms = 0, over50ms = 0,
                excludedPauses = 0, excludedPauseTime = 0, longestPause = 0,
                histogram = {}, buckets = {},
            },
        }
    end

    local data = newData()
    local active = false
    local compareInitialization = false
    local compareLegacyNext = true
    local lastFrameAt

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
        local frames = data.frames
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
            "requested: " .. impacts.requestedModels .. " models, " .. impacts.requestedProps
                .. " props, " .. impacts.requestedParticles .. " particles"
        )
        profilePrint(
            "impact averages: surface " .. milliseconds(impacts.surfaceTime / impactDivisor)
                .. ", placement " .. milliseconds(impacts.placementTime / impactDivisor)
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
        profilePrint(
            "placement: " .. impacts.hullTraces .. " hull traces, " .. impacts.lineTraces
                .. " line traces, " .. impacts.pointChecks .. " point checks, "
                .. impacts.hullRejected .. " hull rejects, " .. impacts.placementRejected
                .. " pre-creation rejects"
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
            "entity creation: " .. creations.models .. " models, " .. creations.props
                .. " props, " .. creations.failed .. " failures, "
                .. milliseconds(creations.totalTime / math.max(creationCount, 1))
                .. " average, " .. milliseconds(creations.maxTime) .. " maximum, "
                .. creations.peakActive .. " peak active"
        )
        profilePrint(
            "particle bursts: " .. bursts.calls .. " calls, " .. bursts.particles
                .. " particles, " .. bursts.failed .. " failures, "
                .. milliseconds(bursts.totalTime / math.max(bursts.calls, 1))
                .. " average, " .. milliseconds(bursts.maxTime) .. " maximum"
        )

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
