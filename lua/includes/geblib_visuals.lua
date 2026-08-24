gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

Visuals.ActiveDebris = Visuals.ActiveDebris or setmetatable({}, {__mode = "k"})
local activeDebris = Visuals.ActiveDebris

local function drawDebris(entity)
    local state = activeDebris[entity]
    if not state then return end

    local blend = 1
    if CurTime() > state.expiresAt - 1 then
        blend = math.Clamp(state.expiresAt - CurTime(), 0, 1)
    end

    render.SetBlend(blend)
    entity:DrawModel()
    render.SetBlend(1)
end

function Visuals.CreateDebris(modelPath, clientProp, lifetime)
    local entity
    if clientProp then
        entity = ents.CreateClientProp(modelPath)
    else
        entity = ClientsideModel(modelPath)
    end

    if not IsValid(entity) then return NULL end

    activeDebris[entity] = {
        expiresAt = CurTime() + (lifetime or 10),
        desiredScale = entity:GetModelScale(),
        animating = true,
    }

    entity:SetModelScale(0, 0)
    entity.RenderOverride = drawDebris
    return entity
end

function Visuals.RemoveDebris(entity)
    activeDebris[entity] = nil
    if IsValid(entity) then entity:Remove() end
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

hook.Add("Think", "gebLib.Visuals.Debris", function()
    local now = CurTime()

    for entity, state in pairs(activeDebris) do
        if not IsValid(entity) or now >= state.expiresAt then
            Visuals.RemoveDebris(entity)
        elseif state.animating then
            local scale = Lerp(
                math.ease.InOutSine(math.Clamp(FrameTime() * 24, 0, 1)),
                entity:GetModelScale(),
                state.desiredScale
            )

            if math.abs(scale - state.desiredScale) < 0.001 then
                scale = state.desiredScale
                state.animating = false
            end

            entity:SetModelScale(scale)
        end
    end
end)
