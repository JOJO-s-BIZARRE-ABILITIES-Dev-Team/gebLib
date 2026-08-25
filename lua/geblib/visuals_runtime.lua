local function createVisualRuntime(Visuals)
    local DebrisRuntime = {}
    local TIMER_NAME = "gebLib.Visuals.Debris"
    local GROW_TIME = 0.25
    local profile

    timer.Remove(TIMER_NAME)

    if Visuals.ActiveDebris then
        local oldDebris = {}
        for key, value in pairs(Visuals.ActiveDebris) do
            local entity = isnumber(key) and value or key
            if IsValid(entity) then oldDebris[#oldDebris + 1] = entity end
        end
        for index = 1, #oldDebris do oldDebris[index]:Remove() end
    end

    local heap = {}
    local scheduledAt
    Visuals.ActiveDebris = heap
    Visuals.MaxDebris = Visuals.MaxDebris or 512
    DebrisRuntime.Heap = heap

    function DebrisRuntime.SetProfile(current)
        profile = current
    end

    local function profileData(name)
        if not profile or not profile.IsActive() then return end
        return profile.Data()[name]
    end

    local function finishDuration(stats, key, startedAt)
        if not stats then return 0 end
        return profile.RecordDuration(stats, key, startedAt)
    end

    local function eventAt(entity)
        return entity.gebLib_DebrisEventAt or math.huge
    end

    local function swap(left, right)
        local leftEntity = heap[left]
        local rightEntity = heap[right]
        heap[left] = rightEntity
        heap[right] = leftEntity
        rightEntity.gebLib_DebrisHeapIndex = left
        leftEntity.gebLib_DebrisHeapIndex = right
    end

    local function siftUp(index)
        while index > 1 do
            local parent = math.floor(index / 2)
            if eventAt(heap[parent]) <= eventAt(heap[index]) then return end
            swap(parent, index)
            index = parent
        end
    end

    local function siftDown(index)
        local count = #heap
        while true do
            local left = index * 2
            if left > count then return end

            local smallest = left
            local right = left + 1
            if right <= count and eventAt(heap[right]) < eventAt(heap[left]) then
                smallest = right
            end
            if eventAt(heap[index]) <= eventAt(heap[smallest]) then return end
            swap(index, smallest)
            index = smallest
        end
    end

    local function push(entity)
        local index = #heap + 1
        heap[index] = entity
        entity.gebLib_DebrisHeapIndex = index
        siftUp(index)
    end

    local function removeAt(index)
        local count = #heap
        local removed = heap[index]
        if not removed then return end

        local last = heap[count]
        heap[count] = nil
        removed.gebLib_DebrisHeapIndex = nil
        if index < count then
            heap[index] = last
            last.gebLib_DebrisHeapIndex = index
            local parent = math.floor(index / 2)
            if index > 1 and eventAt(last) < eventAt(heap[parent]) then
                siftUp(index)
            else
                siftDown(index)
            end
        end
        return removed
    end

    local drawDebris
    local processDue

    local function schedule()
        local lifecycle = profileData("lifecycle")
        local startedAt = lifecycle and profile.Now()
        if lifecycle then lifecycle.scheduleCalls = lifecycle.scheduleCalls + 1 end
        local entity = heap[1]
        if not entity then
            if lifecycle and scheduledAt ~= nil then
                lifecycle.timerRemoves = lifecycle.timerRemoves + 1
            end
            timer.Remove(TIMER_NAME)
            scheduledAt = nil
            if lifecycle then finishDuration(lifecycle, "scheduleTime", startedAt) end
            return
        end

        local nextAt = eventAt(entity)
        if scheduledAt == nextAt then
            if lifecycle then finishDuration(lifecycle, "scheduleTime", startedAt) end
            return
        end
        scheduledAt = nextAt
        timer.Create(TIMER_NAME, math.max(nextAt - CurTime(), 0), 1, processDue)
        if lifecycle then lifecycle.timerCreates = lifecycle.timerCreates + 1 end
        if lifecycle then finishDuration(lifecycle, "scheduleTime", startedAt) end
    end

    processDue = function()
        local lifecycle = profileData("lifecycle")
        local startedAt = lifecycle and profile.Now()
        if lifecycle then lifecycle.timerFires = lifecycle.timerFires + 1 end
        scheduledAt = nil
        local now = CurTime()
        local entity = heap[1]

        while entity and (not IsValid(entity) or now >= eventAt(entity)) do
            if IsValid(entity) and entity.gebLib_DebrisFadePending then
                entity.gebLib_DebrisFadePending = nil
                entity.gebLib_DebrisEventAt = entity.gebLib_DebrisExpiresAt
                entity.RenderOverride = drawDebris
                siftDown(1)
                if lifecycle then lifecycle.fadeTransitions = lifecycle.fadeTransitions + 1 end
            else
                local valid = IsValid(entity)
                entity = removeAt(1)
                if IsValid(entity) then
                    entity.gebLib_DebrisEventAt = nil
                    entity.gebLib_DebrisExpiresAt = nil
                    entity.RenderOverride = nil
                    entity:Remove()
                end
                if lifecycle then
                    if valid then
                        lifecycle.expirations = lifecycle.expirations + 1
                    else
                        lifecycle.invalidDropped = lifecycle.invalidDropped + 1
                    end
                end
            end
            entity = heap[1]
        end
        schedule()
        if lifecycle then finishDuration(lifecycle, "timerTime", startedAt) end
    end

    local function removed(entity)
        local index = entity.gebLib_DebrisHeapIndex
        if not index then return end
        local lifecycle = profileData("lifecycle")
        local startedAt = lifecycle and profile.Now()
        if lifecycle then lifecycle.removeCallbacks = lifecycle.removeCallbacks + 1 end
        local wasFirst = index == 1
        removeAt(index)
        entity.gebLib_DebrisEventAt = nil
        entity.gebLib_DebrisExpiresAt = nil
        entity.gebLib_DebrisFadePending = nil
        if wasFirst then schedule() end
        if lifecycle then finishDuration(lifecycle, "removeTime", startedAt) end
    end

    drawDebris = function(entity)
        local lifecycle = profileData("lifecycle")
        local startedAt = lifecycle and profile.Now()
        if lifecycle then lifecycle.fadeDrawCalls = lifecycle.fadeDrawCalls + 1 end
        local expiry = entity.gebLib_DebrisExpiresAt
        if not expiry then
            entity:DrawModel()
            if lifecycle then
                local elapsed = finishDuration(lifecycle, "fadeDrawTime", startedAt)
                lifecycle.maxFadeDrawTime = math.max(lifecycle.maxFadeDrawTime, elapsed)
            end
            return
        end

        local remaining = expiry - CurTime()
        if remaining <= 0 then
            if lifecycle then
                local elapsed = finishDuration(lifecycle, "fadeDrawTime", startedAt)
                lifecycle.maxFadeDrawTime = math.max(lifecycle.maxFadeDrawTime, elapsed)
            end
            return
        end
        if remaining >= 1 then
            entity:DrawModel()
            if lifecycle then
                local elapsed = finishDuration(lifecycle, "fadeDrawTime", startedAt)
                lifecycle.maxFadeDrawTime = math.max(lifecycle.maxFadeDrawTime, elapsed)
            end
            return
        end

        render.SetBlend(remaining)
        entity:DrawModel()
        render.SetBlend(1)
        if lifecycle then
            local elapsed = finishDuration(lifecycle, "fadeDrawTime", startedAt)
            lifecycle.maxFadeDrawTime = math.max(lifecycle.maxFadeDrawTime, elapsed)
        end
    end

    function Visuals.CreateDebris(modelPath, clientProp, lifetime, ignoreLimit, material, animateGrowth)
        local limit = math.max(math.floor(tonumber(Visuals.MaxDebris) or 512), 0)
        if limit == 0 then return NULL end

        local stats = profileData("creations")
        local startedAt = stats and profile.Now()
        if stats then stats.requests = stats.requests + 1 end
        local factoryStartedAt = stats and profile.Now()
        local entity = clientProp and ents.CreateClientProp(modelPath) or ClientsideModel(modelPath)

        if stats then
            finishDuration(stats, "factoryTime", factoryStartedAt)
            if clientProp then stats.props = stats.props + 1 else stats.models = stats.models + 1 end
            if not IsValid(entity) then stats.failed = stats.failed + 1 end
        end
        if not IsValid(entity) then
            if stats then
                local elapsed = finishDuration(stats, "totalTime", startedAt)
                stats.maxTime = math.max(stats.maxTime, elapsed)
            end
            return NULL
        end

        local materialStartedAt = stats and profile.Now()
        if type(material) == "string" and material ~= "" then entity:SetMaterial(material) end
        if stats then finishDuration(stats, "materialTime", materialStartedAt) end

        local limitStartedAt = stats and profile.Now()
        while not ignoreLimit and #heap >= limit do
            if stats then stats.evictions = stats.evictions + 1 end
            Visuals.RemoveDebris(heap[1])
        end
        if stats then finishDuration(stats, "limitTime", limitStartedAt) end

        local lifetimeStartedAt = stats and profile.Now()
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
        if stats then finishDuration(stats, "lifetimeTime", lifetimeStartedAt) end

        local callbackStartedAt = stats and profile.Now()
        entity:CallOnRemove("gebLib.Visuals.Debris", removed)
        if stats then finishDuration(stats, "callbackTime", callbackStartedAt) end

        local growthStartedAt = stats and profile.Now()
        if not clientProp and animateGrowth ~= false then
            local desiredScale = entity:GetModelScale()
            entity:SetModelScale(0, 0)
            entity:SetModelScale(desiredScale, GROW_TIME)
        end
        if stats then finishDuration(stats, "growthTime", growthStartedAt) end

        local heapStartedAt = stats and profile.Now()
        local previousFirst = heap[1]
        push(entity)
        if stats then finishDuration(stats, "heapTime", heapStartedAt) end
        if stats then
            stats.peakActive = math.max(stats.peakActive, #heap)
        end

        local scheduleStartedAt = stats and profile.Now()
        if heap[1] ~= previousFirst then schedule() end
        if stats then finishDuration(stats, "scheduleTime", scheduleStartedAt) end
        if stats then
            local elapsed = finishDuration(stats, "totalTime", startedAt)
            stats.maxTime = math.max(stats.maxTime, elapsed)
        end
        return entity
    end

    function Visuals.RemoveDebris(entity)
        local lifecycle = profileData("lifecycle")
        if lifecycle then lifecycle.manualRemovals = lifecycle.manualRemovals + 1 end
        removed(entity)
        if IsValid(entity) then entity:Remove() end
    end

    function Visuals.GetDebrisCount()
        return #heap
    end

    function Visuals.ClearDebris()
        local lifecycle = profileData("lifecycle")
        if lifecycle then
            lifecycle.clearCalls = lifecycle.clearCalls + 1
            lifecycle.cleared = lifecycle.cleared + #heap
        end
        timer.Remove(TIMER_NAME)
        scheduledAt = nil

        for index = #heap, 1, -1 do
            local entity = heap[index]
            heap[index] = nil
            entity.gebLib_DebrisHeapIndex = nil
            entity.gebLib_DebrisEventAt = nil
            entity.gebLib_DebrisExpiresAt = nil
            entity.gebLib_DebrisFadePending = nil
            entity.RenderOverride = nil
            if IsValid(entity) then entity:Remove() end
        end
    end

    return DebrisRuntime
end

return createVisualRuntime
