gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

local DEBRIS_TIMER = "gebLib.Visuals.Debris"
local GROW_TIME = 0.25
local DEFAULT_DEBRIS_GRAVITY = Vector(0, 0, -600)
local MAX_IMPACT_MODELS = 16
local MAX_IMPACT_PROPS = 12
local IMPACT_HULL_MINS = Vector(-15, -15, -15)
local IMPACT_HULL_MAXS = Vector(15, 15, 15)

local ROCK_DEBRIS_MODELS = {
    "models/props_debris/physics_debris_rock1.mdl",
    "models/props_debris/physics_debris_rock2.mdl",
    "models/props_debris/physics_debris_rock3.mdl",
    "models/props_debris/physics_debris_rock4.mdl",
    "models/props_debris/physics_debris_rock5.mdl",
    "models/props_debris/physics_debris_rock6.mdl",
    "models/props_debris/physics_debris_rock7.mdl",
    "models/props_debris/physics_debris_rock8.mdl",
    "models/props_debris/physics_debris_rock9.mdl",
    "models/props_debris/physics_debris_rock10.mdl",
    "models/props_debris/physics_debris_rock11.mdl",
}

local METAL_DEBRIS_MODELS = {
    "models/props_debris/metal_panelshard01a.mdl",
    "models/props_debris/metal_panelshard01b.mdl",
    "models/props_debris/metal_panelshard01c.mdl",
    "models/props_debris/metal_panelshard01d.mdl",
}

local ANTLION_DEBRIS_MODELS = {
    "models/gibs/antlion_gib_medium_1.mdl",
    "models/gibs/antlion_gib_medium_2.mdl",
    "models/gibs/antlion_gib_medium_3.mdl",
    "models/gibs/antlion_gib_medium_3a.mdl",
    "models/gibs/antlion_gib_small_1.mdl",
    "models/gibs/antlion_gib_small_2.mdl",
    "models/gibs/antlion_gib_small_3.mdl",
}

local surfaceMaterials = {}
local impactTrace = {}
local impactTraceData = {
    mask = MASK_VISIBLE,
    output = impactTrace,
}
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

Visuals.RockDebrisModels = ROCK_DEBRIS_MODELS

timer.Remove(DEBRIS_TIMER)

if Visuals.ActiveDebris then
    local oldDebris = {}
    for key, value in pairs(Visuals.ActiveDebris) do
        local entity = isnumber(key) and value or key
        if IsValid(entity) then oldDebris[#oldDebris + 1] = entity end
    end
    for index = 1, #oldDebris do oldDebris[index]:Remove() end
end

Visuals.ActiveDebris = {}
Visuals.MaxDebris = Visuals.MaxDebris or 512
local debrisHeap = Visuals.ActiveDebris
local scheduledAt

local function eventAt(entity)
    return entity.gebLib_DebrisEventAt or math.huge
end

local function swap(left, right)
    local leftEntity = debrisHeap[left]
    local rightEntity = debrisHeap[right]
    debrisHeap[left] = rightEntity
    debrisHeap[right] = leftEntity
    rightEntity.gebLib_DebrisHeapIndex = left
    leftEntity.gebLib_DebrisHeapIndex = right
end

local function siftUp(index)
    while index > 1 do
        local parent = math.floor(index / 2)
        if eventAt(debrisHeap[parent]) <= eventAt(debrisHeap[index]) then return end
        swap(parent, index)
        index = parent
    end
end

local function siftDown(index)
    local count = #debrisHeap

    while true do
        local left = index * 2
        if left > count then return end

        local smallest = left
        local right = left + 1
        if right <= count and eventAt(debrisHeap[right]) < eventAt(debrisHeap[left]) then
            smallest = right
        end

        if eventAt(debrisHeap[index]) <= eventAt(debrisHeap[smallest]) then return end
        swap(index, smallest)
        index = smallest
    end
end

local function pushDebris(entity)
    local index = #debrisHeap + 1
    debrisHeap[index] = entity
    entity.gebLib_DebrisHeapIndex = index
    siftUp(index)
end

local function removeAt(index)
    local count = #debrisHeap
    local removed = debrisHeap[index]
    if not removed then return end

    local last = debrisHeap[count]
    debrisHeap[count] = nil
    removed.gebLib_DebrisHeapIndex = nil

    if index < count then
        debrisHeap[index] = last
        last.gebLib_DebrisHeapIndex = index

        local parent = math.floor(index / 2)
        if index > 1 and eventAt(last) < eventAt(debrisHeap[parent]) then
            siftUp(index)
        else
            siftDown(index)
        end
    end

    return removed
end

local drawDebris
local processDueDebris

local function scheduleNextEvent()
    local entity = debrisHeap[1]
    if not entity then
        timer.Remove(DEBRIS_TIMER)
        scheduledAt = nil
        return
    end

    local nextAt = eventAt(entity)
    if scheduledAt == nextAt then return end

    scheduledAt = nextAt
    timer.Create(DEBRIS_TIMER, math.max(nextAt - CurTime(), 0), 1, processDueDebris)
end

processDueDebris = function()
    scheduledAt = nil
    local now = CurTime()
    local entity = debrisHeap[1]

    while entity and (not IsValid(entity) or now >= eventAt(entity)) do
        if IsValid(entity) and entity.gebLib_DebrisFadePending then
            entity.gebLib_DebrisFadePending = nil
            entity.gebLib_DebrisEventAt = entity.gebLib_DebrisExpiresAt
            entity.RenderOverride = drawDebris
            siftDown(1)
        else
            entity = removeAt(1)
            if IsValid(entity) then
                entity.gebLib_DebrisEventAt = nil
                entity.gebLib_DebrisExpiresAt = nil
                entity.RenderOverride = nil
                entity:Remove()
            end
        end
        entity = debrisHeap[1]
    end

    scheduleNextEvent()
end

local function debrisRemoved(entity)
    local index = entity.gebLib_DebrisHeapIndex
    if not index then return end

    local wasFirst = index == 1
    removeAt(index)
    entity.gebLib_DebrisEventAt = nil
    entity.gebLib_DebrisExpiresAt = nil
    entity.gebLib_DebrisFadePending = nil
    if wasFirst then scheduleNextEvent() end
end

drawDebris = function(entity)
    local expiry = entity.gebLib_DebrisExpiresAt
    if not expiry then
        entity:DrawModel()
        return
    end

    local remaining = expiry - CurTime()
    if remaining <= 0 then return end
    if remaining >= 1 then
        entity:DrawModel()
        return
    end

    render.SetBlend(remaining)
    entity:DrawModel()
    render.SetBlend(1)
end

function Visuals.CreateDebrisBurst(materialPath, position, count, options)
    count = math.max(math.floor(tonumber(count) or 0), 0)
    if count == 0 or type(materialPath) ~= "string" or materialPath == "" then return 0 end

    options = type(options) == "table" and options or {}
    position = position or vector_origin

    local emitter = ParticleEmitter(position)
    if not emitter then return 0 end

    local lifetime = math.max(tonumber(options.lifetime) or 5, 0.01)
    local size = math.max(tonumber(options.size) or 4, 0)
    local endSize = math.max(tonumber(options.endSize) or size, 0)
    local speed = math.max(tonumber(options.speed) or 250, 0)
    local spin = math.rad(tonumber(options.spin) or 180)
    local velocity = options.velocity
    local direction = options.direction
    local spread = math.max(tonumber(options.spread) or 1, 0)
    local gravity = options.gravity or DEFAULT_DEBRIS_GRAVITY
    local color = options.color or color_white
    local collide = options.collide ~= false
    local bounce = tonumber(options.bounce) or 0.35
    local lighting = options.lighting == true
    local red, green, blue, alpha = color.r or 255, color.g or 255, color.b or 255, color.a or 255
    local emitted = 0

    for index = 1, count do
        local particle = emitter:Add(materialPath, position)
        if particle then
            local particleVelocity
            if direction then
                particleVelocity = direction * speed + VectorRand(-speed * spread, speed * spread)
            else
                particleVelocity = VectorRand(-speed, speed)
            end
            if velocity then particleVelocity:Add(velocity) end

            particle:SetDieTime(lifetime)
            particle:SetStartAlpha(alpha)
            particle:SetEndAlpha(0)
            particle:SetStartSize(size)
            particle:SetEndSize(endSize)
            particle:SetColor(red, green, blue)
            particle:SetVelocity(particleVelocity)
            particle:SetGravity(gravity)
            particle:SetCollide(collide)
            particle:SetLighting(lighting)
            particle:SetRoll(math.Rand(-math.pi, math.pi))
            particle:SetRollDelta(math.Rand(-spin, spin))
            if collide then particle:SetBounce(bounce) end
            emitted = emitted + 1
        end
    end

    emitter:Finish()
    return emitted
end

function Visuals.CreateDebris(modelPath, clientProp, lifetime, ignoreLimit)
    local limit = math.max(math.floor(tonumber(Visuals.MaxDebris) or 512), 0)
    if limit == 0 then return NULL end

    local entity
    if clientProp then
        entity = ents.CreateClientProp(modelPath)
    else
        entity = ClientsideModel(modelPath)
    end

    if not IsValid(entity) then return NULL end

    while not ignoreLimit and #debrisHeap >= limit do Visuals.RemoveDebris(debrisHeap[1]) end

    if not isnumber(lifetime) then lifetime = 10 end
    lifetime = math.max(lifetime, 0)

    local expiry = CurTime() + lifetime
    entity.gebLib_DebrisExpiresAt = expiry
    if lifetime > 1 then
        entity.gebLib_DebrisEventAt = expiry - 1
        entity.gebLib_DebrisFadePending = true
    else
        entity.gebLib_DebrisEventAt = expiry
        entity.RenderOverride = drawDebris
    end
    entity:CallOnRemove("gebLib.Visuals.Debris", debrisRemoved)

    if not clientProp then
        local desiredScale = entity:GetModelScale()
        entity:SetModelScale(0, 0)
        entity:SetModelScale(desiredScale, GROW_TIME)
    end

    local previousFirst = debrisHeap[1]
    pushDebris(entity)
    if debrisHeap[1] ~= previousFirst then scheduleNextEvent() end
    return entity
end

local function normalizeImpactMaterial(materialType)
    if materialType == MAT_TILE or materialType == MAT_DEFAULT then return MAT_CONCRETE end
    if materialType == MAT_GRASS then return MAT_DIRT end
    if materialType == MAT_BLOODYFLESH then return MAT_FLESH end
    if materialType == MAT_GRATE or materialType == MAT_COMPUTER then return MAT_METAL end
    return materialType
end

local function impactModels(materialType)
    if materialType == MAT_METAL then return METAL_DEBRIS_MODELS end
    if materialType == MAT_ANTLION then return ANTLION_DEBRIS_MODELS end
    return ROCK_DEBRIS_MODELS
end

local function impactPhysicsMaterial(materialType)
    if materialType == MAT_METAL then return "metal" end
    if materialType == MAT_ANTLION or materialType == MAT_FLESH then return "flesh" end
    if materialType == MAT_DIRT then return "dirt" end
    return "concrete"
end

local function impactColor(materialType)
    if materialType == MAT_DIRT then return {r = 104, g = 83, b = 58, a = 255} end
    if materialType == MAT_METAL then return {r = 150, g = 155, b = 160, a = 255} end
    if materialType == MAT_ANTLION or materialType == MAT_FLESH then
        return {r = 185, g = 145, b = 55, a = 255}
    end
    return {r = 145, g = 140, b = 130, a = 255}
end

local function validSurfaceTexture(path)
    if type(path) ~= "string" or path == "" then return false end
    local lowered = string.lower(path)
    if lowered == "**empty**" or lowered == "**displacement**" or lowered == "**studio**" then return false end
    return string.sub(lowered, 1, 5) ~= "tools"
end

local function surfaceMaterialAt(position, normal, hitTexture)
    if not validSurfaceTexture(hitTexture) then
        impactTraceData.start = position + normal * 24
        impactTraceData.endpos = position - normal * 96
        util.TraceLine(impactTraceData)
        hitTexture = impactTrace.HitTexture
    end

    if not validSurfaceTexture(hitTexture) then return end

    local cached = surfaceMaterials[hitTexture]
    if cached ~= nil then return cached or nil end

    local source = Material(hitTexture)
    local texture = source and source:GetTexture("$basetexture")
    local textureName = texture and texture:GetName()
    if not textureName or textureName == "" then
        surfaceMaterials[hitTexture] = false
        return
    end

    local name = "geblib_debris_surface_" .. util.CRC(textureName)
    CreateMaterial(name, "VertexLitGeneric", {
        ["$basetexture"] = textureName,
        ["$model"] = "1",
    })

    cached = "!" .. name
    surfaceMaterials[hitTexture] = cached
    return cached
end

local function configureImpactModel(entity, position, angles, scale, material, shadows)
    entity:SetPos(position)
    entity:SetAngles(angles)
    if scale then entity:SetModelScale(scale, 0) end
    if material then entity:SetMaterial(material) end
    if not shadows then
        entity:DestroyShadow()
        entity:DrawShadow(false)
    end
end

function Visuals.CreateImpactDebris(position, normal, strength, options)
    options = type(options) == "table" and options or {}
    position = position or vector_origin
    normal = normal or vector_up
    strength = math.max(tonumber(strength) or 1, 1)

    local materialType = normalizeImpactMaterial(options.material or MAT_CONCRETE)
    if materialType == MAT_FLESH or materialType == MAT_EGGSHELL then return 0 end

    local count = math.max(math.floor(tonumber(options.count) or strength * 0.5), 0)
    local modelLimit = math.max(math.floor(tonumber(options.modelLimit) or MAX_IMPACT_MODELS), 0)
    local propLimit = math.max(math.floor(tonumber(options.propLimit) or MAX_IMPACT_PROPS), 0)
    local requestedModels = tonumber(options.modelCount)
    local requestedProps = tonumber(options.propCount)
    local requestedParticles = tonumber(options.particleCount)
    local modelCount = options.craters == false and 0 or math.max(math.floor(requestedModels or math.min(count, modelLimit, math.max(math.floor(math.sqrt(count) * 1.5), 1))), 0)
    local propCount = options.props == false and 0 or math.max(math.floor(requestedProps or math.min(count - modelCount, propLimit, math.max(math.floor(math.sqrt(count)), 1))), 0)
    local particleCount = options.particles == false and 0 or math.max(math.floor(requestedParticles or count - modelCount - propCount), 0)
    if modelCount == 0 and propCount == 0 and particleCount == 0 and options.smoke == false then return 0 end

    local models = impactModels(materialType)
    local modelScale = math.max(tonumber(options.modelScale) or 1, 0.01)
    local staticLifetime = math.max(tonumber(options.lifetime) or 5, 0)
    local propLifetime = math.max(tonumber(options.propLifetime) or staticLifetime, 0)
    local shadows = options.shadows ~= false
    local surfaceMaterial
    if options.surface ~= false then
        surfaceMaterial = surfaceMaterialAt(position, normal, options.hitTexture)
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

    for index = 1, loopCount do
        local currentPosition = position + impactDirection * (index / pathDivisor)

        local randomDirection = VectorRand()
        randomDirection.x = randomDirection.x / 55
        randomDirection:Rotate(normalAngle)
        randomDirection:Normalize()

        if index <= modelCount then
            local idealPosition = currentPosition + randomDirection * spreadRadius * math.Rand(0.1, 1)
            impactHullData.start = idealPosition
            impactHullData.endpos = idealPosition
            if validatePlacement then util.TraceHull(impactHullData) end

            if not validatePlacement or impactHull.Hit then
                if options.flags == 2 then currentPosition = position end
                local faceDirection = (idealPosition - (currentPosition - normal * 15)):GetNormalized()
                local modelPosition = currentPosition - normal + randomDirection * (strength * 0.25) * math.Rand(0.5, 2)
                local entity = Visuals.CreateDebris(models[math.random(1, #models)], false, staticLifetime, preserveCount)

                if IsValid(entity) then
                    configureImpactModel(entity, modelPosition, faceDirection:Angle(), math.Rand(3, strength / 100) * modelScale, surfaceMaterial, shadows)
                    entity:Spawn()
                    entity:Activate()

                    local keep = true
                    if validatePlacement then
                        impactModelTraceData.start = modelPosition + normal * 15
                        impactModelTraceData.endpos = modelPosition - normal * 15
                        util.TraceLine(impactModelTraceData)
                        keep = impactModelTrace.Hit

                        for check = 1, 3 do
                            if not keep then break end
                            if bit.band(util.PointContents(entity:GetPos() - normal), CONTENTS_SOLID) == CONTENTS_SOLID then
                                entity:SetPos(entity:GetPos() + normal)
                                if check == 3 then keep = false end
                            else
                                break
                            end
                        end
                    end

                    if keep then
                        spawned = spawned + 1
                    else
                        Visuals.RemoveDebris(entity)
                    end
                end
            end
        end

        if index <= propCount then
            local propPosition = options.propAtOrigin and position or currentPosition
            local propAngle = (propPosition - normal * 70 + sourceDirection):GetNormalized():Angle()
            local entity = Visuals.CreateDebris(models[math.random(1, #models)], true, propLifetime, preserveCount)

            if IsValid(entity) then
                configureImpactModel(entity, propPosition + normal * 24, propAngle, propScale, surfaceMaterial, shadows)
                entity:SetCollisionGroup(3)
                entity:Spawn()
                entity:Activate()

                local physics = entity:GetPhysicsObject()
                if IsValid(physics) then
                    physics:SetVelocity(propVelocity + VectorRand() * propSpeed)
                    physics:SetMaterial(physicsMaterial)
                end
                spawned = spawned + 1
            end
        end
    end

    if particleCount > 0 then
        local color = impactColor(materialType)
        local fleck = materialType == MAT_METAL and "effects/fleck_tile1" or "effects/fleck_cement1"
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
    end

    local smokeEffect
    if options.smoke ~= false then
        local smokePosition = position + vector_up * 10 + normal * 50
        local smoke = CreateParticleSystemNoEntity("geblib_debris_smoke", smokePosition)
        if smoke then
            smokeEffect = smoke
            local smokeCount = math.Clamp(tonumber(options.smokeCount) or count * 0.5, 1, 1000) * 0.01
            local color = options.smokeColor or impactColor(materialType)
            smoke:SetControlPoint(1, impactDirection)
            smoke:SetControlPoint(2, Vector(smokeCount, smokeCount, smokeCount))
            smoke:SetControlPoint(3, Vector(color.r / 255, color.g / 255, color.b / 255))
            smoke:SetControlPoint(4, smokePosition + VectorRand() * 50)
            smoke:SetControlPoint(5, smokePosition + impactDirection + VectorRand() * 50)
        end
    end

    return spawned, smokeEffect
end

function Visuals.RemoveDebris(entity)
    debrisRemoved(entity)
    if IsValid(entity) then entity:Remove() end
end

function Visuals.GetDebrisCount()
    return #debrisHeap
end

function Visuals.ClearDebris()
    timer.Remove(DEBRIS_TIMER)
    scheduledAt = nil

    for index = #debrisHeap, 1, -1 do
        local entity = debrisHeap[index]
        debrisHeap[index] = nil
        entity.gebLib_DebrisHeapIndex = nil
        entity.gebLib_DebrisEventAt = nil
        entity.gebLib_DebrisExpiresAt = nil
        entity.gebLib_DebrisFadePending = nil
        entity.RenderOverride = nil
        if IsValid(entity) then entity:Remove() end
    end
end

function Visuals.CreateDecal(materialPath, position, angles, size, lifetime)
    local decal = ents.CreateClientside("geblib_decal")
    if not IsValid(decal) then return NULL end

    decal:SetPos(position or vector_origin)
    decal:SetAngles(angles or angle_zero)
    decal:SetDecalSize(size or 32)
    decal:SetLifeTime(CurTime() + (lifetime or 3))
    decal:SetDecal(materialPath)
    decal:Spawn()

    return decal
end
