local function installDecalAdapter(Visuals)
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
