local function installDecalAdapter(Visuals)
    local projectedAnimations = {}

    local function validSurface(entity)
        return entity == game.GetWorld() or IsValid(entity)
    end

    local function materialFrom(value)
        if isstring(value) then return Material(value, "noclamp smooth mips") end
        return value
    end

    local function localSurface(entity, position, normal)
        if entity == game.GetWorld() then return position, normal end
        local localPosition = entity:WorldToLocal(position)
        return localPosition, entity:WorldToLocal(position + normal) - localPosition
    end

    local function worldSurface(entity, position, normal)
        if entity == game.GetWorld() then return position, normal end
        local worldPosition = entity:LocalToWorld(position)
        local worldNormal = entity:LocalToWorld(position + normal) - worldPosition
        worldNormal:Normalize()
        return worldPosition, worldNormal
    end

    function Visuals.ProjectDecal(material, entity, position, normal, scale, color)
        material = materialFrom(material)
        if not material or material:IsError() or not validSurface(entity) then return false end
        if not normal or normal:LengthSqr() == 0 then return false end

        local surfaceNormal = normal:GetNormalized()
        util.DecalEx(
            material,
            entity,
            position + surfaceNormal * 0.5,
            -surfaceNormal,
            color or color_white,
            scale or 1,
            scale or 1
        )
        return true
    end

    function Visuals.RegisterProjectedDecalAnimation(name, definition)
        if not isstring(name) or name == "" then
            error("projected decal animation requires a name", 2)
        end
        if not istable(definition)
            or not isstring(definition.texture)
            or definition.texture == "" then
            error("projected decal animation requires a texture", 2)
        end

        local frameCount = math.max(math.floor(tonumber(definition.frameCount) or 1), 1)
        local duration = math.max(tonumber(definition.duration) or 0.2, 0)
        local poolSize = math.max(math.floor(tonumber(definition.poolSize) or 16), 1)
        local materialPrefix = "geblib_projected_decal_" .. util.CRC(name)
        local finalMaterial = CreateMaterial(materialPrefix .. "_final", "UnlitGeneric", {
            ["$basetexture"] = definition.texture,
            ["$frame"] = tostring(frameCount - 1),
            ["$translucent"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1",
            ["$nocull"] = "1",
            ["$decal"] = "1",
        })
        local pool = {}
        for index = 1, poolSize do
            pool[index] = {
                Material = CreateMaterial(materialPrefix .. "_" .. index, "UnlitGeneric", {
                    ["$basetexture"] = definition.texture,
                    ["$frame"] = "0",
                    ["$translucent"] = "1",
                    ["$vertexalpha"] = "1",
                    ["$vertexcolor"] = "1",
                    ["$nocull"] = "1",
                    ["$decal"] = "1",
                }),
                Generation = 0,
            }
        end

        projectedAnimations[name] = {
            FrameCount = frameCount,
            FrameTime = frameCount > 1 and duration / (frameCount - 1) or 0,
            FinalMaterial = finalMaterial,
            Pool = pool,
            NextSlot = 0,
        }
    end

    function Visuals.ProjectAnimatedDecal(name, entity, position, normal, scale, color)
        local animation = projectedAnimations[name]
        if not animation then error("unknown projected decal animation: " .. tostring(name), 2) end
        if not validSurface(entity) or not normal or normal:LengthSqr() == 0 then return false end

        animation.NextSlot = animation.NextSlot % #animation.Pool + 1
        local slot = animation.Pool[animation.NextSlot]
        slot.Generation = slot.Generation + 1
        slot.Material:SetInt("$frame", 0)

        if slot.Material:IsError() or animation.FrameCount == 1 then
            return Visuals.ProjectDecal(animation.FinalMaterial, entity, position, normal, scale, color)
        end

        local generation = slot.Generation
        local localPosition, localNormal = localSurface(entity, position, normal)
        Visuals.ProjectDecal(slot.Material, entity, position, normal, scale, color)

        for frame = 1, animation.FrameCount - 1 do
            timer.Simple(frame * animation.FrameTime, function()
                if slot.Generation ~= generation then return end
                slot.Material:SetInt("$frame", frame)
                if frame ~= animation.FrameCount - 1 or not validSurface(entity) then return end

                local worldPosition, worldNormal = worldSurface(entity, localPosition, localNormal)
                Visuals.ProjectDecal(animation.FinalMaterial, entity, worldPosition, worldNormal, scale, color)
            end)
        end
        return true
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
end

return installDecalAdapter
