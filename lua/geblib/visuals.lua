gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

local DEBRIS_TIMER = "gebLib.Visuals.Debris"
local GROW_TIME = 0.25
local DEFAULT_DEBRIS_GRAVITY = Vector(0, 0, -600)

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
            local particleVelocity = VectorRand(-speed, speed)
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

function Visuals.CreateDebris(modelPath, clientProp, lifetime)
    local limit = math.max(math.floor(tonumber(Visuals.MaxDebris) or 512), 0)
    if limit == 0 then return NULL end

    local entity
    if clientProp then
        entity = ents.CreateClientProp(modelPath)
    else
        entity = ClientsideModel(modelPath)
    end

    if not IsValid(entity) then return NULL end

    while #debrisHeap >= limit do Visuals.RemoveDebris(debrisHeap[1]) end

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
