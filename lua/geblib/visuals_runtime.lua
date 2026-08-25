local function createVisualRuntime(Visuals)
    local DebrisRuntime = {}
    local TIMER_NAME = "gebLib.Visuals.Debris"
    local PHYSICS_TIMER_NAME = "gebLib.Visuals.DebrisPhysics"
    local GROW_TIME = 0.25
    local PHYSICS_SCAN_INTERVAL = 0.25
    local PHYSICS_MIN_SCAN_BUDGET = 256
    local PHYSICS_TARGET_SWEEP_TIME = 0.5
    local PHYSICS_MIN_AGE = 0.5
    local SLEEP_CONFIRMATIONS = 2
    local profile

    timer.Remove(TIMER_NAME)
    timer.Remove(PHYSICS_TIMER_NAME)

    if Visuals.ActiveDebris then
        local oldDebris = {}
        for key, value in pairs(Visuals.ActiveDebris) do
            local entity = isnumber(key) and value or key
            if IsValid(entity) then oldDebris[#oldDebris + 1] = entity end
        end
        for index = 1, #oldDebris do oldDebris[index]:Remove() end
    end

    local heap = {}
    local physicalDebris = {}
    local physicsScanIndex = 1
    local physicsTimerRunning = false
    local scheduledAt
    Visuals.ActiveDebris = heap
    Visuals.MaxDebris = Visuals.MaxDebris or 512
    Visuals.RetireSettledPhysics = Visuals.RetireSettledPhysics ~= false
    DebrisRuntime.Heap = heap
    DebrisRuntime.PhysicalDebris = physicalDebris

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

    local function retirementStats()
        return profileData("retirement")
    end

    local function removePhysicalAt(index)
        local count = #physicalDebris
        local entity = physicalDebris[index]
        if not entity then return end

        local last = physicalDebris[count]
        physicalDebris[count] = nil
        entity.gebLib_DebrisPhysicsIndex = nil
        entity.gebLib_DebrisSleepChecks = nil
        if index < count then
            physicalDebris[index] = last
            last.gebLib_DebrisPhysicsIndex = index
        end
        if physicsScanIndex > #physicalDebris then physicsScanIndex = 1 end
        return entity
    end

    local function unregisterPhysical(entity)
        local index = entity and entity.gebLib_DebrisPhysicsIndex
        if index then removePhysicalAt(index) end
    end

    local scanPhysics

    local function updatePhysicsTimer()
        if Visuals.RetireSettledPhysics and Visuals.DebrisPhysicsEnabled ~= false and #physicalDebris > 0 then
            if not physicsTimerRunning then
                physicsTimerRunning = true
                timer.Create(PHYSICS_TIMER_NAME, PHYSICS_SCAN_INTERVAL, 0, scanPhysics)
            end
        else
            timer.Remove(PHYSICS_TIMER_NAME)
            physicsTimerRunning = false
        end
    end

    local function applyPhysicsDiagnostic(entity)
        if Visuals.DebrisPhysicsEnabled ~= false or not IsValid(entity) then return end
        local physics = entity:GetPhysicsObject()
        if not IsValid(physics) then return end
        if entity.gebLib_DebrisMotionWasEnabled == nil then
            entity.gebLib_DebrisMotionWasEnabled = not physics.IsMotionEnabled or physics:IsMotionEnabled()
        end
        if physics.EnableMotion then physics:EnableMotion(false) end
        if physics.Sleep then physics:Sleep() end
    end

    local function registerPhysical(entity)
        if entity.gebLib_DebrisPhysicsIndex then return end
        local index = #physicalDebris + 1
        physicalDebris[index] = entity
        entity.gebLib_DebrisPhysicsIndex = index
        entity.gebLib_DebrisPhysicsCreatedAt = CurTime()
        entity.gebLib_DebrisSleepChecks = 0
        local stats = retirementStats()
        if stats then stats.peakTracked = math.max(stats.peakTracked, index) end
        applyPhysicsDiagnostic(entity)
        updatePhysicsTimer()
    end

    local function physicsScanBudget(count)
        if count == 0 then return 0 end
        return math.min(
            count,
            math.max(
                PHYSICS_MIN_SCAN_BUDGET,
                math.ceil(count * PHYSICS_SCAN_INTERVAL / PHYSICS_TARGET_SWEEP_TIME)
            )
        )
    end

    scanPhysics = function()
        if not Visuals.RetireSettledPhysics or Visuals.DebrisPhysicsEnabled == false then
            updatePhysicsTimer()
            return
        end

        local stats = retirementStats()
        local startedAt = stats and profile.Now()
        if stats then stats.scans = stats.scans + 1 end
        local checked = 0
        local scanLimit = physicsScanBudget(#physicalDebris)
        local now = CurTime()

        while checked < scanLimit and #physicalDebris > 0 do
            if physicsScanIndex > #physicalDebris then physicsScanIndex = 1 end
            local entity = physicalDebris[physicsScanIndex]
            checked = checked + 1

            if not IsValid(entity) then
                removePhysicalAt(physicsScanIndex)
                if stats then stats.invalid = stats.invalid + 1 end
            else
                local physics = entity:GetPhysicsObject()
                if not IsValid(physics) then
                    removePhysicalAt(physicsScanIndex)
                    if stats then stats.missing = stats.missing + 1 end
                elseif now - (entity.gebLib_DebrisPhysicsCreatedAt or now) < PHYSICS_MIN_AGE then
                    physicsScanIndex = physicsScanIndex + 1
                elseif physics.IsAsleep and physics:IsAsleep() then
                    entity.gebLib_DebrisSleepChecks = (entity.gebLib_DebrisSleepChecks or 0) + 1
                    if stats then stats.sleepingChecks = stats.sleepingChecks + 1 end
                    if entity.gebLib_DebrisSleepChecks >= SLEEP_CONFIRMATIONS then
                        entity:PhysicsDestroy()
                        if not IsValid(entity:GetPhysicsObject()) then
                            entity.gebLib_DebrisRetiredPhysics = true
                            removePhysicalAt(physicsScanIndex)
                            if stats then stats.retired = stats.retired + 1 end
                            if entity.gebLib_DebrisPromoteWhenSettled
                                and entity.gebLib_DebrisFadePending
                                and Visuals.QueueRetiredDebris
                            then
                                Visuals.QueueRetiredDebris(entity)
                            end
                        else
                            entity.gebLib_DebrisSleepChecks = 0
                            physicsScanIndex = physicsScanIndex + 1
                            if stats then stats.failures = stats.failures + 1 end
                        end
                    else
                        physicsScanIndex = physicsScanIndex + 1
                    end
                else
                    entity.gebLib_DebrisSleepChecks = 0
                    physicsScanIndex = physicsScanIndex + 1
                    if stats then stats.awakeChecks = stats.awakeChecks + 1 end
                end
            end
        end

        if stats then
            stats.checks = stats.checks + checked
            stats.scanBudgetTotal = stats.scanBudgetTotal + scanLimit
            stats.maxScanBudget = math.max(stats.maxScanBudget, scanLimit)
            stats.tracked = #physicalDebris
            finishDuration(stats, "scanTime", startedAt)
        end
        updatePhysicsTimer()
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

    local processDue

    local function beginNativeFade(entity)
        entity.gebLib_DebrisFadePending = nil
        entity:SetRenderMode(RENDERMODE_TRANSCOLOR)
        entity:SetRenderFX(kRenderFxFadeFast)
    end

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
                beginNativeFade(entity)
                entity.gebLib_DebrisEventAt = entity.gebLib_DebrisExpiresAt
                siftDown(1)
                if lifecycle then lifecycle.fadeTransitions = lifecycle.fadeTransitions + 1 end
            else
                local valid = IsValid(entity)
                entity = removeAt(1)
                if IsValid(entity) then
                    entity.gebLib_DebrisEventAt = nil
                    entity.gebLib_DebrisExpiresAt = nil
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
        unregisterPhysical(entity)
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
            beginNativeFade(entity)
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
        if clientProp then registerPhysical(entity) end
        if Visuals.DebrisRenderEnabled == false and entity.SetNoDraw then
            entity.gebLib_DebrisNoDrawWas = entity.GetNoDraw and entity:GetNoDraw() or false
            entity:SetNoDraw(true)
        end
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

    function Visuals.RefreshDebrisPhysics(entity)
        if IsValid(entity) and entity.gebLib_DebrisPhysicsIndex then applyPhysicsDiagnostic(entity) end
    end

    function Visuals.SetDebrisPhysicsRetirement(enabled)
        Visuals.RetireSettledPhysics = enabled == true
        updatePhysicsTimer()
        return Visuals.RetireSettledPhysics
    end

    function Visuals.SetDebrisRenderEnabled(enabled)
        enabled = enabled ~= false
        Visuals.DebrisRenderEnabled = enabled
        for index = 1, #heap do
            local entity = heap[index]
            if IsValid(entity) and entity.SetNoDraw then
                if enabled then
                    if entity.gebLib_DebrisNoDrawWas ~= nil then
                        entity:SetNoDraw(entity.gebLib_DebrisNoDrawWas)
                        entity.gebLib_DebrisNoDrawWas = nil
                    end
                elseif entity.gebLib_DebrisNoDrawWas == nil then
                    entity.gebLib_DebrisNoDrawWas = entity.GetNoDraw and entity:GetNoDraw() or false
                    entity:SetNoDraw(true)
                end
            end
        end
        return enabled
    end

    function Visuals.SetDebrisPhysicsEnabled(enabled)
        enabled = enabled ~= false
        if Visuals.DebrisPhysicsEnabled == enabled then return enabled end
        Visuals.DebrisPhysicsEnabled = enabled

        for index = 1, #physicalDebris do
            local entity = physicalDebris[index]
            if IsValid(entity) then
                local physics = entity:GetPhysicsObject()
                if IsValid(physics) then
                    if enabled then
                        local wasEnabled = entity.gebLib_DebrisMotionWasEnabled
                        entity.gebLib_DebrisMotionWasEnabled = nil
                        if wasEnabled and physics.EnableMotion then
                            physics:EnableMotion(true)
                            if physics.Wake then physics:Wake() end
                        end
                    else
                        applyPhysicsDiagnostic(entity)
                    end
                end
            end
        end
        updatePhysicsTimer()
        return enabled
    end

    function Visuals.GetDebrisRuntimeState()
        return {
            retirement = Visuals.RetireSettledPhysics,
            render = Visuals.DebrisRenderEnabled ~= false,
            physics = Visuals.DebrisPhysicsEnabled ~= false,
            trackedPhysics = #physicalDebris,
            scanBudget = physicsScanBudget(#physicalDebris),
            scanInterval = PHYSICS_SCAN_INTERVAL,
            targetSweepTime = PHYSICS_TARGET_SWEEP_TIME,
        }
    end

    function Visuals.RemoveDebris(entity)
        local lifecycle = profileData("lifecycle")
        if lifecycle then lifecycle.manualRemovals = lifecycle.manualRemovals + 1 end
        removed(entity)
        if IsValid(entity) then entity:Remove() end
    end

    function Visuals.GetDebrisCount()
        local batchState = Visuals.GetDebrisBatchState and Visuals.GetDebrisBatchState()
        return #heap + (batchState and batchState.pieces or 0)
    end

    function Visuals.ClearDebris()
        local lifecycle = profileData("lifecycle")
        if lifecycle then
            lifecycle.clearCalls = lifecycle.clearCalls + 1
            lifecycle.cleared = lifecycle.cleared + #heap
        end
        timer.Remove(TIMER_NAME)
        timer.Remove(PHYSICS_TIMER_NAME)
        physicsTimerRunning = false
        scheduledAt = nil
        physicsScanIndex = 1

        for index = #heap, 1, -1 do
            local entity = heap[index]
            heap[index] = nil
            entity.gebLib_DebrisHeapIndex = nil
            entity.gebLib_DebrisEventAt = nil
            entity.gebLib_DebrisExpiresAt = nil
            entity.gebLib_DebrisFadePending = nil
            entity.gebLib_DebrisPhysicsIndex = nil
            entity.gebLib_DebrisSleepChecks = nil
            entity.gebLib_DebrisMotionWasEnabled = nil
            entity.gebLib_DebrisNoDrawWas = nil
            if IsValid(entity) then entity:Remove() end
        end
        for index = #physicalDebris, 1, -1 do physicalDebris[index] = nil end
        if Visuals.ClearDebrisBatches then Visuals.ClearDebrisBatches() end
    end

    return DebrisRuntime
end

return createVisualRuntime
