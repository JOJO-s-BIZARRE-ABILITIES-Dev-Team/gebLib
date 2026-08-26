if SERVER then return end

gebLib.BoneMatrixModifiers = {}

local BoneMatrixModifiers = gebLib.BoneMatrixModifiers
local modifiers = {}
local order = {}
local tracked = setmetatable({}, {__mode = "k"})
local HOOK_NAME = "BuildBonePositions"

local function report(name, message)
    local text = "[gebLib.BoneMatrixModifiers] " .. name .. " failed: " .. tostring(message) .. "\n"
    if ErrorNoHaltWithStack then ErrorNoHaltWithStack(text)
    elseif ErrorNoHalt then ErrorNoHalt(text) end
end

local function sortModifiers()
    table.sort(order, function(left, right)
        if left.Priority == right.Priority then return left.Name < right.Name end
        return left.Priority < right.Priority
    end)
end

local function applyModifiers(entity, state)
    if state.Applying then return end
    state.Applying = true

    local active = state.Active
    local channelWinners = state.ChannelWinners
    for modifier in pairs(active) do active[modifier] = nil end
    for channel in pairs(channelWinners) do channelWinners[channel] = nil end
    for index = 1, #order do
        local modifier = order[index]
        local enabled = true
        if modifier.IsActive then
            local ok, result = pcall(modifier.IsActive, entity)
            if not ok then
                enabled = false
                report(modifier.Name .. " activity", result)
            else
                enabled = result == true
            end
        end
        if enabled then
            active[modifier] = true
            if modifier.Channel then channelWinners[modifier.Channel] = modifier end
        end
    end

    for index = 1, #order do
        local modifier = order[index]
        if active[modifier]
            and (not modifier.Channel or channelWinners[modifier.Channel] == modifier) then
            local ok, message = pcall(modifier.Apply, entity)
            if not ok then report(modifier.Name, message) end
        end
    end
    state.Applying = false
end

function BoneMatrixModifiers.Register(name, definition)
    if not isstring(name) or name == "" then
        error("bone matrix modifier requires a name", 2)
    end
    if not istable(definition) or not isfunction(definition.Apply) then
        error("bone matrix modifier requires Apply", 2)
    end
    if definition.IsActive ~= nil and not isfunction(definition.IsActive) then
        error("bone matrix modifier IsActive must be a function", 2)
    end

    local existing = modifiers[name]
    if existing then
        existing.Priority = tonumber(definition.Priority) or 0
        existing.Channel = definition.Channel
        existing.IsActive = definition.IsActive
        existing.Apply = definition.Apply
    else
        existing = {
            Name = name,
            Priority = tonumber(definition.Priority) or 0,
            Channel = definition.Channel,
            IsActive = definition.IsActive,
            Apply = definition.Apply,
        }
        modifiers[name] = existing
        order[#order + 1] = existing
    end
    sortModifiers()
end

function BoneMatrixModifiers.Remove(name)
    local modifier = modifiers[name]
    if not modifier then return false end
    modifiers[name] = nil
    for index = #order, 1, -1 do
        if order[index] == modifier then table.remove(order, index) break end
    end
    return true
end

function BoneMatrixModifiers.Track(entity, owner)
    if not IsValid(entity) then return false end
    owner = tostring(owner or "default")
    local state = tracked[entity]
    if not state then
        state = {
            Owners = {},
            Active = {},
            ChannelWinners = {},
            Applying = false,
        }
        tracked[entity] = state
        state.CallbackId = entity:AddCallback(HOOK_NAME, function(animatedEntity)
            local current = tracked[animatedEntity]
            if current then applyModifiers(animatedEntity, current) end
        end)
    end
    state.Owners[owner] = true
    return true
end

function BoneMatrixModifiers.Untrack(entity, owner)
    local state = tracked[entity]
    if not state then return false end
    state.Owners[tostring(owner or "default")] = nil
    if next(state.Owners) then return true end
    if IsValid(entity) and state.CallbackId then
        entity:RemoveCallback(HOOK_NAME, state.CallbackId)
    end
    tracked[entity] = nil
    return true
end

function BoneMatrixModifiers.ClearEntity(entity)
    local state = tracked[entity]
    if not state then return false end
    if IsValid(entity) and state.CallbackId then
        entity:RemoveCallback(HOOK_NAME, state.CallbackId)
    end
    tracked[entity] = nil
    return true
end

function BoneMatrixModifiers.Clear()
    for entity in pairs(tracked) do BoneMatrixModifiers.ClearEntity(entity) end
    modifiers = {}
    order = {}
end
