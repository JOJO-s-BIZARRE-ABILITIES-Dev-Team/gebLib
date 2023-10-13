// Developed by T0M and jopster1336
--------------------------
//
gebLib = {}
gebLib.Version = "0.0.0"
gebLib.Build   = "0"
//
--------------------------
--TODO: make this work with varargs
function gebLib.PrintDebug( string ) -- Equivalent to print(), however prints only if gebLib_developer_debugmode is on 
    if !gebLib.DebugMode() then return end
    string = tostring(string)
    print( "[gebLib Debug] " .. string )
end
--------------------------
local includes = "includes/"
--------------------------
--Once these files are not empty then commment them out, but as of now, they cause errors on include
--include( includes .. "geblib_utilities.lua" )
include( includes .. "geblib_network.lua" )
--include( includes .. "geblib_animation.lua" )
--include( includes .. "geblib_camera.lua" )
--include( includes .. "geblib_cinematics.lua" )
--include( includes .. "geblib_statuseffects.lua" )
--------------------------
if SERVER then
    --AddCSLuaFile( includes .. "geblib_utilities.lua" )
    AddCSLuaFile( includes .. "geblib_network.lua" )
   -- AddCSLuaFile( includes .. "geblib_animation.lua" )
    --AddCSLuaFile( includes .. "geblib_camera.lua" )
    --AddCSLuaFile( includes .. "geblib_cinematics.lua" )
    --AddCSLuaFile( includes .. "geblib_statuseffects.lua" )
end
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