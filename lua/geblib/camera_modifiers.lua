if SERVER then return end

gebLib.CameraModifiers = {}

local CameraModifiers = gebLib.CameraModifiers
local modifiers = {}
local modifierOrder = {}
local HOOK_NAME = "gebLib.CameraModifiers"

local function sortModifiers()
    table.sort(modifierOrder, function(left, right)
        if left.Priority == right.Priority then return left.Name < right.Name end
        return left.Priority < right.Priority
    end)
end

local function reportError(name, message)
    local text = "[gebLib.CameraModifiers] " .. name .. " failed: " .. tostring(message) .. "\n"
    if ErrorNoHaltWithStack then
        ErrorNoHaltWithStack(text)
    elseif ErrorNoHalt then
        ErrorNoHalt(text)
    end
end

local function calculateView(player, position, angles, fov)
    local view = {
        origin = Vector(position.x, position.y, position.z),
        angles = Angle(angles.p, angles.y, angles.r),
        fov = fov,
        drawviewer = false,
    }
    local handled = false

    for index = 1, #modifierOrder do
        local modifier = modifierOrder[index]
        local ok, changed = pcall(modifier.Apply, player, view)
        if not ok then
            reportError(modifier.Name, changed)
        elseif changed == true then
            handled = true
        end
    end

    if handled then return view end
end

function CameraModifiers.Register(name, priority, apply)
    if not isstring(name) or name == "" then
        error("gebLib.CameraModifiers.Register requires a name", 2)
    end
    if not isnumber(priority) then
        error("camera modifier priority must be a number", 2)
    end
    if not isfunction(apply) then
        error("camera modifier apply callback must be a function", 2)
    end

    local existing = modifiers[name]
    if existing then
        existing.Priority = priority
        existing.Apply = apply
    else
        existing = {Name = name, Priority = priority, Apply = apply}
        modifiers[name] = existing
        modifierOrder[#modifierOrder + 1] = existing
    end
    sortModifiers()
    hook.Add("CalcView", HOOK_NAME, calculateView)
end

function CameraModifiers.Remove(name)
    local modifier = modifiers[name]
    if not modifier then return false end

    modifiers[name] = nil
    for index = #modifierOrder, 1, -1 do
        if modifierOrder[index] == modifier then
            table.remove(modifierOrder, index)
            break
        end
    end

    if #modifierOrder == 0 then hook.Remove("CalcView", HOOK_NAME) end
    return true
end

function CameraModifiers.Clear()
    modifiers = {}
    modifierOrder = {}
    hook.Remove("CalcView", HOOK_NAME)
end
