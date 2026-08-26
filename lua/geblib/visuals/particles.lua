local function installVisualParticles(Visuals, Profile)
    local DEFAULT_DEBRIS_GRAVITY = Vector(0, 0, -600)
    local DEFAULT_WATER_GRAVITY = Vector(0, 0, -850)
    local DEFAULT_WATER_COLOR = {r = 205, g = 235, b = 255, a = 235}
    local DEFAULT_WATER_MIST_COLOR = {r = 225, g = 240, b = 245, a = 145}
    local profileClock = Profile.Now
    local recordDuration = Profile.RecordDuration

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

    local function normalizeBurst(materialPath, position, count, options)
        count = math.max(math.floor(tonumber(count) or 0), 0)
        if count == 0 or type(materialPath) ~= "string" or materialPath == "" then return end

        options = copyOptions(options)
        local color = options.color or color_white
        return {
            materialPath = materialPath,
            position = position or vector_origin,
            count = count,
            lifetime = math.max(tonumber(options.lifetime) or 5, 0.01),
            size = math.max(tonumber(options.size) or 4, 0),
            endSize = math.max(tonumber(options.endSize) or tonumber(options.size) or 4, 0),
            speed = math.max(tonumber(options.speed) or 250, 0),
            spin = math.rad(tonumber(options.spin) or 180),
            velocity = options.velocity,
            direction = options.direction,
            spread = math.max(tonumber(options.spread) or 1, 0),
            gravity = options.gravity or DEFAULT_DEBRIS_GRAVITY,
            collide = options.collide ~= false,
            bounce = tonumber(options.bounce) or 0.35,
            lighting = options.lighting == true,
            red = color.r or 255,
            green = color.g or 255,
            blue = color.b or 255,
            alpha = color.a or 255,
        }
    end

    local function normalizeWater(position, normal, strength, options)
        options = copyOptions(options)
        position = position or vector_origin
        normal = normal or vector_up
        if normal:LengthSqr() == 0 then normal = vector_up end
        normal = normal:GetNormalized()
        strength = math.max(tonumber(strength) or 1, 1)

        local requestedParticles = tonumber(options.particleCount or options.count)
        local particleCount = options.particles == false and 0
            or math.max(math.floor(requestedParticles or strength * 1.25), 0)
        local sprayCount = math.floor(particleCount * 0.45)
        local dropletCount = math.floor(particleCount * 0.4)

        return {
            options = options,
            position = position,
            normal = normal,
            strength = strength,
            particleCount = particleCount,
            sprayCount = sprayCount,
            dropletCount = dropletCount,
            mistCount = particleCount - sprayCount - dropletCount,
            speed = math.Clamp(tonumber(options.speed) or strength * 2.2, 180, 1100),
            scale = math.Clamp(tonumber(options.scale) or strength / 90, 0.6, 8),
            particleScale = math.Clamp(tonumber(options.particleScale) or 1, 0.25, 32),
            color = options.color,
        }
    end

    local function prepareBurstPlan(materialPath, position, count, options)
        local profiling = Profile.IsActive()
        local planStartedAt = profiling and profileClock()
        local plan = normalizeBurst(materialPath, position, count, options)
        if not plan then return end

        local burstStats = profiling and Profile.Data().bursts
        if profiling then
            burstStats.calls = burstStats.calls + 1
            burstStats.requestedParticles = burstStats.requestedParticles + plan.count
            recordDuration(burstStats, "planTime", planStartedAt)
        end
        return plan, burstStats
    end

    local function emitBurstPlans(plans, emitterPosition, burstStats, profileStartedAt)
        if #plans == 0 then return 0 end

        local emitterStartedAt = burstStats and profileClock()
        local emitter = ParticleEmitter(emitterPosition)
        if burstStats then
            recordDuration(burstStats, "emitterTime", emitterStartedAt)
            burstStats.emitterGroups = burstStats.emitterGroups + 1
        end
        if not emitter then
            if burstStats then
                burstStats.failed = burstStats.failed + #plans
                local elapsed = recordDuration(burstStats, "totalTime", profileStartedAt)
                if elapsed > burstStats.maxTime then burstStats.maxTime = elapsed end
            end
            return 0
        end

        local emitted = 0

        for planIndex = 1, #plans do
            local plan = plans[planIndex]
            local layerStartedAt = plan.profileStats and profileClock()
            for index = 1, plan.count do
                local addStartedAt = burstStats and profileClock()
                local particle = emitter:Add(plan.materialPath, plan.position)
                if burstStats then recordDuration(burstStats, "addTime", addStartedAt) end
                if particle then
                    local velocityStartedAt = burstStats and profileClock()
                    local particleVelocity
                    if plan.direction then
                        particleVelocity = plan.direction * plan.speed
                            + VectorRand(-plan.speed * plan.spread, plan.speed * plan.spread)
                    else
                        particleVelocity = VectorRand(-plan.speed, plan.speed)
                    end
                    if plan.velocity then particleVelocity:Add(plan.velocity) end
                    if burstStats then recordDuration(burstStats, "velocityTime", velocityStartedAt) end

                    local setupStartedAt = burstStats and profileClock()
                    particle:SetDieTime(plan.lifetime)
                    particle:SetStartAlpha(plan.alpha)
                    particle:SetEndAlpha(0)
                    particle:SetStartSize(plan.size)
                    particle:SetEndSize(plan.endSize)
                    particle:SetColor(plan.red, plan.green, plan.blue)
                    particle:SetVelocity(particleVelocity)
                    particle:SetGravity(plan.gravity)
                    particle:SetCollide(plan.collide)
                    particle:SetLighting(plan.lighting)
                    particle:SetRoll(math.Rand(-math.pi, math.pi))
                    particle:SetRollDelta(math.Rand(-plan.spin, plan.spin))
                    if plan.collide then particle:SetBounce(plan.bounce) end
                    if burstStats then recordDuration(burstStats, "setupTime", setupStartedAt) end
                    emitted = emitted + 1
                elseif burstStats then
                    burstStats.failedParticles = burstStats.failedParticles + 1
                end
            end
            if plan.profileStats then
                recordDuration(plan.profileStats, plan.profileKey, layerStartedAt)
            end
        end

        local finishStartedAt = burstStats and profileClock()
        emitter:Finish()
        if burstStats then
            recordDuration(burstStats, "finishTime", finishStartedAt)
            burstStats.particles = burstStats.particles + emitted
            local elapsed = recordDuration(burstStats, "totalTime", profileStartedAt)
            if elapsed > burstStats.maxTime then burstStats.maxTime = elapsed end
        end
        return emitted
    end

    function Visuals.CreateDebrisBurst(materialPath, position, count, options)
        local profiling = Profile.IsActive()
        local profileStartedAt = profiling and profileClock()
        local plan, burstStats = prepareBurstPlan(materialPath, position, count, options)
        if not plan then return 0 end
        return emitBurstPlans({plan}, plan.position, burstStats, profileStartedAt)
    end
    local function waterEffect(name, position, normal, scale)
        if not EffectData or not util or not util.Effect then return false end

        local data = EffectData()
        data:SetOrigin(position)
        data:SetNormal(normal)
        data:SetScale(scale)
        util.Effect(name, data)
        return true
    end

    function Visuals.CreateWaterDebris(position, normal, strength, options)
        local profiling = Profile.IsActive()
        local waterStats = profiling and Profile.Data().water
        local startedAt = profiling and profileClock()
        local planStartedAt = profiling and profileClock()
        local plan = normalizeWater(position, normal, strength, options)
        if profiling then
            waterStats.calls = waterStats.calls + 1
            waterStats.requestedParticles = waterStats.requestedParticles + plan.particleCount
            recordDuration(waterStats, "planTime", planStartedAt)
        end
        options = plan.options
        position = plan.position
        normal = plan.normal
        strength = plan.strength

        local sprayCount = plan.sprayCount
        local dropletCount = plan.dropletCount
        local mistCount = plan.mistCount
        local speed = plan.speed
        local scale = plan.scale
        local particleScale = plan.particleScale
        local color = plan.color or DEFAULT_WATER_COLOR
        local directionStartedAt = profiling and profileClock()
        local direction = options.direction or normal
        if direction:LengthSqr() == 0 then direction = normal end
        direction = direction:GetNormalized()
        if profiling then recordDuration(waterStats, "directionTime", directionStartedAt) end
        local spawned = 0
        local burstPlans = {}
        local burstStats
        local burstStartedAt = profiling and profileClock()

        local function addWaterBurst(materialPath, particlePosition, count, burstOptions, profileKey)
            local layerStartedAt = profiling and profileClock()
            local burstPlan, currentStats = prepareBurstPlan(
                materialPath,
                particlePosition,
                count,
                burstOptions
            )
            if profiling then recordDuration(waterStats, profileKey, layerStartedAt) end
            if not burstPlan then return end
            burstPlan.profileStats = profiling and waterStats or nil
            burstPlan.profileKey = profileKey
            burstPlans[#burstPlans + 1] = burstPlan
            burstStats = currentStats or burstStats
        end

        if sprayCount > 0 then
            addWaterBurst(
                options.sprayMaterial or "effects/splash4",
                position + normal * 2,
                sprayCount,
                {
                    lifetime = math.Clamp(strength * 0.005, 0.45, 1.4),
                    size = math.Clamp(strength * 0.025, 3, 12) * particleScale,
                    endSize = math.Clamp(strength * 0.008, 1, 4) * particleScale,
                    speed = speed,
                    spin = 80,
                    velocity = options.velocity,
                    direction = direction,
                    spread = tonumber(options.spread) or 0.7,
                    gravity = options.gravity or DEFAULT_WATER_GRAVITY,
                    collide = false,
                    lighting = false,
                    color = color,
                },
                "sprayTime"
            )
        end

        if dropletCount > 0 then
            addWaterBurst(
                options.dropletMaterial or "particle/water/waterdrop_001a",
                position + normal * 3,
                dropletCount,
                {
                    lifetime = math.Clamp(strength * 0.007, 0.65, 1.8),
                    size = math.Clamp(strength * 0.009, 1.25, 4) * particleScale,
                    endSize = 0,
                    speed = speed * 1.2,
                    spin = 120,
                    velocity = options.velocity,
                    direction = direction,
                    spread = tonumber(options.dropletSpread) or 0.95,
                    gravity = options.gravity or DEFAULT_WATER_GRAVITY,
                    collide = false,
                    lighting = false,
                    color = color,
                },
                "dropletTime"
            )
        end

        if mistCount > 0 and options.mist ~= false and options.smoke ~= false then
            addWaterBurst(
                options.mistMaterial or "particle/particle_smokegrenade",
                position + normal * 5,
                mistCount,
                {
                    lifetime = math.Clamp(strength * 0.0025, 0.25, 0.65),
                    size = math.Clamp(strength * 0.025, 4, 12) * particleScale,
                    endSize = math.Clamp(strength * 0.055, 10, 26) * particleScale,
                    speed = math.Clamp(speed * 0.08, 20, 70),
                    spin = 45,
                    velocity = options.velocity,
                    direction = direction,
                    spread = tonumber(options.mistSpread) or 1.15,
                    gravity = Vector(0, 0, -60),
                    collide = false,
                    lighting = false,
                    color = options.mistColor or DEFAULT_WATER_MIST_COLOR,
                },
                "mistTime"
            )
        end

        if #burstPlans > 0 then
            spawned = spawned + emitBurstPlans(burstPlans, position, burstStats, burstStartedAt)
        end

        if options.effects ~= false then
            local effectsStartedAt = profiling and profileClock()
            local splashCount = math.floor(math.Clamp(tonumber(options.splashCount) or strength / 85 + 1.5, 1, 8))
            local radius = math.max(tonumber(options.radius) or strength * 0.12, 2)
            local tangent = normal:Cross(Vector(1, 0, 0))
            if tangent:LengthSqr() < 0.01 then tangent = normal:Cross(Vector(0, 1, 0)) end
            tangent:Normalize()
            local bitangent = normal:Cross(tangent)
            bitangent:Normalize()

            for index = 1, splashCount do
                local effectPosition = position
                    + tangent * math.Rand(-radius, radius)
                    + bitangent * math.Rand(-radius, radius)
                    + normal * 2
                if profiling then waterStats.effectCalls = waterStats.effectCalls + 1 end
                if waterEffect("watersplash", effectPosition, normal, scale * math.Rand(0.75, 1.25)) then
                    spawned = spawned + 1
                    if profiling then waterStats.effectSpawned = waterStats.effectSpawned + 1 end
                end
                if options.gunshotSplashes ~= false then
                    if profiling then waterStats.effectCalls = waterStats.effectCalls + 1 end
                    if waterEffect("gunshotsplash", effectPosition, normal, scale) then
                        spawned = spawned + 1
                        if profiling then waterStats.effectSpawned = waterStats.effectSpawned + 1 end
                    end
                end
            end

            local rippleCount = math.floor(math.Clamp(tonumber(options.rippleCount) or splashCount * 0.5, 1, 4))
            if options.ripples ~= false then
                for index = 1, rippleCount do
                    if profiling then waterStats.effectCalls = waterStats.effectCalls + 1 end
                    if waterEffect("waterripple", position + normal * 2, normal, scale * (1 + index * 0.35)) then
                        spawned = spawned + 1
                        if profiling then waterStats.effectSpawned = waterStats.effectSpawned + 1 end
                    end
                end
            end
            if profiling then recordDuration(waterStats, "effectsTime", effectsStartedAt) end
        end

        if profiling then
            waterStats.spawned = waterStats.spawned + spawned
            local elapsed = recordDuration(waterStats, "totalTime", startedAt)
            waterStats.maxTime = math.max(waterStats.maxTime, elapsed)
        end
        return spawned
    end
end

return installVisualParticles
