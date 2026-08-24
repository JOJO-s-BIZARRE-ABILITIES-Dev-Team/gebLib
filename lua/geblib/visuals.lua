gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

local DEBRIS_TIMER = "gebLib.Visuals.Debris"
local GROW_TIME = 0.25

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

local function expiresAt(entity)
    return entity.gebLib_DebrisExpiresAt or math.huge
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
        if expiresAt(debrisHeap[parent]) <= expiresAt(debrisHeap[index]) then return end
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
        if right <= count and expiresAt(debrisHeap[right]) < expiresAt(debrisHeap[left]) then
            smallest = right
        end

        if expiresAt(debrisHeap[index]) <= expiresAt(debrisHeap[smallest]) then return end
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
        if index > 1 and expiresAt(last) < expiresAt(debrisHeap[parent]) then
            siftUp(index)
        else
            siftDown(index)
        end
    end

    return removed
end

local expireDueDebris

local function scheduleNextExpiry()
    timer.Remove(DEBRIS_TIMER)

    local entity = debrisHeap[1]
    if not entity then return end

    timer.Create(DEBRIS_TIMER, math.max(expiresAt(entity) - CurTime(), 0), 1, expireDueDebris)
end

expireDueDebris = function()
    local now = CurTime()
    local entity = debrisHeap[1]

    while entity and (not IsValid(entity) or now >= expiresAt(entity)) do
        entity = removeAt(1)
        if IsValid(entity) then
            entity.gebLib_DebrisExpiresAt = nil
            entity:Remove()
        end
        entity = debrisHeap[1]
    end

    scheduleNextExpiry()
end

local function debrisRemoved(entity)
    local index = entity.gebLib_DebrisHeapIndex
    if not index then return end

    local wasFirst = index == 1
    removeAt(index)
    entity.gebLib_DebrisExpiresAt = nil
    if wasFirst then scheduleNextExpiry() end
end

local function drawDebris(entity)
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

    entity.gebLib_DebrisExpiresAt = CurTime() + lifetime
    entity.RenderOverride = drawDebris
    entity:CallOnRemove("gebLib.Visuals.Debris", debrisRemoved)

    if not clientProp then
        local desiredScale = entity:GetModelScale()
        entity:SetModelScale(0, 0)
        entity:SetModelScale(desiredScale, GROW_TIME)
    end

    local previousFirst = debrisHeap[1]
    pushDebris(entity)
    if debrisHeap[1] ~= previousFirst then scheduleNextExpiry() end
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

    for index = #debrisHeap, 1, -1 do
        local entity = debrisHeap[index]
        debrisHeap[index] = nil
        entity.gebLib_DebrisHeapIndex = nil
        entity.gebLib_DebrisExpiresAt = nil
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
