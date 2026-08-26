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

    local function numberRange(options, name, fallback, minimum)
        local value = tonumber(options[name]) or fallback
        local lower = tonumber(options[name .. "Min"])
        local upper = tonumber(options[name .. "Max"])
        if lower == nil and upper == nil then
            lower = value
            upper = value
        else
            lower = lower or upper
            upper = upper or lower
        end
        if minimum ~= nil then
            lower = math.max(lower, minimum)
            upper = math.max(upper, minimum)
        end
        if lower > upper then lower, upper = upper, lower end
        return lower, upper
    end

    local function randomRange(lower, upper)
        if lower == upper then return lower end
        return math.Rand(lower, upper)
    end

    local function normalizeBurst(materialPath, position, count, options)
        count = math.max(math.floor(tonumber(count) or 0), 0)
        if count == 0 or type(materialPath) ~= "string" or materialPath == "" then return end

        options = copyOptions(options)
        local color = options.color or color_white
        local lifetimeMin, lifetimeMax = numberRange(options, "lifetime", 5, 0.01)
        local sizeMin, sizeMax = numberRange(options, "size", 4, 0)
        local speedMin, speedMax = numberRange(options, "speed", 250, 0)
        local alphaMin, alphaMax = numberRange(options, "alpha", color.a or 255, 0)
        alphaMin = math.min(alphaMin, 255)
        alphaMax = math.min(alphaMax, 255)
        local endSizeTracksStart = options.endSize == nil
            and options.endSizeMin == nil
            and options.endSizeMax == nil
        local endSizeMin, endSizeMax
        if not endSizeTracksStart then
            endSizeMin, endSizeMax = numberRange(options, "endSize", sizeMin, 0)
        end
        local maximumActive = tonumber(options.maxActiveParticles)
        if maximumActive ~= nil then
            maximumActive = math.max(math.floor(maximumActive), 0)
        end
        return {
            materialPath = materialPath,
            position = position or vector_origin,
            count = count,
            requestedCount = count,
            lifetimeMin = lifetimeMin,
            lifetimeMax = lifetimeMax,
            sizeMin = sizeMin,
            sizeMax = sizeMax,
            endSizeMin = endSizeMin,
            endSizeMax = endSizeMax,
            endSizeTracksStart = endSizeTracksStart,
            speedMin = speedMin,
            speedMax = speedMax,
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
            alphaMin = alphaMin,
            alphaMax = alphaMax,
            airResistance = tonumber(options.airResistance),
            length = tonumber(options.length),
            endLength = tonumber(options.endLength),
            maxActiveParticles = maximumActive,
            emitter = options.emitter,
            use3D = options.use3D == true,
            collideChance = math.max(math.min(tonumber(options.collideChance) or 1, 1), 0),
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
            burstStats.requestedParticles = burstStats.requestedParticles + plan.requestedCount
            recordDuration(burstStats, "planTime", planStartedAt)
        end
        return plan, burstStats
    end

    local function emitterIsValid(emitter)
        if not emitter or not emitter.Add then return false end
        return not emitter.IsValid or emitter:IsValid()
    end

    local function emitBurstPlans(plans, emitterPosition, burstStats, profileStartedAt, suppliedEmitter)
        if #plans == 0 then return 0 end

        local emitterStartedAt = burstStats and profileClock()
        local emitter = suppliedEmitter
        local ownsEmitter = not emitterIsValid(emitter)
        if ownsEmitter then
            emitter = ParticleEmitter(emitterPosition, plans[1].use3D)
        elseif emitter.SetPos then
            emitter:SetPos(emitterPosition)
        end
        if burstStats then
            recordDuration(burstStats, "emitterTime", emitterStartedAt)
            burstStats.emitterGroups = burstStats.emitterGroups + 1
        end
        if not emitterIsValid(emitter) then
            if burstStats then
                burstStats.failed = burstStats.failed + #plans
                local elapsed = recordDuration(burstStats, "totalTime", profileStartedAt)
                if elapsed > burstStats.maxTime then burstStats.maxTime = elapsed end
            end
            return 0
        end

        local emitted = 0
        local startingActive = emitter.GetNumActiveParticles
            and emitter:GetNumActiveParticles()
            or 0

        for planIndex = 1, #plans do
            local plan = plans[planIndex]
            local layerStartedAt = plan.profileStats and profileClock()
            local count = plan.count
            if plan.maxActiveParticles ~= nil then
                local active = emitter.GetNumActiveParticles
                    and emitter:GetNumActiveParticles()
                    or startingActive + emitted
                count = math.min(count, math.max(plan.maxActiveParticles - active, 0))
                if burstStats then
                    burstStats.cappedParticles = burstStats.cappedParticles + plan.count - count
                end
            end
            for index = 1, count do
                local addStartedAt = burstStats and profileClock()
                local particle = emitter:Add(plan.materialPath, plan.position)
                if burstStats then recordDuration(burstStats, "addTime", addStartedAt) end
                if particle then
                    local velocityStartedAt = burstStats and profileClock()
                    local speed = randomRange(plan.speedMin, plan.speedMax)
                    local particleVelocity
                    if plan.direction then
                        particleVelocity = plan.direction * speed
                            + VectorRand(-speed * plan.spread, speed * plan.spread)
                    else
                        particleVelocity = VectorRand(-speed, speed)
                    end
                    if plan.velocity then particleVelocity:Add(plan.velocity) end
                    if burstStats then recordDuration(burstStats, "velocityTime", velocityStartedAt) end

                    local setupStartedAt = burstStats and profileClock()
                    local size = randomRange(plan.sizeMin, plan.sizeMax)
                    local endSize = plan.endSizeTracksStart
                        and size
                        or randomRange(plan.endSizeMin, plan.endSizeMax)
                    particle:SetDieTime(randomRange(plan.lifetimeMin, plan.lifetimeMax))
                    particle:SetStartAlpha(randomRange(plan.alphaMin, plan.alphaMax))
                    particle:SetEndAlpha(0)
                    particle:SetStartSize(size)
                    particle:SetEndSize(endSize)
                    particle:SetColor(plan.red, plan.green, plan.blue)
                    particle:SetVelocity(particleVelocity)
                    particle:SetGravity(plan.gravity)
                    local collides = plan.collide
                        and (plan.collideChance >= 1 or math.Rand(0, 1) < plan.collideChance)
                    particle:SetCollide(collides)
                    particle:SetLighting(plan.lighting)
                    particle:SetRoll(math.Rand(-math.pi, math.pi))
                    particle:SetRollDelta(math.Rand(-plan.spin, plan.spin))
                    if collides then particle:SetBounce(plan.bounce) end
                    if plan.airResistance ~= nil then
                        particle:SetAirResistance(math.max(plan.airResistance, 0))
                    end
                    if plan.length ~= nil then
                        local length = math.max(plan.length, 0)
                        particle:SetStartLength(length)
                        particle:SetEndLength(math.max(plan.endLength or length, 0))
                    end
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
        if ownsEmitter then emitter:Finish() end
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
        return emitBurstPlans({plan}, plan.position, burstStats, profileStartedAt, plan.emitter)
    end

    local function addShockwaveParticle(emitter, material, position, angles, lifetime, startRadius,
        radius, color, alpha, lighting)
        local particle = emitter:Add(material, position)
        if not particle then return false end

        particle:SetDieTime(lifetime)
        particle:SetStartAlpha(alpha)
        particle:SetEndAlpha(0)
        particle:SetStartSize(startRadius)
        particle:SetEndSize(radius)
        particle:SetColor(color.r or 255, color.g or 255, color.b or 255)
        particle:SetAngles(angles)
        particle:SetCollide(false)
        particle:SetLighting(lighting)
        return true
    end

    function Visuals.CreateShockwave(position, normal, radius, lifetime, options)
        options = type(options) == "table" and options or {}
        position = position or vector_origin
        normal = normal or vector_up
        if normal:LengthSqr() == 0 then normal = vector_up end
        normal = normal:GetNormalized()
        radius = math.max(tonumber(radius) or 0, 0)
        lifetime = math.max(tonumber(lifetime) or 0.4, 0.01)
        if radius == 0 then return 0 end

        local offset = tonumber(options.offset) or 5
        local particlePosition = position + normal * offset
        local emitter = ParticleEmitter(particlePosition, true)
        if not emitter then return 0 end

        local color = options.color or color_white
        local angles = normal:Angle()
        local startRadius = math.max(tonumber(options.startRadius) or 0, 0)
        local lighting = options.lighting == true
        local emitted = 0
        if addShockwaveParticle(
            emitter,
            options.material or "particle/particle_ring_wave_additive",
            particlePosition,
            angles,
            lifetime,
            startRadius,
            radius,
            color,
            tonumber(options.alpha) or color.a or 200,
            lighting
        ) then
            emitted = emitted + 1
        end

        if options.distortion ~= false and addShockwaveParticle(
            emitter,
            options.distortionMaterial or "particle/warp1_warp",
            particlePosition,
            angles,
            lifetime,
            startRadius,
            radius * math.max(tonumber(options.distortionScale) or 1, 0),
            color_white,
            tonumber(options.distortionAlpha) or 255,
            false
        ) then
            emitted = emitted + 1
        end

        emitter:Finish()
        return emitted
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
