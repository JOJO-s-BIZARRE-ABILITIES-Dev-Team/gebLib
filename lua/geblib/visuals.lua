gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

local DEFAULT_DEBRIS_GRAVITY = Vector(0, 0, -600)
local DEFAULT_WATER_GRAVITY = Vector(0, 0, -850)
local DEFAULT_WATER_COLOR = {r = 205, g = 235, b = 255, a = 235}
local DEFAULT_WATER_MIST_COLOR = {r = 225, g = 240, b = 245, a = 145}
local MAX_IMPACT_MODELS = 16
local MAX_IMPACT_PROPS = 12
local IMPACT_HULL_MINS = Vector(-15, -15, -15)
local IMPACT_HULL_MAXS = Vector(15, 15, 15)

local loadInternal = include or function(path)
    return assert(loadfile("lua/" .. path))()
end

local Runtime = gebLib._Runtime or loadInternal("geblib/runtime.lua")
local Surface = loadInternal("geblib/visuals_surface.lua")
local Config = loadInternal("geblib/visuals_config.lua")(Surface)
loadInternal("geblib/visuals_decal.lua")(Visuals)

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

Visuals.RockDebrisModels = Surface.RockModels

if Visuals.ClearDebrisBatches then Visuals.ClearDebrisBatches() end

local Profile
local profileClock
local recordDuration
local BATCH_HOOK_NAME = "gebLib.Visuals.DebrisBatches"
local PROMOTION_HOOK_NAME = "gebLib.Visuals.DebrisPromotions"
local MAX_BATCH_VERTICES = 60000
local MAX_PROMOTION_PIECES_PER_FRAME = 16
local BATCH_LIGHTING_INTERVAL = 0.25
local BATCH_LIGHTING_DIRECTIONS = {
    {BOX_FRONT, Vector(1, 0, 0)},
    {BOX_BACK, Vector(-1, 0, 0)},
    {BOX_RIGHT, Vector(0, -1, 0)},
    {BOX_LEFT, Vector(0, 1, 0)},
    {BOX_TOP, Vector(0, 0, 1)},
    {BOX_BOTTOM, Vector(0, 0, -1)},
}
local debrisBatches = {}
local activeBatchPieces = 0
local modelMeshCache = {}
local promotionQueue = {}
local promotionGroups = {}
local promotionHead = 1
local promotionTail = 0
local pendingPromotionPieces = 0
Visuals.StaticBatchingDefault = Visuals.StaticBatchingDefault ~= false
local staticBatchingEnabled = Visuals.StaticBatchingDefault

if hook and hook.Remove then hook.Remove("PostDrawOpaqueRenderables", BATCH_HOOK_NAME) end
if hook and hook.Remove then hook.Remove("Think", PROMOTION_HOOK_NAME) end

local function batchStats()
    if not Profile or not Profile.IsActive() then return end
    return Profile.Data().batching
end

local function destroyBatch(batch)
    for index = 1, #batch.meshes do
        local drawing = batch.meshes[index]
        if drawing.mesh and drawing.mesh.Destroy then drawing.mesh:Destroy() end
    end
end

local function clearPromotionQueue()
    for queueIndex = promotionHead, promotionTail do
        local group = promotionQueue[queueIndex]
        if group then
            for entityIndex = group.head, group.tail do
                local entity = group.entities[entityIndex]
                if IsValid(entity) then entity.gebLib_DebrisPromotionQueued = nil end
            end
        end
    end
    promotionQueue = {}
    promotionGroups = {}
    promotionHead = 1
    promotionTail = 0
    pendingPromotionPieces = 0
    if hook and hook.Remove then hook.Remove("Think", PROMOTION_HOOK_NAME) end
end

function Visuals.ClearDebrisBatches()
    clearPromotionQueue()
    for index = #debrisBatches, 1, -1 do
        destroyBatch(debrisBatches[index])
        debrisBatches[index] = nil
    end
    activeBatchPieces = 0
end

function Visuals.SetDebrisStaticBatching(enabled)
    staticBatchingEnabled = enabled == true
    if not staticBatchingEnabled then clearPromotionQueue() end
    return staticBatchingEnabled
end

function Visuals.GetDebrisBatchState()
    return {
        enabled = staticBatchingEnabled,
        batches = #debrisBatches,
        pieces = activeBatchPieces,
        pendingPromotions = pendingPromotionPieces,
    }
end

local function sourceMeshes(modelPath, stats)
    local cached = modelMeshCache[modelPath]
    if cached ~= nil then
        if stats then stats.cacheHits = stats.cacheHits + 1 end
        return cached or nil
    end

    if stats then stats.cacheMisses = stats.cacheMisses + 1 end
    local startedAt = stats and profileClock and profileClock()
    local meshes = util.GetModelMeshes and util.GetModelMeshes(modelPath, 0)
    modelMeshCache[modelPath] = meshes or false
    if stats then recordDuration(stats, "sourceTime", startedAt) end
    return meshes
end

local function recordBatchTiming(stats, startedAt, transformTime, buildTime)
    if not stats then return end
    local totalTime = profileClock() - startedAt
    stats.transformTime = stats.transformTime + transformTime
    stats.maxTransformTime = math.max(stats.maxTransformTime, transformTime)
    stats.buildTime = stats.buildTime + buildTime
    stats.maxBuildTime = math.max(stats.maxBuildTime, buildTime)
    stats.totalTime = stats.totalTime + totalTime
    stats.maxTotalTime = math.max(stats.maxTotalTime, totalTime)
end

local function destroyBuiltMeshes(built)
    for index = 1, #built do
        local drawing = built[index]
        if drawing.mesh and drawing.mesh.Destroy then drawing.mesh:Destroy() end
    end
end

local function appendBatchSource(group, piece, triangles)
    local vertexCount = #triangles
    if vertexCount == 0 or vertexCount % 3 ~= 0 then return false end

    local firstVertex = 1
    while firstVertex <= vertexCount do
        local chunk = group.chunks[#group.chunks]
        local capacity = MAX_BATCH_VERTICES - chunk.vertexCount
        if capacity < 3 then
            chunk = {entries = {}, vertexCount = 0}
            group.chunks[#group.chunks + 1] = chunk
            capacity = MAX_BATCH_VERTICES
        end

        local take = math.min(vertexCount - firstVertex + 1, capacity)
        take = take - take % 3
        if take == 0 then return false end
        chunk.entries[#chunk.entries + 1] = {
            piece = piece,
            triangles = triangles,
            firstVertex = firstVertex,
            lastVertex = firstVertex + take - 1,
        }
        chunk.vertexCount = chunk.vertexCount + take
        firstVertex = firstVertex + take
    end
    return true
end

local function buildStaticBatch(pieces, lifetime, shadows, expiresAt)
    if #pieces == 0 or not Mesh or not mesh or not mesh.Begin or not util.GetModelMeshes then return false end
    local stats = batchStats()
    local totalStartedAt = stats and profileClock()
    local transformTime = 0
    local buildTime = 0
    local groups = {}
    local groupOrder = {}
    local bounds = {}

    local function fail(built)
        if built then destroyBuiltMeshes(built) end
        if stats then
            stats.failures = stats.failures + 1
            recordBatchTiming(stats, totalStartedAt, transformTime, buildTime)
        end
        return false
    end

    for pieceIndex = 1, #pieces do
        local piece = pieces[pieceIndex]
        local sources = sourceMeshes(piece.modelPath, stats)
        if not sources then return fail() end

        for sourceIndex = 1, #sources do
            local source = sources[sourceIndex]
            local materialName = piece.material or source.material
            if materialName and source.triangles then
                local group = groups[materialName]
                if not group then
                    local material = Material(materialName)
                    if not material or material.IsError and material:IsError() then return fail() end
                    group = {
                        material = material,
                        chunks = {{entries = {}, vertexCount = 0}},
                    }
                    groups[materialName] = group
                    groupOrder[#groupOrder + 1] = group
                end
                if not appendBatchSource(group, piece, source.triangles) then return fail() end
            end
        end
    end

    local built = {}
    local vertices = 0
    local position = Vector()
    local normal = Vector()

    for groupIndex = 1, #groupOrder do
        local group = groupOrder[groupIndex]
        for chunkIndex = 1, #group.chunks do
            local chunk = group.chunks[chunkIndex]
            if chunk.vertexCount > 0 then
                local drawing
                local meshBegun = false
                local ok = pcall(function()
                    local buildStartedAt = stats and profileClock()
                    drawing = {mesh = Mesh(group.material), material = group.material}
                    if not drawing.mesh then error("failed to create IMesh") end
                    mesh.Begin(drawing.mesh, MATERIAL_TRIANGLES, chunk.vertexCount / 3)
                    meshBegun = true
                    if stats then buildTime = buildTime + profileClock() - buildStartedAt end

                    local transformStartedAt = stats and profileClock()
                    for entryIndex = 1, #chunk.entries do
                        local entry = chunk.entries[entryIndex]
                        local piece = entry.piece
                        for vertexIndex = entry.firstVertex, entry.lastVertex do
                            local vertex = entry.triangles[vertexIndex]
                            position.x = vertex.pos.x * piece.scale
                            position.y = vertex.pos.y * piece.scale
                            position.z = vertex.pos.z * piece.scale
                            position:Rotate(piece.angles)
                            position:Add(piece.position)

                            local sourceNormal = vertex.normal or vector_up
                            normal.x = sourceNormal.x
                            normal.y = sourceNormal.y
                            normal.z = sourceNormal.z
                            normal:Rotate(piece.angles)

                            if not bounds.mins then
                                bounds.mins = Vector(position.x, position.y, position.z)
                                bounds.maxs = Vector(position.x, position.y, position.z)
                            else
                                bounds.mins.x = math.min(bounds.mins.x, position.x)
                                bounds.mins.y = math.min(bounds.mins.y, position.y)
                                bounds.mins.z = math.min(bounds.mins.z, position.z)
                                bounds.maxs.x = math.max(bounds.maxs.x, position.x)
                                bounds.maxs.y = math.max(bounds.maxs.y, position.y)
                                bounds.maxs.z = math.max(bounds.maxs.z, position.z)
                            end

                            local color = vertex.color or color_white
                            mesh.Position(position)
                            mesh.Normal(normal)
                            mesh.TexCoord(0, vertex.u or 0, vertex.v or 0)
                            mesh.Color(color.r or 255, color.g or 255, color.b or 255, color.a or 255)
                            mesh.AdvanceVertex()
                        end
                    end
                    if stats then transformTime = transformTime + profileClock() - transformStartedAt end

                    buildStartedAt = stats and profileClock()
                    mesh.End()
                    meshBegun = false
                    if stats then buildTime = buildTime + profileClock() - buildStartedAt end
                end)

                if meshBegun then pcall(mesh.End) end
                if not ok then
                    if drawing and drawing.mesh and drawing.mesh.Destroy then drawing.mesh:Destroy() end
                    return fail(built)
                end
                built[#built + 1] = drawing
                vertices = vertices + chunk.vertexCount
            end
        end
    end

    if #built == 0 or not bounds.mins then return fail(built) end

    local center = vector_origin
    for index = 1, #pieces do center = center + pieces[index].position end
    center = center / #pieces
    debrisBatches[#debrisBatches + 1] = {
        meshes = built,
        center = center,
        mins = bounds.mins,
        maxs = bounds.maxs,
        expiresAt = expiresAt or CurTime() + lifetime,
        pieceCount = #pieces,
        shadowsRequested = shadows,
    }
    activeBatchPieces = activeBatchPieces + #pieces
    if stats then
        recordBatchTiming(stats, totalStartedAt, transformTime, buildTime)
        stats.created = stats.created + 1
        stats.pieces = stats.pieces + #pieces
        stats.meshes = stats.meshes + #built
        stats.vertices = stats.vertices + vertices
        if shadows then stats.shadowedPieces = stats.shadowedPieces + #pieces end
    end
    return true
end

local function processPromotionQueue()
    local group = promotionQueue[promotionHead]
    if not group then
        clearPromotionQueue()
        return
    end

    local stats = batchStats()
    local startedAt = stats and profileClock()
    local now = CurTime()
    local pieces = {}
    local entities = {}
    local expiresAt

    while #pieces < MAX_PROMOTION_PIECES_PER_FRAME and group.head <= group.tail do
        local entity = group.entities[group.head]
        group.entities[group.head] = nil
        group.head = group.head + 1
        pendingPromotionPieces = pendingPromotionPieces - 1

        if IsValid(entity) then entity.gebLib_DebrisPromotionQueued = nil end
        local entityExpiry = IsValid(entity) and entity.gebLib_DebrisExpiresAt
        if staticBatchingEnabled
            and IsValid(entity)
            and entity.gebLib_DebrisFadePending
            and entityExpiry
            and entityExpiry - now > 1
        then
            local modelPath = entity:GetModel()
            if modelPath and modelPath ~= "" then
                local material = entity:GetMaterial()
                pieces[#pieces + 1] = {
                    modelPath = modelPath,
                    position = entity:GetPos(),
                    angles = entity:GetAngles(),
                    scale = entity:GetModelScale(),
                    material = material ~= "" and material or nil,
                }
                entities[#entities + 1] = entity
                expiresAt = math.min(expiresAt or entityExpiry, entityExpiry)
            elseif stats then
                stats.promotionSkipped = stats.promotionSkipped + 1
            end
        elseif stats then
            stats.promotionSkipped = stats.promotionSkipped + 1
        end
    end

    if group.head > group.tail then
        promotionGroups[group.key] = nil
        promotionQueue[promotionHead] = nil
        promotionHead = promotionHead + 1
    end

    if #pieces > 0 then
        local ok, built = pcall(buildStaticBatch, pieces, 0, group.shadows, expiresAt)
        if ok and built then
            for index = 1, #entities do
                local entity = entities[index]
                if IsValid(entity) then entity:Remove() end
            end
            if stats then stats.promotedPieces = stats.promotedPieces + #entities end
        elseif stats then
            if not ok then stats.failures = stats.failures + 1 end
            stats.promotionFailed = stats.promotionFailed + #entities
        end
    end

    if stats then
        stats.promotionRuns = stats.promotionRuns + 1
        local elapsed = profileClock() - startedAt
        stats.promotionTime = stats.promotionTime + elapsed
        stats.maxPromotionTime = math.max(stats.maxPromotionTime, elapsed)
    end
    if promotionHead > promotionTail then clearPromotionQueue() end
end

function Visuals.QueueRetiredDebris(entity)
    if not staticBatchingEnabled
        or not IsValid(entity)
        or entity.gebLib_DebrisPromotionQueued
        or not entity.gebLib_DebrisFadePending
    then
        return false
    end

    local wasEmpty = pendingPromotionPieces == 0
    local key = entity.gebLib_DebrisBatchGroup or entity
    local group = promotionGroups[key]
    if not group then
        group = {
            key = key,
            shadows = entity.gebLib_DebrisBatchShadows == true,
            entities = {},
            head = 1,
            tail = 0,
        }
        promotionGroups[key] = group
        promotionTail = promotionTail + 1
        promotionQueue[promotionTail] = group
    end

    group.tail = group.tail + 1
    group.entities[group.tail] = entity
    entity.gebLib_DebrisPromotionQueued = true
    pendingPromotionPieces = pendingPromotionPieces + 1
    local stats = batchStats()
    if stats then stats.promotionsQueued = stats.promotionsQueued + 1 end
    if wasEmpty and hook and hook.Add then
        hook.Add("Think", PROMOTION_HOOK_NAME, processPromotionQueue)
    end
    return true
end

local function establishBatchLighting(batch, now, stats)
    if not batch.lighting or now >= (batch.nextLightingAt or 0) then
        local startedAt = stats and profileClock()
        local lighting = batch.lighting or {}
        for index = 1, #BATCH_LIGHTING_DIRECTIONS do
            lighting[index] = render.ComputeLighting(batch.center, BATCH_LIGHTING_DIRECTIONS[index][2])
        end
        batch.lighting = lighting
        batch.nextLightingAt = now + BATCH_LIGHTING_INTERVAL
        if stats then
            local elapsed = recordDuration(stats, "lightingTime", startedAt)
            stats.lightingSamples = stats.lightingSamples + 1
            stats.maxLightingTime = math.max(stats.maxLightingTime, elapsed)
        end
    end

    render.ResetModelLighting(0, 0, 0)
    for index = 1, #BATCH_LIGHTING_DIRECTIONS do
        local color = batch.lighting[index]
        render.SetModelLighting(BATCH_LIGHTING_DIRECTIONS[index][1], color.x, color.y, color.z)
    end
end

if hook and hook.Add then
    hook.Add("PostDrawOpaqueRenderables", BATCH_HOOK_NAME, function(drawingDepth, drawingSkybox, drawing3DSkybox)
        if drawingDepth or drawingSkybox or drawing3DSkybox then return end
        local stats = batchStats()
        local startedAt = stats and profileClock()
        if stats then stats.renderHooks = stats.renderHooks + 1 end
        local now = CurTime()
        local renderEnabled = Visuals.DebrisRenderEnabled ~= false
        local localLightsCleared = false

        for index = #debrisBatches, 1, -1 do
            local batch = debrisBatches[index]
            local remaining = batch.expiresAt - now
            if remaining <= 0 then
                destroyBatch(batch)
                activeBatchPieces = activeBatchPieces - batch.pieceCount
                debrisBatches[index] = debrisBatches[#debrisBatches]
                debrisBatches[#debrisBatches] = nil
                if stats then stats.expired = stats.expired + 1 end
            elseif renderEnabled then
                if not util.IsBoxVisible or util.IsBoxVisible(batch.mins, batch.maxs) then
                    local blend = 1
                    if remaining <= 1 then
                        batch.fadeAlpha = math.max((batch.fadeAlpha or 255) - 4, 0)
                        blend = batch.fadeAlpha / 255
                    end

                    if blend > 0 then
                        if not localLightsCleared then
                            render.SetLocalModelLights()
                            localLightsCleared = true
                        end
                        establishBatchLighting(batch, now, stats)
                        local fading = blend < 1
                        for meshIndex = 1, #batch.meshes do
                            local drawing = batch.meshes[meshIndex]
                            render.SetMaterial(drawing.material)
                            if fading then
                                render.OverrideBlend(
                                    true,
                                    BLEND_SRC_ALPHA,
                                    BLEND_ONE_MINUS_SRC_ALPHA,
                                    BLENDFUNC_ADD
                                )
                            end
                            render.SetBlend(blend)
                            drawing.mesh:Draw()
                        end
                        if fading then
                            render.SetBlend(1)
                            render.OverrideBlend(false, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
                        end
                        if stats then
                            stats.drawCalls = stats.drawCalls + #batch.meshes
                            stats.drawnBatches = stats.drawnBatches + 1
                        end
                    end
                elseif stats then
                    stats.culledBatches = stats.culledBatches + 1
                end
            end
        end

        if stats then
            local elapsed = recordDuration(stats, "drawTime", startedAt)
            stats.maxDrawTime = math.max(stats.maxDrawTime, elapsed)
        end
    end)
end

local DebrisRuntime = loadInternal("geblib/visuals_runtime.lua")(Visuals)
local debrisHeap = DebrisRuntime.Heap

Profile = loadInternal("geblib/visuals_profile.lua")(Visuals, function()
    return debrisHeap
end)
DebrisRuntime.SetProfile(Profile)
profileClock = Profile.Now
recordDuration = Profile.RecordDuration
local finishImpactProfile = Profile.FinishImpact
loadInternal("geblib/visuals_wave.lua")(Visuals, Runtime, Surface, Config, Profile)

function Visuals.CreateDebrisBurst(materialPath, position, count, options)
    local profiling = Profile.IsActive()
    local profileStartedAt = profiling and profileClock()
    local planStartedAt = profiling and profileClock()
    local plan = Config.Burst(materialPath, position, count, options, {gravity = DEFAULT_DEBRIS_GRAVITY})
    if not plan then return 0 end

    local burstStats
    if profiling then
        burstStats = Profile.Data().bursts
        burstStats.calls = burstStats.calls + 1
        burstStats.requestedParticles = burstStats.requestedParticles + plan.count
        recordDuration(burstStats, "planTime", planStartedAt)
    end

    local emitterStartedAt = profiling and profileClock()
    local emitter = ParticleEmitter(plan.position)
    if profiling then recordDuration(burstStats, "emitterTime", emitterStartedAt) end
    if not emitter then
        if profiling then
            burstStats.failed = burstStats.failed + 1
            local elapsed = recordDuration(burstStats, "totalTime", profileStartedAt)
            if elapsed > burstStats.maxTime then burstStats.maxTime = elapsed end
        end
        return 0
    end

    local emitted = 0

    for index = 1, plan.count do
        local addStartedAt = profiling and profileClock()
        local particle = emitter:Add(plan.materialPath, plan.position)
        if profiling then recordDuration(burstStats, "addTime", addStartedAt) end
        if particle then
            local velocityStartedAt = profiling and profileClock()
            local particleVelocity
            if plan.direction then
                particleVelocity = plan.direction * plan.speed
                    + VectorRand(-plan.speed * plan.spread, plan.speed * plan.spread)
            else
                particleVelocity = VectorRand(-plan.speed, plan.speed)
            end
            if plan.velocity then particleVelocity:Add(plan.velocity) end
            if profiling then recordDuration(burstStats, "velocityTime", velocityStartedAt) end

            local setupStartedAt = profiling and profileClock()
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
            if profiling then recordDuration(burstStats, "setupTime", setupStartedAt) end
            emitted = emitted + 1
        elseif profiling then
            burstStats.failedParticles = burstStats.failedParticles + 1
        end
    end

    local finishStartedAt = profiling and profileClock()
    emitter:Finish()
    if profiling then
        recordDuration(burstStats, "finishTime", finishStartedAt)
        burstStats.particles = burstStats.particles + emitted
        local elapsed = recordDuration(burstStats, "totalTime", profileStartedAt)
        if elapsed > burstStats.maxTime then burstStats.maxTime = elapsed end
    end
    return emitted
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
    local plan = Config.Water(position, normal, strength, options)
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

    if sprayCount > 0 then
        local sprayStartedAt = profiling and profileClock()
        spawned = spawned + Visuals.CreateDebrisBurst(
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
            }
        )
        if profiling then recordDuration(waterStats, "sprayTime", sprayStartedAt) end
    end

    if dropletCount > 0 then
        local dropletStartedAt = profiling and profileClock()
        spawned = spawned + Visuals.CreateDebrisBurst(
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
            }
        )
        if profiling then recordDuration(waterStats, "dropletTime", dropletStartedAt) end
    end

    if mistCount > 0 and options.mist ~= false and options.smoke ~= false then
        local mistStartedAt = profiling and profileClock()
        spawned = spawned + Visuals.CreateDebrisBurst(
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
            }
        )
        if profiling then recordDuration(waterStats, "mistTime", mistStartedAt) end
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
    local plan = Config.Impact(position, normal, strength, options)
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
    local batchedModels = staticBatchingEnabled and {} or nil
    local propBatchGroup = staticBatchingEnabled and propCount > 0 and {} or nil
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
                if staticBatchingEnabled then
                    entity.gebLib_DebrisPromoteWhenSettled = true
                    entity.gebLib_DebrisBatchGroup = propBatchGroup
                    entity.gebLib_DebrisBatchShadows = shadows
                end
                Visuals.RefreshDebrisPhysics(entity)
                spawned = spawned + 1
            end
        end
    end
    if profiling then recordDuration(impactStats, "loopTime", loopStartedAt) end

    if batchedModels and #batchedModels > 0 then
        local batchCallOk, batchBuilt = pcall(buildStaticBatch, batchedModels, staticLifetime, shadows)
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
            local smokeCount = math.Clamp(tonumber(options.smokeCount) or count * 0.5, 1, 1000) * 0.01
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
