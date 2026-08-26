local function installImpactDebris(Visuals, Surface, Profile, Batch)
    local DEFAULT_DEBRIS_GRAVITY = Vector(0, 0, -600)
    local MAX_IMPACT_MODELS = 16
    local MAX_IMPACT_PROPS = 12
    local IMPACT_HULL_MINS = Vector(-15, -15, -15)
    local IMPACT_HULL_MAXS = Vector(15, 15, 15)
    local profileClock = Profile.Now
    local recordDuration = Profile.RecordDuration
    local finishImpactProfile = Profile.FinishImpact

    local impactHull = {}
    local impactHullData = {
        mask = MASK_SOLID,
        mins = IMPACT_HULL_MINS,
        maxs = IMPACT_HULL_MAXS,
        output = impactHull,
    }
    local impactModelTrace = {}
    local impactModelTraceData = {
        mask = MASK_VISIBLE,
        output = impactModelTrace,
    }

    local function copyValue(value)
        if isvector and isvector(value) then return Vector(value.x, value.y, value.z) end
        if isangle and isangle(value) then return Angle(value.p, value.y, value.r) end
        if IsColor and IsColor(value) then return Color(value.r, value.g, value.b, value.a) end
        return value
    end

    local function copyOptions(source)
        local owned = {}
        if type(source) ~= "table" then return owned end
        for key, value in pairs(source) do owned[key] = copyValue(value) end
        return owned
    end

    local function normalizeImpact(position, normal, strength, options)
        return {
            options = copyOptions(options),
            position = position or vector_origin,
            normal = normal or vector_up,
            strength = math.max(tonumber(strength) or 1, 1),
        }
    end

    local normalizeImpactMaterial = Surface.NormalizeMaterial
    local impactModels = Surface.Models
    local impactPhysicsMaterial = Surface.PhysicsMaterial
    local impactColor = Surface.Color
    local surfaceMaterialAt = Surface.MaterialAt
    local impactTouchesWater = Surface.TouchesWater

    function Visuals.GetDebrisSurfaceMaterial(position, normal, hitTexture, materialType)
        return Surface.MaterialAt(position or vector_origin, normal or vector_up, hitTexture, materialType)
    end

    function Visuals.GetImpactDebrisModel(materialType)
        return Surface.Model(materialType)
    end

    function Visuals.GetImpactPhysicsMaterial(materialType)
        return Surface.PhysicsMaterial(Surface.NormalizeMaterial(materialType or MAT_CONCRETE))
    end

    local function configureImpactModel(entity, position, angles, scale, material, shadows, stats, physical)
        local startedAt = stats and profileClock()
        entity:SetPos(position)
        if stats then recordDuration(stats, physical and "propPositionTime" or "modelPositionTime", startedAt) end

        startedAt = stats and profileClock()
        entity:SetAngles(angles)
        if stats then recordDuration(stats, physical and "propAngleTime" or "modelAngleTime", startedAt) end

        if scale then
            startedAt = stats and profileClock()
            entity:SetModelScale(scale, 0)
            if stats then recordDuration(stats, physical and "propScaleTime" or "modelScaleTime", startedAt) end
        end
        if material then
            startedAt = stats and profileClock()
            entity:SetMaterial(material)
            if stats then recordDuration(stats, physical and "propMaterialTime" or "modelMaterialTime", startedAt) end
        end
        if not shadows then
            startedAt = stats and profileClock()
            entity:DestroyShadow()
            entity:DrawShadow(false)
            if stats then recordDuration(stats, physical and "propShadowTime" or "modelShadowTime", startedAt) end
        end
    end
    function Visuals.CreateImpactDebris(position, normal, strength, options)
        local profiling = Profile.IsActive()
        local impactStartedAt
        local impactStats
        if profiling then
            impactStartedAt = profileClock()
            impactStats = Profile.Data().impacts
            impactStats.calls = impactStats.calls + 1
        end

        local planStartedAt = profiling and profileClock()
        local plan = normalizeImpact(position, normal, strength, options)
        if profiling then recordDuration(impactStats, "planTime", planStartedAt) end
        options = plan.options
        position = plan.position
        normal = plan.normal
        strength = plan.strength

        local waterCheckStartedAt = profiling and profileClock()
        local requestedMaterial = options.material
        if requestedMaterial == nil and options.detectWater ~= false and impactTouchesWater(position, normal) then
            requestedMaterial = MAT_SLOSH
        end
        if profiling then recordDuration(impactStats, "waterCheckTime", waterCheckStartedAt) end

        local materialStartedAt = profiling and profileClock()
        local materialType = normalizeImpactMaterial(requestedMaterial or MAT_CONCRETE)
        if profiling then recordDuration(impactStats, "materialTime", materialStartedAt) end
        if materialType == MAT_SLOSH then
            local spawned = Visuals.CreateWaterDebris(position, normal, strength, options)
            if profiling then
                impactStats.requestedParticles = impactStats.requestedParticles
                    + math.max(math.floor(tonumber(options.particleCount or options.count) or strength * 1.25), 0)
                finishImpactProfile(impactStats, impactStartedAt, spawned)
            end
            return spawned
        end
        if materialType == MAT_FLESH or materialType == MAT_EGGSHELL then
            if profiling then finishImpactProfile(impactStats, impactStartedAt, 0) end
            return 0
        end

        local countStartedAt = profiling and profileClock()
        local count = math.max(math.floor(tonumber(options.count) or strength * 0.5), 0)
        local modelLimit = math.max(math.floor(tonumber(options.modelLimit) or MAX_IMPACT_MODELS), 0)
        local propLimit = math.max(math.floor(tonumber(options.propLimit) or MAX_IMPACT_PROPS), 0)
        local requestedModels = tonumber(options.modelCount)
        local requestedProps = tonumber(options.propCount)
        local requestedParticles = tonumber(options.particleCount)
        local modelCount = options.craters == false and 0 or math.max(math.floor(requestedModels or math.min(count, modelLimit, math.max(math.floor(math.sqrt(count) * 1.5), 1))), 0)
        local propCount = options.props == false and 0 or math.max(math.floor(requestedProps or math.min(count - modelCount, propLimit, math.max(math.floor(math.sqrt(count)), 1))), 0)
        local particleCount = options.particles == false and 0 or math.max(math.floor(requestedParticles or count - modelCount - propCount), 0)
        if profiling then
            recordDuration(impactStats, "countTime", countStartedAt)
            impactStats.requestedModels = impactStats.requestedModels + modelCount
            impactStats.requestedProps = impactStats.requestedProps + propCount
            impactStats.requestedParticles = impactStats.requestedParticles + particleCount
        end
        if modelCount == 0 and propCount == 0 and particleCount == 0 and options.smoke == false then
            if profiling then finishImpactProfile(impactStats, impactStartedAt, 0) end
            return 0
        end

        local preparationStartedAt = profiling and profileClock()
        local models = impactModels(materialType)
        local modelScale = math.max(tonumber(options.modelScale) or 1, 0.01)
        local staticLifetime = math.max(tonumber(options.lifetime) or 5, 0)
        local propLifetime = math.max(tonumber(options.propLifetime) or staticLifetime, 0)
        local shadows = options.shadows ~= false
        local surfaceMaterial
        if options.surface ~= false then
            if profiling then recordDuration(impactStats, "preparationTime", preparationStartedAt) end
            local surfaceStartedAt = profiling and profileClock()
            surfaceMaterial = surfaceMaterialAt(position, normal, options.hitTexture, materialType)
            if profiling then
                recordDuration(impactStats, "surfaceTime", surfaceStartedAt)
                preparationStartedAt = profileClock()
            end
        end

        local sourceDirection = options.direction or vector_origin
        local impactDirection = normal * 2 + sourceDirection * 1.3
        local particleDirection = impactDirection
        if particleDirection:LengthSqr() == 0 then particleDirection = normal end
        particleDirection = particleDirection:GetNormalized()
        local normalAngle = normal:Angle()
        local loopCount = math.max(modelCount, propCount)
        local pathDivisor = math.max(tonumber(options.pathDivisor) or math.min(loopCount, strength), 1)
        local spreadRadius = math.max(tonumber(options.radius) or strength / 3, 1)
        local propSpeed = math.max(tonumber(options.propSpeed) or 1000, 0)
        local propVelocity = options.propVelocity or vector_origin
        local propScale = tonumber(options.propScale)
        local validatePlacement = options.validatePlacement ~= false
        local preserveCount = options.preserveCount == true
        local physicsMaterial = impactPhysicsMaterial(materialType)
        local spawned = 0
        local batchedModels = Batch.Enabled() and {} or nil
        local propBatchGroup = Batch.Enabled() and propCount > 0 and {} or nil
        if profiling then recordDuration(impactStats, "preparationTime", preparationStartedAt) end

        local loopStartedAt = profiling and profileClock()
        for index = 1, loopCount do
            local loopMathStartedAt = profiling and profileClock()
            local currentPosition = position + impactDirection * (index / pathDivisor)

            local randomDirection = VectorRand()
            randomDirection.x = randomDirection.x / 55
            randomDirection:Rotate(normalAngle)
            randomDirection:Normalize()
            if profiling then recordDuration(impactStats, "loopMathTime", loopMathStartedAt) end

            if index <= modelCount then
                local placementMathStartedAt = profiling and profileClock()
                local idealPosition = currentPosition + randomDirection * spreadRadius * math.Rand(0.1, 1)
                impactHullData.start = idealPosition
                impactHullData.endpos = idealPosition
                if profiling then recordDuration(impactStats, "placementMathTime", placementMathStartedAt) end
                if validatePlacement then
                    if profiling then
                        local placementStartedAt = profileClock()
                        util.TraceHull(impactHullData)
                        local elapsed = recordDuration(impactStats, "placementTime", placementStartedAt)
                        impactStats.hullTraceTime = impactStats.hullTraceTime + elapsed
                        impactStats.hullTraces = impactStats.hullTraces + 1
                    else
                        util.TraceHull(impactHullData)
                    end
                end

                if not validatePlacement or impactHull.Hit then
                    placementMathStartedAt = profiling and profileClock()
                    if options.flags == 2 then currentPosition = position end
                    local faceDirection = (idealPosition - (currentPosition - normal * 15)):GetNormalized()
                    local modelPosition = currentPosition - normal + randomDirection * (strength * 0.25) * math.Rand(0.5, 2)
                    if profiling then recordDuration(impactStats, "placementMathTime", placementMathStartedAt) end

                    local modelSelectStartedAt = profiling and profileClock()
                    local modelPath = models[math.random(1, #models)]
                    local scale = math.Rand(3, strength / 100) * modelScale
                    if profiling then recordDuration(impactStats, "modelSelectTime", modelSelectStartedAt) end
                    local keep = true

                    if validatePlacement then
                        impactModelTraceData.start = modelPosition + normal * 15
                        impactModelTraceData.endpos = modelPosition - normal * 15
                        if profiling then
                            local placementStartedAt = profileClock()
                            util.TraceLine(impactModelTraceData)
                            local elapsed = recordDuration(impactStats, "placementTime", placementStartedAt)
                            impactStats.lineTraceTime = impactStats.lineTraceTime + elapsed
                            impactStats.lineTraces = impactStats.lineTraces + 1
                        else
                            util.TraceLine(impactModelTraceData)
                        end
                        keep = impactModelTrace.Hit

                        for check = 1, 3 do
                            if not keep then break end
                            local contents
                            if profiling then
                                local placementStartedAt = profileClock()
                                contents = util.PointContents(modelPosition - normal)
                                local elapsed = recordDuration(impactStats, "placementTime", placementStartedAt)
                                impactStats.pointCheckTime = impactStats.pointCheckTime + elapsed
                                impactStats.pointChecks = impactStats.pointChecks + 1
                            else
                                contents = util.PointContents(modelPosition - normal)
                            end
                            if bit.band(contents, CONTENTS_SOLID) == CONTENTS_SOLID then
                                modelPosition = modelPosition + normal
                                if check == 3 then keep = false end
                            else
                                break
                            end
                        end
                    end

                    if keep then
                        local modelAngles = faceDirection:Angle()
                        if batchedModels then
                            batchedModels[#batchedModels + 1] = {
                                modelPath = modelPath,
                                position = modelPosition,
                                angles = modelAngles,
                                scale = scale,
                                material = surfaceMaterial,
                            }
                        else
                            local modelCreateStartedAt = profiling and profileClock()
                            local entity = Visuals.CreateDebris(modelPath, false, staticLifetime, preserveCount, nil, false)
                            if profiling then recordDuration(impactStats, "modelCreateTime", modelCreateStartedAt) end

                            if IsValid(entity) then
                                local modelSetupStartedAt = profiling and profileClock()
                                configureImpactModel(
                                    entity,
                                    modelPosition,
                                    modelAngles,
                                    scale,
                                    surfaceMaterial,
                                    shadows,
                                    profiling and impactStats or nil,
                                    false
                                )
                                if profiling then
                                    recordDuration(impactStats, "modelSetupTime", modelSetupStartedAt)
                                    impactStats.modelsConfigured = impactStats.modelsConfigured + 1
                                end
                                spawned = spawned + 1
                            end
                        end
                    elseif profiling then
                        impactStats.placementRejected = impactStats.placementRejected + 1
                    end
                elseif profiling then
                    impactStats.hullRejected = impactStats.hullRejected + 1
                end
            end

            if index <= propCount then
                local placementMathStartedAt = profiling and profileClock()
                local propPosition = options.propAtOrigin and position or currentPosition
                local propAngle = (propPosition - normal * 70 + sourceDirection):GetNormalized():Angle()
                if profiling then recordDuration(impactStats, "placementMathTime", placementMathStartedAt) end
                local legacyInitialization
                if profiling then legacyInitialization = Profile.TakeInitializationCohort() end
                local comparing = legacyInitialization ~= nil
                local comparisonStartedAt = comparing and profileClock()
                local modelSelectStartedAt = profiling and profileClock()
                local propModelPath = models[math.random(1, #models)]
                if profiling then recordDuration(impactStats, "modelSelectTime", modelSelectStartedAt) end
                local propCreateStartedAt = profiling and profileClock()
                local entity = Visuals.CreateDebris(propModelPath, true, propLifetime, preserveCount)
                if profiling then recordDuration(impactStats, "propCreateTime", propCreateStartedAt) end

                if IsValid(entity) then
                    local propSetupStartedAt = profiling and profileClock()
                    local transformStartedAt = profiling and profileClock()
                    configureImpactModel(
                        entity,
                        propPosition + normal * 24,
                        propAngle,
                        propScale,
                        surfaceMaterial,
                        shadows,
                        profiling and impactStats or nil,
                        true
                    )
                    if profiling then recordDuration(impactStats, "propTransformTime", transformStartedAt) end

                    local collisionStartedAt = profiling and profileClock()
                    entity:SetCollisionGroup(3)
                    if profiling then recordDuration(impactStats, "propCollisionTime", collisionStartedAt) end

                    if legacyInitialization then
                        local spawnStartedAt = profileClock()
                        entity:Spawn()
                        recordDuration(impactStats, "propSpawnTime", spawnStartedAt)
                    end

                    if legacyInitialization or propScale then
                        local activateStartedAt = profileClock()
                        entity:Activate()
                        if profiling then recordDuration(impactStats, "propActivateTime", activateStartedAt) end
                    end
                    if profiling then recordDuration(impactStats, "propSetupTime", propSetupStartedAt) end

                    local physicsStartedAt = profiling and profileClock()
                    local physicsLookupStartedAt = profiling and profileClock()
                    local physics = entity:GetPhysicsObject()
                    if profiling then recordDuration(impactStats, "physicsLookupTime", physicsLookupStartedAt) end
                    if IsValid(physics) then
                        local velocityStartedAt = profiling and profileClock()
                        physics:SetVelocity(propVelocity + VectorRand() * propSpeed)
                        if profiling then recordDuration(impactStats, "physicsVelocityTime", velocityStartedAt) end

                        local physicsMaterialStartedAt = profiling and profileClock()
                        physics:SetMaterial(physicsMaterial)
                        if profiling then recordDuration(impactStats, "physicsMaterialTime", physicsMaterialStartedAt) end
                    end
                    if profiling then
                        recordDuration(impactStats, "physicsTime", physicsStartedAt)
                        impactStats.propsConfigured = impactStats.propsConfigured + 1
                        if IsValid(physics) then impactStats.physicsReady = impactStats.physicsReady + 1 end
                    end

                    if comparing then
                        local comparisonTime = profileClock() - comparisonStartedAt
                        if legacyInitialization then
                            impactStats.abLegacyProps = impactStats.abLegacyProps + 1
                            impactStats.abLegacyTime = impactStats.abLegacyTime + comparisonTime
                            if IsValid(physics) then impactStats.abLegacyPhysics = impactStats.abLegacyPhysics + 1 end
                        else
                            impactStats.abOptimizedProps = impactStats.abOptimizedProps + 1
                            impactStats.abOptimizedTime = impactStats.abOptimizedTime + comparisonTime
                            if IsValid(physics) then impactStats.abOptimizedPhysics = impactStats.abOptimizedPhysics + 1 end
                        end
                    end
                    if Batch.Enabled() then
                        entity.gebLib_DebrisPromoteWhenSettled = true
                        entity.gebLib_DebrisBatchGroup = propBatchGroup
                        entity.gebLib_DebrisBatchShadows = shadows
                        entity.gebLib_DebrisBatchMaterial = surfaceMaterial
                    end
                    Visuals.RefreshDebrisPhysics(entity)
                    spawned = spawned + 1
                end
            end
        end
        if profiling then recordDuration(impactStats, "loopTime", loopStartedAt) end

        if batchedModels and #batchedModels > 0 then
            local batchCallOk, batchBuilt = pcall(Batch.Build, batchedModels, staticLifetime, shadows)
            if batchCallOk and batchBuilt then
                spawned = spawned + #batchedModels
            else
                local stats = batchStats()
                if stats then
                    if not batchCallOk then stats.failures = stats.failures + 1 end
                    stats.fallbackPieces = stats.fallbackPieces + #batchedModels
                end
                for index = 1, #batchedModels do
                    local piece = batchedModels[index]
                    local modelCreateStartedAt = profiling and profileClock()
                    local entity = Visuals.CreateDebris(piece.modelPath, false, staticLifetime, preserveCount, nil, false)
                    if profiling then recordDuration(impactStats, "modelCreateTime", modelCreateStartedAt) end
                    if IsValid(entity) then
                        local modelSetupStartedAt = profiling and profileClock()
                        configureImpactModel(
                            entity,
                            piece.position,
                            piece.angles,
                            piece.scale,
                            piece.material,
                            shadows,
                            profiling and impactStats or nil,
                            false
                        )
                        if profiling then
                            recordDuration(impactStats, "modelSetupTime", modelSetupStartedAt)
                            impactStats.modelsConfigured = impactStats.modelsConfigured + 1
                        end
                        spawned = spawned + 1
                    end
                end
            end
        end

        if particleCount > 0 then
            local color = impactColor(materialType)
            local fleck = materialType == MAT_METAL and "effects/fleck_tile1" or "effects/fleck_cement1"
            local particleStartedAt = profiling and profileClock()
            spawned = spawned + Visuals.CreateDebrisBurst(fleck, position + normal * 4, particleCount, {
                lifetime = math.Clamp(strength * 0.008, 1.25, 3),
                size = math.Clamp(strength * 0.02, 2, 6),
                endSize = 0,
                speed = math.Clamp(strength * 1.5, 180, 650),
                direction = particleDirection,
                spread = 0.75,
                gravity = DEFAULT_DEBRIS_GRAVITY,
                collide = false,
                lighting = false,
                color = color,
            })
            if profiling then recordDuration(impactStats, "particleTime", particleStartedAt) end
        end

        local smokeEffect
        if options.smoke ~= false then
            local smokeStartedAt = profiling and profileClock()
            local smokePosition = position + vector_up * 10 + normal * 50
            local smokeCreateStartedAt = profiling and profileClock()
            local smoke = CreateParticleSystemNoEntity("geblib_debris_smoke", smokePosition)
            if profiling then recordDuration(impactStats, "smokeCreateTime", smokeCreateStartedAt) end
            if smoke then
                local smokeSetupStartedAt = profiling and profileClock()
                smokeEffect = smoke
                local smokeCount = math.Clamp(tonumber(options.smokeCount) or count * 0.3, 1, 96) * 0.01
                local color = options.smokeColor or impactColor(materialType)
                smoke:SetControlPoint(1, impactDirection)
                smoke:SetControlPoint(2, Vector(smokeCount, smokeCount, smokeCount))
                smoke:SetControlPoint(3, Vector(color.r / 255, color.g / 255, color.b / 255))
                smoke:SetControlPoint(4, smokePosition + VectorRand() * 50)
                smoke:SetControlPoint(5, smokePosition + impactDirection + VectorRand() * 50)
                if profiling then recordDuration(impactStats, "smokeSetupTime", smokeSetupStartedAt) end
            end
            if profiling then recordDuration(impactStats, "smokeTime", smokeStartedAt) end
        end

        if profiling then finishImpactProfile(impactStats, impactStartedAt, spawned) end
        return spawned, smokeEffect
    end

    function Visuals.CreateSurfaceCrater(position, normal, size, options)
        options = copyOptions(options)
        size = math.max(tonumber(size) or 140, 1)

        local count = math.Clamp(
            math.floor(tonumber(options.count) or size / 12),
            1,
            MAX_IMPACT_MODELS
        )
        options.count = count
        options.modelCount = count
        options.propCount = 0
        options.particleCount = 0
        options.craters = true
        options.props = false
        options.particles = false
        options.effects = false
        options.smoke = false
        options.radius = math.max(tonumber(options.radius) or size / 3, 1)
        options.modelScale = math.max(tonumber(options.modelScale) or 0.65, 0.01)

        return Visuals.CreateImpactDebris(position, normal, size, options)
    end
end

return installImpactDebris
