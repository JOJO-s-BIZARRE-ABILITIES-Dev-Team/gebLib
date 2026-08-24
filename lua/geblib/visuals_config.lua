local function createVisualConfig(Surface)
    local Config = {}

    function Config.Number(value, fallback, minimum)
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            value = fallback
        end
        if minimum ~= nil then value = math.max(value, minimum) end
        return value
    end

    local function copyVector(value)
        if isvector and isvector(value) then return Vector(value.x, value.y, value.z) end
        if isangle and isangle(value) then return Angle(value.p, value.y, value.r) end
        if IsColor and IsColor(value) then return Color(value.r, value.g, value.b, value.a) end
        return value
    end

    function Config.Copy(source)
        local owned = {}
        if type(source) ~= "table" then return owned end
        for key, value in pairs(source) do owned[key] = copyVector(value) end
        return owned
    end

    function Config.Burst(materialPath, position, count, options, defaults)
        count = math.max(math.floor(tonumber(count) or 0), 0)
        if count == 0 or type(materialPath) ~= "string" or materialPath == "" then return end

        options = Config.Copy(options)
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
            gravity = options.gravity or defaults.gravity,
            collide = options.collide ~= false,
            bounce = tonumber(options.bounce) or 0.35,
            lighting = options.lighting == true,
            red = color.r or 255,
            green = color.g or 255,
            blue = color.b or 255,
            alpha = color.a or 255,
        }
    end

    function Config.Water(position, normal, strength, options)
        options = Config.Copy(options)
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

    function Config.Impact(position, normal, strength, options)
        return {
            options = Config.Copy(options),
            position = position or vector_origin,
            normal = normal or vector_up,
            strength = math.max(tonumber(strength) or 1, 1),
        }
    end

    function Config.Wave(options)
        if type(options) ~= "table" then return end
        options = Config.Copy(options)

        local count = math.floor(Config.Number(options.count, 1, 0))
        local propConfig
        if options.prop ~= false then propConfig = Config.Copy(options.prop) end
        local modelConfig
        if options.model ~= false then modelConfig = Config.Copy(options.model) end
        local waterConfig = options.water == false and false or Config.Copy(options.water)
        if count == 0 or (not propConfig and not modelConfig and waterConfig == false) then return end

        local direction = copyVector(options.direction) or Vector(1, 0, 0)
        if direction:LengthSqr() == 0 then direction = Vector(1, 0, 0) end
        direction = direction:GetNormalized()

        local spreadAxis = copyVector(options.spreadAxis)
        if not spreadAxis or spreadAxis:LengthSqr() == 0 then
            spreadAxis = direction:Cross(vector_up)
            if spreadAxis:LengthSqr() == 0 then spreadAxis = direction:Cross(Vector(0, 1, 0)) end
        end
        spreadAxis = spreadAxis:GetNormalized()

        local material = options.material
        local materialType = Surface.NormalizeMaterial(options.materialType or MAT_CONCRETE)
        local surface = type(options.surface) == "table" and Config.Copy(options.surface) or nil
        if surface then
            local sampledMaterial, sampledType = Surface.MaterialAt(
                surface.position or options.origin or vector_origin,
                surface.normal or vector_up,
                surface.hitTexture,
                surface.materialType or options.materialType
            )
            if material == nil then material = sampledMaterial end
            materialType = sampledType
        end

        local floorConfig
        if type(options.floor) == "table" then
            local floor = Config.Copy(options.floor)
            local floorTrace = {}
            local floorMask = floor.mask
            if floorMask == nil then
                floorMask = MASK_SOLID
                if floor.water ~= false and bit and bit.bor and MASK_WATER then
                    floorMask = bit.bor(floorMask, MASK_WATER)
                end
            end
            floorConfig = {
                StartHeight = Config.Number(floor.startHeight, 64, 0),
                Depth = Config.Number(floor.depth, 256, 0),
                Offset = Config.Number(floor.offset, 1),
                MinNormalZ = Config.Number(floor.minNormalZ, 0.2, -1),
                RejectSky = floor.rejectSky ~= false,
                RejectNoDraw = floor.rejectNoDraw ~= false,
                ColorFallback = floor.colorFallback ~= false,
                Trace = floorTrace,
                TraceData = {
                    mask = floorMask,
                    filter = floor.filter,
                    collisiongroup = floor.collisionGroup,
                    ignoreworld = floor.ignoreWorld,
                    output = floorTrace,
                },
            }
        end

        return {
            Active = true,
            Started = false,
            StartAt = CurTime() + Config.Number(options.delay, 0, 0),
            PausedAt = nil,
            NextStep = 1,
            Spawned = 0,
            Skipped = 0,
            Count = count,
            Interval = Config.Number(options.interval, 0.01, 0),
            MaxStepsPerFrame = math.floor(Config.Number(options.maxStepsPerFrame, 12, 1)),
            Origin = copyVector(options.origin) or vector_origin,
            Direction = direction,
            SpreadAxis = spreadAxis,
            DistanceStep = Config.Number(options.distanceStep, 35),
            Spread = Config.Number(options.spread, 0, 0),
            IntegerSpread = options.integerSpread == true,
            Lifetime = Config.Number(options.lifetime, 5, 0),
            PreserveCount = options.preserveCount == true,
            Material = material,
            MaterialType = materialType,
            PhysicsMaterial = Surface.PhysicsMaterial(materialType),
            FloorConfig = floorConfig,
            ModelPath = options.modelPath,
            PropConfig = propConfig,
            ModelConfig = modelConfig,
            WaterConfig = waterConfig,
            Events = Config.Copy(options.events),
            OnStart = options.onStart,
            OnStep = options.onStep,
            OnComplete = options.onComplete,
            OnCancel = options.onCancel,
        }
    end

    return Config
end

return createVisualConfig
