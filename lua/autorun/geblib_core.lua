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

function gebLib.ImportFile(filePath)
	AddCSLuaFile(filePath)
	include(filePath)
end
--------------------------
local includes = "includes/"
local modules = includes .. "modules/"
--------------------------
gebLib.ImportFile( modules .. "print.lua" )
gebLib.ImportFile( includes .. "geblib_enums.lua" )
gebLib.ImportFile( includes .. "geblib_utilities.lua" )
gebLib.ImportFile( includes .. "geblib_cache.lua" )
gebLib.ImportFile( includes .. "geblib_network.lua" )
gebLib.ImportFile( includes .. "geblib_animation.lua" )
gebLib.ImportFile( includes .. "geblib_camera.lua" )
gebLib.ImportFile( includes .. "geblib_statuseffect.lua" )
gebLib.ImportFile( includes .. "geblib_powerlevels.lua" )
--------------------------
//
--------------------------
// DEBUGGING
CreateConVar( "geblib_developer_debugmode", 0, { FCVAR_CHEAT, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_PROTECTED }, "[DEVELOPER] Debug Mode" )
CreateConVar( "geblib_developer_debugnetwork", 0, { FCVAR_CHEAT, FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_PROTECTED }, "[DEVELOPER] Displays network debug messages" )

function gebLib.DebugMode()
	return GetConVar("geblib_developer_debugmode"):GetInt() == 1
end

function gebLib.NetworkDebug()
	return GetConVar("geblib_developer_debugnetwork"):GetInt() == 1
end
--------------------------
// 

// For some reason i enjoy making these frames for chunks of code
