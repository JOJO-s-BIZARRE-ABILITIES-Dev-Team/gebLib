local function installDebrisBatch(Visuals, Runtime, Surface, Profile)
    local profileClock = Profile.Now
    local recordDuration = Profile.RecordDuration

    local BATCH_HOOK_NAME = "gebLib.Visuals.DebrisBatches"
    local PROMOTION_HOOK_NAME = "gebLib.Visuals.DebrisPromotions"
    local MESH_WARMUP_HOOK_NAME = "gebLib.Visuals.DebrisMeshWarmup"
    local MAX_BATCH_VERTICES = 60000
    local MAX_PROMOTION_PIECES_PER_FRAME = 64
    local BATCH_CELL_SIZE = 512
    local BATCH_EXPIRY_BUCKET = 0.25
    local BATCH_QUEUE_MAX_DELAY = 0.05
    local BATCH_QUEUE_TARGET_PIECES = 12
    local BATCH_LIGHTING_INTERVAL = 1.5
    local MAX_LIGHTING_REFRESHES_PER_HOOK = 1
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
    local pendingStaticGroups = {}
    local pendingStaticOrder = {}
    local pendingStaticPieces = 0
    local pendingBatchScheduler = {}
    local lightingCells = {}
    local flushPendingStaticPieces
    Visuals.StaticBatchingDefault = Visuals.StaticBatchingDefault ~= false
    local staticBatchingEnabled = Visuals.StaticBatchingDefault

    if hook and hook.Remove then hook.Remove("PostDrawOpaqueRenderables", BATCH_HOOK_NAME) end
    if hook and hook.Remove then hook.Remove("Think", PROMOTION_HOOK_NAME) end
    if hook and hook.Remove then hook.Remove("Think", MESH_WARMUP_HOOK_NAME) end

    local function batchStats()
        if not Profile or not Profile.IsActive() then return end
        return Profile.Data().batching
    end

    local function destroyBatch(batch)
        for index = 1, #batch.meshes do
            local drawing = batch.meshes[index]
            if drawing.mesh and drawing.mesh.Destroy then drawing.mesh:Destroy() end
        end

        local cell = batch.lightingCell
        if cell then
            cell.references = cell.references - 1
            if cell.references <= 0 then lightingCells[cell.key] = nil end
        end
    end

    local function clearPendingStaticPieces()
        Runtime.Unregister(pendingBatchScheduler)
        pendingStaticGroups = {}
        pendingStaticOrder = {}
        pendingStaticPieces = 0
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
        clearPendingStaticPieces()
        for index = #debrisBatches, 1, -1 do
            destroyBatch(debrisBatches[index])
            debrisBatches[index] = nil
        end
        activeBatchPieces = 0
        lightingCells = {}
    end

    function Visuals.SetDebrisStaticBatching(enabled)
        local shouldEnable = enabled == true
        if not shouldEnable and flushPendingStaticPieces then flushPendingStaticPieces(true) end
        staticBatchingEnabled = shouldEnable
        if not staticBatchingEnabled then
            clearPromotionQueue()
            clearPendingStaticPieces()
        end
        return staticBatchingEnabled
    end

    function Visuals.GetDebrisBatchState()
        return {
            enabled = staticBatchingEnabled,
            batches = #debrisBatches,
            pieces = activeBatchPieces,
            pendingPromotions = pendingPromotionPieces,
            pendingPieces = pendingStaticPieces,
            lightingCells = table.Count and table.Count(lightingCells) or 0,
            promotionBudget = MAX_PROMOTION_PIECES_PER_FRAME,
        }
    end

    local function sourceMeshes(modelPath, stats, cacheFailure)
        local cached = modelMeshCache[modelPath]
        if cached ~= nil then
            if stats then stats.cacheHits = stats.cacheHits + 1 end
            return cached or nil
        end

        if stats then stats.cacheMisses = stats.cacheMisses + 1 end
        local startedAt = stats and profileClock and profileClock()
        local meshes = util.GetModelMeshes and util.GetModelMeshes(modelPath, 0)
        if meshes then
            modelMeshCache[modelPath] = meshes
        elseif cacheFailure ~= false then
            modelMeshCache[modelPath] = false
        end
        if stats then recordDuration(stats, "sourceTime", startedAt) end
        return meshes
    end

    if hook and hook.Add and Surface.AllModels and util and util.GetModelMeshes then
        local warmupIndex = 1
        hook.Add("Think", MESH_WARMUP_HOOK_NAME, function()
            local modelPath = Surface.AllModels[warmupIndex]
            if not modelPath then
                hook.Remove("Think", MESH_WARMUP_HOOK_NAME)
                return
            end

            if sourceMeshes(modelPath, nil, false) then
                warmupIndex = warmupIndex + 1
            end
        end)
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

    local function batchCell(position)
        local x = math.floor(position.x / BATCH_CELL_SIZE)
        local y = math.floor(position.y / BATCH_CELL_SIZE)
        local z = math.floor(position.z / BATCH_CELL_SIZE)
        return x .. ":" .. y .. ":" .. z, x, y, z
    end

    local function expiryBucket(expiresAt)
        return math.floor(expiresAt / BATCH_EXPIRY_BUCKET)
    end

    local function lightingCellFor(position)
        local key, x, y, z = batchCell(position)
        local cell = lightingCells[key]
        if cell then
            cell.references = cell.references + 1
            return cell
        end

        local phaseIndex = math.abs(x * 73 + y * 193 + z * 389) % 16
        cell = {
            key = key,
            position = Vector(position.x, position.y, position.z),
            phase = phaseIndex / 16 * BATCH_LIGHTING_INTERVAL,
            references = 1,
            revision = 0,
        }
        lightingCells[key] = cell
        return cell
    end

    local function buildStaticBatch(pieces, lifetime, shadows, expiresAt)
        if #pieces == 0 or not Mesh or not mesh or not mesh.Begin or not util.GetModelMeshes then return false end
        local stats = batchStats()
        local totalStartedAt = stats and profileClock()
        local transformTime = 0
        local buildTime = 0
        local groups
        local groupOrder = {}
        local bounds = {}
        local centerX, centerY, centerZ = 0, 0, 0

        local function fail(built)
            if built then destroyBuiltMeshes(built) end
            if stats then
                stats.failures = stats.failures + 1
                recordBatchTiming(stats, totalStartedAt, transformTime, buildTime)
            end
            return false
        end

        local sharedMaterialName = pieces[1].material
        local singleMaterial = type(sharedMaterialName) == "string" and sharedMaterialName ~= ""
        if singleMaterial then
            for pieceIndex = 2, #pieces do
                if pieces[pieceIndex].material ~= sharedMaterialName then
                    singleMaterial = false
                    break
                end
            end
        end

        local singleGroup
        if singleMaterial then
            local material = Material(sharedMaterialName)
            if not material or material.IsError and material:IsError() then return fail() end
            singleGroup = {
                material = material,
                chunks = {{entries = {}, vertexCount = 0}},
            }
            groupOrder[1] = singleGroup
        else
            groups = {}
        end

        for pieceIndex = 1, #pieces do
            local piece = pieces[pieceIndex]
            local angles = piece.angles or angle_zero
            piece.scale = tonumber(piece.scale) or 1
            piece.batchForward = angles:Forward()
            piece.batchRight = angles:Right()
            piece.batchUp = angles:Up()
            centerX = centerX + piece.position.x
            centerY = centerY + piece.position.y
            centerZ = centerZ + piece.position.z
            local sources = sourceMeshes(piece.modelPath, stats)
            if not sources then return fail() end

            for sourceIndex = 1, #sources do
                local source = sources[sourceIndex]
                local materialName = piece.material or source.material
                if materialName and source.triangles then
                    local group = singleGroup
                    if not group then
                        group = groups[materialName]
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
                            local forward = piece.batchForward
                            local right = piece.batchRight
                            local up = piece.batchUp
                            local origin = piece.position
                            local scale = piece.scale
                            for triangleIndex = entry.firstVertex, entry.lastVertex, 3 do
                                for corner = 1, 3 do
                                    local vertex = entry.triangles[triangleIndex + corner - 1]
                                    local sourcePosition = vertex.pos
                                    local localX = sourcePosition.x * scale
                                    local localY = sourcePosition.y * scale
                                    local localZ = sourcePosition.z * scale
                                    position.x = origin.x
                                        + forward.x * localX - right.x * localY + up.x * localZ
                                    position.y = origin.y
                                        + forward.y * localX - right.y * localY + up.y * localZ
                                    position.z = origin.z
                                        + forward.z * localX - right.z * localY + up.z * localZ

                                    local sourceNormal = vertex.normal or vector_up
                                    normal.x = forward.x * sourceNormal.x
                                        - right.x * sourceNormal.y + up.x * sourceNormal.z
                                    normal.y = forward.y * sourceNormal.x
                                        - right.y * sourceNormal.y + up.y * sourceNormal.z
                                    normal.z = forward.z * sourceNormal.x
                                        - right.z * sourceNormal.y + up.z * sourceNormal.z

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

        local inversePieceCount = 1 / #pieces
        local center = Vector(
            centerX * inversePieceCount,
            centerY * inversePieceCount,
            centerZ * inversePieceCount
        )
        local lightingCell = lightingCellFor(center)
        debrisBatches[#debrisBatches + 1] = {
            meshes = built,
            center = center,
            mins = bounds.mins,
            maxs = bounds.maxs,
            expiresAt = expiresAt or CurTime() + lifetime,
            pieceCount = #pieces,
            shadowsRequested = shadows,
            lightingCell = lightingCell,
        }
        activeBatchPieces = activeBatchPieces + #pieces
        if stats then
            recordBatchTiming(stats, totalStartedAt, transformTime, buildTime)
            stats.created = stats.created + 1
            stats.pieces = stats.pieces + #pieces
            stats.meshes = stats.meshes + #built
            stats.vertices = stats.vertices + vertices
            if singleMaterial then stats.singleMaterialBuilds = stats.singleMaterialBuilds + 1 end
            if shadows then stats.shadowedPieces = stats.shadowedPieces + #pieces end
        end
        return true
    end

    local function fallbackStaticPieces(group)
        local remaining = group.expiresAt - CurTime()
        if remaining <= 0 then return end

        for index = 1, #group.pieces do
            local piece = group.pieces[index]
            local entity = Visuals.CreateDebris(
                piece.modelPath,
                false,
                remaining,
                group.preserveCount,
                nil,
                false
            )
            if IsValid(entity) then
                entity:SetPos(piece.position)
                entity:SetAngles(piece.angles)
                entity:SetModelScale(piece.scale, 0)
                if piece.material then entity:SetMaterial(piece.material) end
                if not group.shadows then
                    entity:DestroyShadow()
                    entity:DrawShadow(false)
                end
            end
        end
    end

    flushPendingStaticPieces = function(force)
        if pendingStaticPieces == 0 then
            Runtime.Unregister(pendingBatchScheduler)
            return false
        end

        local flushAll = force == true
        local now = CurTime()
        local groups = pendingStaticOrder
        local remainingGroups = {}
        local remainingOrder = {}
        local remainingPieces = 0
        local flushed = 0
        local stats = batchStats()

        for index = 1, #groups do
            local group = groups[index]
            local ready = flushAll
                or #group.pieces >= BATCH_QUEUE_TARGET_PIECES
                or now - group.createdAt >= BATCH_QUEUE_MAX_DELAY

            if ready then
                flushed = flushed + 1
                local ok, built = pcall(
                    buildStaticBatch,
                    group.pieces,
                    0,
                    group.shadows,
                    group.expiresAt
                )
                if not ok or not built then
                    fallbackStaticPieces(group)
                    if stats then
                        if not ok then stats.failures = stats.failures + 1 end
                        stats.queuedFallbackPieces = stats.queuedFallbackPieces + #group.pieces
                    end
                elseif stats then
                    stats.queuedBuilds = stats.queuedBuilds + 1
                end
            else
                remainingGroups[group.key] = group
                remainingOrder[#remainingOrder + 1] = group
                remainingPieces = remainingPieces + #group.pieces
            end
        end

        pendingStaticGroups = remainingGroups
        pendingStaticOrder = remainingOrder
        pendingStaticPieces = remainingPieces
        if stats and flushed > 0 then stats.queueFlushes = stats.queueFlushes + 1 end
        if pendingStaticPieces == 0 then
            Runtime.Unregister(pendingBatchScheduler)
            return false
        end
        return true
    end

    local function queueStaticDebrisPiece(piece, lifetime, shadows, preserveCount)
        if not staticBatchingEnabled
            or type(piece) ~= "table"
            or type(piece.modelPath) ~= "string"
            or piece.modelPath == ""
            or not piece.position
            or not piece.angles
        then
            return false
        end

        lifetime = math.max(tonumber(lifetime) or 0, 0)
        local expiresAt = CurTime() + lifetime
        local cellKey = batchCell(piece.position)
        local key = cellKey .. "\n" .. tostring(piece.material or "")
            .. "\n" .. tostring(expiryBucket(expiresAt)) .. "\n" .. tostring(shadows ~= false)
        local group = pendingStaticGroups[key]
        if not group then
            group = {
                key = key,
                pieces = {},
                expiresAt = expiresAt,
                createdAt = CurTime(),
                shadows = shadows ~= false,
                preserveCount = preserveCount == true,
            }
            pendingStaticGroups[key] = group
            pendingStaticOrder[#pendingStaticOrder + 1] = group
        else
            group.expiresAt = math.min(group.expiresAt, expiresAt)
            if preserveCount then group.preserveCount = true end
        end

        group.pieces[#group.pieces + 1] = piece
        pendingStaticPieces = pendingStaticPieces + 1
        local stats = batchStats()
        if stats then stats.queuedPieces = stats.queuedPieces + 1 end
        Runtime.Register(
            pendingBatchScheduler,
            "Static debris frame batch",
            flushPendingStaticPieces,
            clearPendingStaticPieces,
            clearPendingStaticPieces
        )
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
                    local material = entity.gebLib_DebrisBatchMaterial or entity:GetMaterial()
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
            group.ownerGroups[group.groupKey] = nil
            if next(group.ownerGroups) == nil then promotionGroups[group.ownerKey] = nil end
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
            stats.maxPromotionPieces = math.max(stats.maxPromotionPieces, #pieces)
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
        local ownerKey = entity.gebLib_DebrisBatchGroup or entity
        local ownerGroups = promotionGroups[ownerKey]
        if not ownerGroups then
            ownerGroups = {}
            promotionGroups[ownerKey] = ownerGroups
        end
        local expiresAt = entity.gebLib_DebrisExpiresAt
        local shadows = entity.gebLib_DebrisBatchShadows == true
        local groupKey = batchCell(entity:GetPos()) .. "\n" .. tostring(expiryBucket(expiresAt))
            .. "\n" .. tostring(shadows)
        local group = ownerGroups[groupKey]
        if not group then
            group = {
                ownerKey = ownerKey,
                ownerGroups = ownerGroups,
                groupKey = groupKey,
                expiresAt = expiresAt,
                shadows = shadows,
                entities = {},
                head = 1,
                tail = 0,
            }
            ownerGroups[groupKey] = group
            promotionTail = promotionTail + 1
            promotionQueue[promotionTail] = group
        else
            group.expiresAt = math.min(group.expiresAt, expiresAt)
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

    local function nextLightingRefresh(cell, now)
        local cycle = math.floor((now - cell.phase) / BATCH_LIGHTING_INTERVAL) + 1
        cell.nextAt = cycle * BATCH_LIGHTING_INTERVAL + cell.phase
    end

    local function prepareBatchLighting(batch, now, refreshes, stats)
        local cell = batch.lightingCell
        local needsLighting = not cell.lighting
        local due = needsLighting or now >= (cell.nextAt or 0)
        if due and (needsLighting or refreshes < MAX_LIGHTING_REFRESHES_PER_HOOK) then
            local startedAt = stats and profileClock()
            local lighting = cell.lighting or {}
            for index = 1, #BATCH_LIGHTING_DIRECTIONS do
                lighting[index] = render.ComputeLighting(
                    cell.position,
                    BATCH_LIGHTING_DIRECTIONS[index][2]
                )
            end
            cell.lighting = lighting
            cell.revision = cell.revision + 1
            nextLightingRefresh(cell, now)
            refreshes = refreshes + 1
            if stats then
                local elapsed = recordDuration(stats, "lightingTime", startedAt)
                stats.lightingSamples = stats.lightingSamples + 1
                stats.maxLightingTime = math.max(stats.maxLightingTime, elapsed)
            end
        elseif due then
            if stats then stats.lightingDeferred = stats.lightingDeferred + 1 end
        elseif stats then
            stats.lightingCacheHits = stats.lightingCacheHits + 1
        end

        return cell, refreshes
    end

    local function bindBatchLighting(cell, stats)
        local startedAt = stats and profileClock()
        render.ResetModelLighting(0, 0, 0)
        for index = 1, #BATCH_LIGHTING_DIRECTIONS do
            local color = cell.lighting[index]
            render.SetModelLighting(BATCH_LIGHTING_DIRECTIONS[index][1], color.x, color.y, color.z)
        end
        if stats then
            local elapsed = recordDuration(stats, "lightingBindTime", startedAt)
            stats.lightingBinds = stats.lightingBinds + 1
            stats.maxLightingBindTime = math.max(stats.maxLightingBindTime, elapsed)
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
            local lightingRefreshes = 0
            local boundLightingCell
            local boundLightingRevision

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
                            local lightingCell
                            lightingCell, lightingRefreshes = prepareBatchLighting(
                                batch,
                                now,
                                lightingRefreshes,
                                stats
                            )
                            if boundLightingCell ~= lightingCell
                                or boundLightingRevision ~= lightingCell.revision
                            then
                                bindBatchLighting(lightingCell, stats)
                                boundLightingCell = lightingCell
                                boundLightingRevision = lightingCell.revision
                            end
                            local fading = blend < 1
                            if fading then
                                render.OverrideBlend(
                                    true,
                                    BLEND_SRC_ALPHA,
                                    BLEND_ONE_MINUS_SRC_ALPHA,
                                    BLENDFUNC_ADD
                                )
                            end
                            render.SetBlend(blend)
                            for meshIndex = 1, #batch.meshes do
                                local drawing = batch.meshes[meshIndex]
                                render.SetMaterial(drawing.material)
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
                stats.maxLightingRefreshesPerHook = math.max(
                    stats.maxLightingRefreshesPerHook,
                    lightingRefreshes
                )
                local elapsed = recordDuration(stats, "drawTime", startedAt)
                stats.maxDrawTime = math.max(stats.maxDrawTime, elapsed)
            end
        end)
    end

    return {
        Build = buildStaticBatch,
        Queue = queueStaticDebrisPiece,
        Enabled = function() return staticBatchingEnabled end,
    }
end

return installDebrisBatch
