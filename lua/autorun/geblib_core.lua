// Developed by T0M and jopster1336
--------------------------
//
gebLib = {}
gebLib.Version = "0.0.0"
//
--------------------------
function gebLib.PrintDebug(...) -- Equivalent to print(), however prints only if gebLib_developer_debugmode is on 
    if !gebLib.DebugMode() then return end
    print("[gebLib Debug]", unpack({...}))
end

function gebLib.ImportFile( filePath, clientOnly )
	AddCSLuaFile( filePath )
	if !clientOnly or ( clientOnly and CLIENT ) then
		include( filePath )
	end
end
--------------------------
local includes = "includes/"
local modules = includes .. "modules/"
local iderma = includes .. "derma/"
--------------------------
gebLib.ImportFile( includes .. "geblib_globals.lua" )
gebLib.ImportFile( includes .. "geblib_enums.lua" )
gebLib.ImportFile( includes .. "geblib_utilities.lua" )
gebLib.ImportFile( includes .. "geblib_cache.lua" )
gebLib.ImportFile( includes .. "geblib_network.lua" )
gebLib.ImportFile( includes .. "geblib_animation.lua" )
gebLib.ImportFile( includes .. "geblib_camera.lua" )
gebLib.ImportFile( includes .. "geblib_statuseffect.lua" )
gebLib.ImportFile( includes .. "geblib_powerlevels.lua" )
gebLib.ImportFile( includes .. "gebLib_sound.lua" )
--------------------------
//
--------------------------
// DEBUGGING
CreateConVar( "geblib_developer_debugmode", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_PROTECTED }, "[DEVELOPER] Debug Mode" )
CreateConVar( "geblib_developer_debugnetwork", 0, { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_PROTECTED }, "[DEVELOPER] Displays network debug messages" )

function gebLib.DebugMode()
	return GetConVar("geblib_developer_debugmode"):GetBool()
end

function gebLib.NetworkDebug()
	return GetConVar("geblib_developer_debugnetwork"):GetBool()
end
--------------------------
// 

// For some reason i enjoy making these frames for chunks of code

-- Player connnection handling
if SERVER then
    local playersConnected = {}
    gameevent.Listen("OnRequestFullUpdate")

    hook.Add("OnRequestFullUpdate", "gebLib_InitialConnect", function(data)
        if not playersConnected[data.userid] then
            playersConnected[data.userid] = true
            -- Needs to be run on the next tick, because this runs slighty before client stage, so we cannot send net messages to players
            timer.Simple(0, function()
                hook.Run("gebLib_PlayerFullyConnected", Player(data.userid))
            end)
        end
    end)
end

if CLIENT then
    hook.Add("InitPostEntity", "gebLib_InitialConnect", function()
        hook.Run("gebLib_PlayerFullyConnected", LocalPlayer())
    end)
end
