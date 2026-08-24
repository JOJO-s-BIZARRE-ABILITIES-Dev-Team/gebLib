local Entity = FindMetaTable("Entity")
local Player = FindMetaTable("Player")
local Weapon = FindMetaTable("Weapon")

local propClasses = {
    prop_dynamic = true,
    prop_physics = true,
    prop_physics_clipped = true,
    prop_physics_multiplayer = true,
    prop_ragdoll = true,
}

function Weapon:gebLib_IsCarried()
    return IsValid(self:GetOwner())
end

function Player:gebLib_ValidAndAlive()
    return IsValid(self) and self:Alive()
end

function Entity:gebLib_IsPerson()
    return self:IsPlayer() or self:IsNPC() or self:IsNextBot()
end

function Entity:gebLib_IsProp()
    return propClasses[self:GetClass()] == true
end

function Entity:gebLib_IsItem()
    return string.StartWith(self:GetClass(), "item_")
end

function Entity:gebLib_Alive()
    if not IsValid(self) or not self:gebLib_IsPerson() then return false end
    if self:IsPlayer() then return self:Alive() end
    return self:Health() > 0
end

function Entity:gebLib_IsLookingAt(position, minimumDot)
    minimumDot = minimumDot or 0.9

    local direction = position - self:GetPos()
    local distance = direction:Length()
    if distance == 0 then return true end

    local lookDirection = self:IsPlayer() and self:GetAimVector() or self:GetForward()
    return lookDirection:Dot(direction) / distance >= minimumDot
end

function Entity:gebLib_CheckSides(distance, filter)
    distance = distance or 1
    filter = filter or self

    local position = self:GetPos()
    local directions = {
        -self:GetUp(),
        self:GetUp(),
        self:GetRight(),
        -self:GetRight(),
        self:GetForward(),
        -self:GetForward(),
    }

    for _, direction in ipairs(directions) do
        local result = util.TraceLine({
            start = position,
            endpos = position + direction * distance,
            filter = filter,
            mask = MASK_SOLID,
        })

        if result.Hit then return result end
    end

    return false
end


function Entity:gebLib_PositionEmpty(position, filter)
    return not util.TraceHull({
        start = position,
        endpos = position,
        mins = self:OBBMins(),
        maxs = self:OBBMaxs(),
        filter = filter or self,
        mask = MASK_PLAYERSOLID,
    }).Hit
end

function Entity:gebLib_FindEmptyPosition(position, distance, step, filter)
    distance = distance or 128
    step = step or 16

    if not isnumber(distance) or distance < 0 then
        error("position search distance must be zero or greater", 2)
    end

    if not isnumber(step) or step <= 0 then
        error("position search step must be greater than zero", 2)
    end

    if self:gebLib_PositionEmpty(position, filter) then return position end

    for offset = step, distance, step do
        local candidates = {
            position + Vector(offset, 0, 0),
            position + Vector(-offset, 0, 0),
            position + Vector(0, offset, 0),
            position + Vector(0, -offset, 0),
            position + Vector(0, 0, offset),
            position + Vector(0, 0, -offset),
        }

        for _, candidate in ipairs(candidates) do
            if self:gebLib_PositionEmpty(candidate, filter) then
                return candidate
            end
        end
    end

    return nil
end

function Entity:gebLib_GetBoneHitBox(bone)
    if isstring(bone) then
        bone = self:LookupBone(bone)
    end

    if bone == nil then return nil end

    for hitboxSet = 0, self:GetHitboxSetCount() - 1 do
        for hitbox = 0, self:GetHitBoxCount(hitboxSet) - 1 do
            if self:GetHitBoxBone(hitbox, hitboxSet) == bone then
                return self:GetHitBoxBounds(hitbox, hitboxSet)
            end
        end
    end

    return nil
end

function Entity:gebLib_Dissolve(delay)
    if CLIENT or not IsValid(self) then return nil end

    delay = delay or 0
    if not isnumber(delay) or delay < 0 then
        error("dissolve delay must be zero or greater", 2)
    end

    local dissolver = ents.Create("env_entity_dissolver")
    if not IsValid(dissolver) then return nil end

    dissolver:SetOwner(self)
    dissolver:Spawn()
    dissolver:SetSaveValue("dissolvetype", 0)
    dissolver:Fire("Dissolve", "!activator", delay, self)
    SafeRemoveEntityDelayed(dissolver, delay + 1)

    return dissolver
end
