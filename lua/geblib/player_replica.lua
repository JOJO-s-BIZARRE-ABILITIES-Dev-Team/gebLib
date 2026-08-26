if SERVER then return end

gebLib.PlayerReplica = {}

local PlayerReplica = gebLib.PlayerReplica

function PlayerReplica.Create(source, renderGroup, shadows)
    if not IsValid(source) then return NULL end

    local model = source:GetModel()
    if not model or model == "" then return NULL end

    local replica = ClientsideModel(model, renderGroup or RENDERGROUP_TRANSLUCENT)
    if not IsValid(replica) then return NULL end

    replica:SetNoDraw(true)
    replica:SetPlaybackRate(0)
    replica:SetRenderMode(RENDERMODE_TRANSALPHA)
    replica:DrawShadow(shadows == true)
    PlayerReplica.SyncAppearance(replica, source)
    return replica
end

function PlayerReplica.SyncAppearance(replica, source)
    if not IsValid(replica) or not IsValid(source) then return false end

    local model = source:GetModel()
    if model and model ~= "" and replica:GetModel() ~= model then replica:SetModel(model) end
    if replica:GetSkin() ~= source:GetSkin() then replica:SetSkin(source:GetSkin()) end
    replica:SetColor(source:GetColor())
    replica:SetModelScale(source:GetModelScale(), 0)

    for group = 0, source:GetNumBodyGroups() - 1 do
        local bodygroup = source:GetBodygroup(group)
        if replica:GetBodygroup(group) ~= bodygroup then
            replica:SetBodygroup(group, bodygroup)
        end
    end
    return true
end

function PlayerReplica.SyncPose(replica, source)
    if not IsValid(replica) or not IsValid(source) then return false end

    replica:SetSequence(source:GetSequence())
    replica:SetCycle(source:GetCycle())
    replica:SetPlaybackRate(0)

    for index = 0, source:GetNumPoseParameters() - 1 do
        local name = source:GetPoseParameterName(index)
        local minimum, maximum = source:GetPoseParameterRange(index)
        local value = math.Remap(source:GetPoseParameter(index), 0, 1, minimum, maximum)
        replica:SetPoseParameter(name, value)
    end

    if gebLib.BoneControllers then
        gebLib.BoneControllers.CopyControlledTransforms(source, replica)
    end
    replica:InvalidateBoneCache()
    return true
end

function PlayerReplica.CaptureBoneMatrices(source, matrices)
    matrices = matrices or {}
    if not IsValid(source) then return matrices, 0 end

    local boneCount = source:GetBoneCount() or 0
    local copyBoneMatrix = source.CopyBoneMatrix
    for bone = 0, boneCount - 1 do
        local boneName = source:GetBoneName(bone)
        if boneName and boneName ~= "__INVALIDBONE__" then
            local matrix = matrices[bone] or Matrix()
            matrices[bone] = matrix
            if isfunction(copyBoneMatrix) then
                copyBoneMatrix(source, bone, matrix)
            else
                local sourceMatrix = source:GetBoneMatrix(bone)
                if sourceMatrix then
                    matrix:Set(sourceMatrix)
                else
                    matrices[bone] = nil
                end
            end
        else
            matrices[bone] = nil
        end
    end

    for bone in pairs(matrices) do
        if isnumber(bone) and bone >= boneCount then matrices[bone] = nil end
    end
    return matrices, boneCount
end

function PlayerReplica.ApplyBoneMatrices(replica, matrices, boneCount)
    if not IsValid(replica) or not istable(matrices) then return false end

    boneCount = math.min(boneCount or replica:GetBoneCount() or 0, replica:GetBoneCount() or 0)
    for bone = 0, boneCount - 1 do
        local matrix = matrices[bone]
        if matrix then replica:SetBoneMatrix(bone, matrix) end
    end
    return true
end
