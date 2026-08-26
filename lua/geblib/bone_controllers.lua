if SERVER then return end

gebLib.BoneControllers = {}

local BoneControllers = gebLib.BoneControllers
local controllers = {}
local controllerOrder = {}
local playerStates = setmetatable({}, {__mode = "k"})
local suspendedPlayers = setmetatable({}, {__mode = "k"})
local abs = math.abs
local approach = math.Approach

local function isZero(pitch, yaw, roll)
    return abs(pitch) < 0.001
        and abs(yaw) < 0.001
        and abs(roll) < 0.001
end

local function controllerSpeeds(speed)
    if isnumber(speed) then return speed, speed, speed end
    if isangle(speed) then return abs(speed.p), abs(speed.y), abs(speed.r) end
    return 180, 180, 180
end

local function restoreBone(player, state)
    local bone = state.Bone
    if not bone or bone < 0 or bone >= player:GetBoneCount() then return end
    if isZero(state.Pitch, state.Yaw, state.Roll) then return end

    local angles = player:GetManipulateBoneAngles(bone)
    angles.p = angles.p - state.Pitch
    angles.y = angles.y - state.Yaw
    angles.r = angles.r - state.Roll
    player:ManipulateBoneAngles(bone, angles)
end

local function applyBone(player, boneName, target, state)
    local bone = player:LookupBone(boneName)
    if not bone then
        if state then restoreBone(player, state) end
        return nil
    end

    if state and state.Bone == bone
        and abs(state.Pitch - target.Pitch) < 0.001
        and abs(state.Yaw - target.Yaw) < 0.001
        and abs(state.Roll - target.Roll) < 0.001 then
        return state
    end

    if state and state.Bone ~= bone then
        restoreBone(player, state)
        state = nil
    end

    local previousPitch = state and state.Pitch or 0
    local previousYaw = state and state.Yaw or 0
    local previousRoll = state and state.Roll or 0
    local angles = player:GetManipulateBoneAngles(bone)

    angles.p = angles.p - previousPitch + target.Pitch
    angles.y = angles.y - previousYaw + target.Yaw
    angles.r = angles.r - previousRoll + target.Roll
    player:ManipulateBoneAngles(bone, angles)

    state = state or {}
    state.Bone = bone
    state.Pitch = target.Pitch
    state.Yaw = target.Yaw
    state.Roll = target.Roll
    return state
end

local function controllerFrameTime(controller, player)
    local frameTime = controller.GetFrameTime and controller.GetFrameTime(player) or FrameTime()
    if not isnumber(frameTime) or frameTime ~= frameTime then return 0 end
    return math.Clamp(frameTime, 0, 0.05)
end

function BoneControllers.Register(name, definition)
    if not isstring(name) or name == "" then
        error("gebLib.BoneControllers.Register requires a name", 2)
    end
    if not istable(definition)
        or not isstring(definition.Bone)
        or not isfunction(definition.GetTarget) then
        error("bone controller requires Bone and GetTarget", 2)
    end
    if definition.IsActive ~= nil and not isfunction(definition.IsActive) then
        error("bone controller IsActive must be a function", 2)
    end
    if definition.GetFrameTime ~= nil and not isfunction(definition.GetFrameTime) then
        error("bone controller GetFrameTime must be a function", 2)
    end

    local speedPitch, speedYaw, speedRoll = controllerSpeeds(definition.Speed)
    local existing = controllers[name]
    local index = existing and existing.Index or #controllerOrder + 1
    local controller = {
        Name = name,
        Bone = definition.Bone,
        IsActive = definition.IsActive,
        GetTarget = definition.GetTarget,
        GetFrameTime = definition.GetFrameTime,
        ResetImmediately = definition.ResetImmediately == true,
        SpeedPitch = speedPitch,
        SpeedYaw = speedYaw,
        SpeedRoll = speedRoll,
        Index = index,
    }

    controllers[name] = controller
    controllerOrder[index] = controller
end

function BoneControllers.Remove(name)
    local controller = controllers[name]
    if not controller then return false end

    local index = controller.Index
    local last = controllerOrder[#controllerOrder]
    controllerOrder[index] = last
    controllerOrder[#controllerOrder] = nil
    controllers[name] = nil
    if last and last ~= controller then last.Index = index end

    for _, state in pairs(playerStates) do
        state.Controllers[name] = nil
    end
    return true
end

function BoneControllers.Clear(player)
    local state = playerStates[player]
    if not state then return end

    if IsValid(player) then
        for _, boneState in pairs(state.Bones) do
            restoreBone(player, boneState)
        end
    end
    playerStates[player] = nil
end

function BoneControllers.Suspend(player)
    BoneControllers.Clear(player)
    suspendedPlayers[player] = true
end

function BoneControllers.Resume(player)
    suspendedPlayers[player] = nil
end

function BoneControllers.IsSuspended(player)
    return suspendedPlayers[player] == true
end

function BoneControllers.CopyControlledTransforms(source, target)
    if not IsValid(source) or not IsValid(target) then return end

    local copied = {}
    for index = 1, #controllerOrder do
        local boneName = controllerOrder[index].Bone
        if not copied[boneName] then
            copied[boneName] = true
            local sourceBone = source:LookupBone(boneName)
            local targetBone = target:LookupBone(boneName)
            if sourceBone and targetBone then
                target:ManipulateBoneAngles(targetBone, source:GetManipulateBoneAngles(sourceBone))
                target:ManipulateBonePosition(targetBone, source:GetManipulateBonePosition(sourceBone))
                target:ManipulateBoneScale(targetBone, source:GetManipulateBoneScale(sourceBone))
            end
        end
    end
end

hook.Add("UpdateAnimation", "gebLib.BoneControllers", function(player)
    local state = playerStates[player]
    if suspendedPlayers[player] or #controllerOrder == 0 then
        if state then BoneControllers.Clear(player) end
        return
    end

    local totals = state and state.Totals
    if totals then
        for _, total in pairs(totals) do total.Active = false end
    end

    for index = 1, #controllerOrder do
        local controller = controllerOrder[index]
        local controllerState = state and state.Controllers[controller.Name]
        local active = not controller.IsActive or controller.IsActive(player)

        if active or controllerState then
            if not state then
                state = {Controllers = {}, Bones = {}, Totals = {}}
                playerStates[player] = state
                totals = state.Totals
            end

            controllerState = controllerState or {Pitch = 0, Yaw = 0, Roll = 0}
            state.Controllers[controller.Name] = controllerState

            local targetPitch, targetYaw, targetRoll = 0, 0, 0
            if active then
                local first, second, third = controller.GetTarget(player)
                if isangle(first) then
                    targetPitch, targetYaw, targetRoll = first.p, first.y, first.r
                elseif isnumber(first) then
                    targetPitch = first
                    targetYaw = isnumber(second) and second or 0
                    targetRoll = isnumber(third) and third or 0
                end
            end

            if not active and controller.ResetImmediately then
                controllerState.Pitch = 0
                controllerState.Yaw = 0
                controllerState.Roll = 0
            else
                local frameTime = controllerFrameTime(controller, player)
                controllerState.Pitch = approach(controllerState.Pitch, targetPitch, controller.SpeedPitch * frameTime)
                controllerState.Yaw = approach(controllerState.Yaw, targetYaw, controller.SpeedYaw * frameTime)
                controllerState.Roll = approach(controllerState.Roll, targetRoll, controller.SpeedRoll * frameTime)
            end

            if not active and isZero(controllerState.Pitch, controllerState.Yaw, controllerState.Roll) then
                state.Controllers[controller.Name] = nil
            else
                local total = totals[controller.Bone]
                if not total then
                    total = {Pitch = 0, Yaw = 0, Roll = 0}
                    totals[controller.Bone] = total
                elseif not total.Active then
                    total.Pitch = 0
                    total.Yaw = 0
                    total.Roll = 0
                end

                total.Active = true
                total.Pitch = total.Pitch + controllerState.Pitch
                total.Yaw = total.Yaw + controllerState.Yaw
                total.Roll = total.Roll + controllerState.Roll
            end
        end
    end

    if not state then return end

    for boneName, boneState in pairs(state.Bones) do
        local target = totals[boneName]
        if target and target.Active and not isZero(target.Pitch, target.Yaw, target.Roll) then
            state.Bones[boneName] = applyBone(player, boneName, target, boneState)
        else
            restoreBone(player, boneState)
            state.Bones[boneName] = nil
        end
    end

    for boneName, target in pairs(totals) do
        if target.Active
            and not state.Bones[boneName]
            and not isZero(target.Pitch, target.Yaw, target.Roll) then
            state.Bones[boneName] = applyBone(player, boneName, target)
        end
    end

    if not next(state.Controllers) and not next(state.Bones) then
        playerStates[player] = nil
    end
end)
