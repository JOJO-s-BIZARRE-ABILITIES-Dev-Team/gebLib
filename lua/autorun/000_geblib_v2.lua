-- Developed by T0M and jopster1336

gebLib = gebLib or {}
gebLib.Version = "3.2.0"
gebLib.Loaded = false

if game and game.AddParticles then game.AddParticles("particles/geblib_debris.pcf") end
if SERVER and PrecacheParticleSystem then PrecacheParticleSystem("geblib_debris_smoke") end

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
    "geblib/runtime.lua",
    "geblib/math.lua",
    "geblib/combat.lua",
    "geblib/net.lua",
    "geblib/entities.lua",
    "geblib/camera.lua",
    "geblib/status_effects.lua",
    "geblib/chat.lua",
    "geblib/player_animation.lua",
    "geblib/sound.lua",
}

local clientFiles = {
    "geblib/drawing.lua",
    "geblib/visuals.lua",
    "geblib/visual_batches.lua",
    "geblib/bone_controllers.lua",
    "geblib/bone_matrix_modifiers.lua",
    "geblib/player_replica.lua",
    "geblib/replica_trail.lua",
    "geblib/camera_modifiers.lua",
    "geblib/camera_impulses.lua",
    "geblib/particle_emitters.lua",
    "geblib/audio.lua",
    "geblib/impact_frames.lua",
}

local supportFiles = {
    "geblib/net_codecs.lua",
    "geblib/net_profile.lua",
    "geblib/impact_frames_render.lua",
    "geblib/visuals_surface.lua",
    "geblib/visuals_config.lua",
    "geblib/visuals_runtime.lua",
    "geblib/visuals_profile.lua",
    "geblib/visuals_wave.lua",
    "geblib/visuals_decal.lua",
}

if SERVER then
    for _, path in ipairs(sharedFiles) do
        AddCSLuaFile(path)
    end

    for _, path in ipairs(clientFiles) do
        AddCSLuaFile(path)
    end

    for _, path in ipairs(supportFiles) do
        AddCSLuaFile(path)
    end
end

for _, path in ipairs(sharedFiles) do
    include(path)
end

if SERVER then include("geblib/visuals_surface.lua") end

if CLIENT then
    for _, path in ipairs(clientFiles) do
        include(path)
    end
end

-- TODO: Figure out if gmod implemented a proper player connected hook, it has been like 4 years since this was coded in
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

gebLib.Loaded = true
hook.Run("gebLib.Loaded", gebLib)
