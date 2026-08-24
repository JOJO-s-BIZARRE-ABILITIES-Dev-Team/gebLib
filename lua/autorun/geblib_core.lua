-- Developed by T0M and jopster1336

gebLib = gebLib or {}
gebLib.Version = "2.0.0"

CreateConVar(
    "geblib_developer_debugmode",
    "0",
    {FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_PROTECTED},
    "Enable gebLib debug messages"
)

function gebLib.DebugMode()
    return GetConVar("geblib_developer_debugmode"):GetBool()
end

function gebLib.PrintDebug(...)
    if not gebLib.DebugMode() then return end
    print("[gebLib]", ...)
end

local sharedFiles = {
    "includes/geblib_entities.lua",
    "includes/geblib_action.lua",
    "includes/geblib_animation.lua",
    "includes/geblib_camera.lua",
    "includes/geblib_status_effects.lua",
    "includes/geblib_chat.lua",
    "includes/geblib_player_animation.lua",
    "includes/geblib_sound.lua",
}

local clientFiles = {
    "includes/geblib_drawing.lua",
    "includes/geblib_visuals.lua",
}

if SERVER then
    for _, path in ipairs(sharedFiles) do
        AddCSLuaFile(path)
    end

    for _, path in ipairs(clientFiles) do
        AddCSLuaFile(path)
    end
end

for _, path in ipairs(sharedFiles) do
    include(path)
end

if CLIENT then
    for _, path in ipairs(clientFiles) do
        include(path)
    end
end

if SERVER then
    local connectedPlayers = {}

    gameevent.Listen("OnRequestFullUpdate")

    hook.Add("OnRequestFullUpdate", "gebLib.PlayerFullyConnected", function(data)
        local userId = data.userid
        if connectedPlayers[userId] then return end

        connectedPlayers[userId] = true

        timer.Simple(0, function()
            local player = Player(userId)
            if not IsValid(player) or player:UserID() ~= userId then
                connectedPlayers[userId] = nil
                return
            end

            hook.Run("gebLib.PlayerFullyConnected", player)
        end)
    end)

    hook.Add("PlayerDisconnected", "gebLib.PlayerFullyConnected", function(player)
        connectedPlayers[player:UserID()] = nil
    end)
else
    hook.Add("InitPostEntity", "gebLib.PlayerFullyConnected", function()
        hook.Run("gebLib.PlayerFullyConnected", LocalPlayer())
    end)
end
