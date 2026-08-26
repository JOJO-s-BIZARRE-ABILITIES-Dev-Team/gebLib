local bootstrapPath = "lua/autorun/000_geblib_v2.lua"

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function runBootstrap(server, failingPath)
    local included = {}
    local sent = {}
    local addedHooks = {}
    local runHooks = {}

    SERVER = server
    CLIENT = not server
    FCVAR_REPLICATED = 1
    FCVAR_ARCHIVE = 2
    FCVAR_PROTECTED = 4
    gebLib = nil

    function CreateConVar() end
    function GetConVar()
        return {GetBool = function() return false end}
    end

    function AddCSLuaFile(path)
        sent[#sent + 1] = path
    end

    function include(path)
        assertEqual(gebLib.Loaded, false, "library must stay unavailable while modules load")
        if path == failingPath then error("injected include failure") end
        included[#included + 1] = path
    end

    gameevent = {Listen = function() end}
    timer = {Simple = function() end}

    hook = {}
    function hook.Add(eventName, hookName, callback)
        addedHooks[eventName] = {name = hookName, callback = callback}
    end
    function hook.Run(eventName, ...)
        runHooks[#runHooks + 1] = {name = eventName, arguments = {...}}
    end

    local ok, loadError = pcall(assert(loadfile(bootstrapPath)))
    return ok, loadError, included, sent, addedHooks, runHooks
end

do
    local ok, _, included, sent, addedHooks, runHooks = runBootstrap(true)

    assertEqual(ok, true, "server bootstrap should load")
    assertEqual(#included, 11, "server should include shared modules and debris precaching")
    assertEqual(#sent, 31, "server should send shared, client, and support modules")
    assertEqual(included[1], "geblib/runtime.lua", "shared runtime should load first")
    assertEqual(included[2], "geblib/math.lua", "math helpers should load before combat")
    assertEqual(included[3], "geblib/combat.lua", "combat should load before addon code")
    assertEqual(included[4], "geblib/net.lua", "network module should precede gameplay modules")
    assertEqual(included[5], "geblib/entities.lua", "first gameplay module")
    assertEqual(included[10], "geblib/sound.lua", "last shared gameplay module")
    assertEqual(included[11], "geblib/visuals_surface.lua", "server debris model precaching")
    assertEqual(sent[11], "geblib/drawing.lua", "first client module sent")
    assertEqual(sent[12], "geblib/visuals.lua", "client visual facade sent")
    assertEqual(sent[22], "geblib/impact_frames.lua", "last client module sent")
    assertEqual(sent[23], "geblib/net_codecs.lua", "network codecs should be sent as support code")
    assertEqual(sent[24], "geblib/net_profile.lua", "network profile should be sent as support code")
    assertEqual(sent[25], "geblib/impact_frames_render.lua", "impact-frame renderer support")
    assertEqual(sent[31], "geblib/visuals_decal.lua", "last client support module sent")
    assertEqual(addedHooks.OnRequestFullUpdate.name, "gebLib.PlayerFullyConnected", "server connection hook")
    assertEqual(gebLib.Loaded, true, "server bootstrap should publish readiness")
    assertEqual(#runHooks, 1, "server should publish readiness once")
    assertEqual(runHooks[1].name, "gebLib.Loaded", "readiness event name")
    assertEqual(runHooks[1].arguments[1], gebLib, "readiness event library")
end

do
    local ok, _, included, sent, addedHooks, runHooks = runBootstrap(false)

    assertEqual(ok, true, "client bootstrap should load")
    assertEqual(#included, 22, "client should include shared and client modules")
    assertEqual(#sent, 0, "client should not send Lua files")
    assertEqual(included[11], "geblib/drawing.lua", "first client module included")
    assertEqual(included[12], "geblib/visuals.lua", "visual facade included")
    assertEqual(included[22], "geblib/impact_frames.lua", "last client module included")
    assertEqual(addedHooks.InitPostEntity.name, "gebLib.PlayerFullyConnected", "client connection hook")
    assertEqual(gebLib.Loaded, true, "client bootstrap should publish readiness")
    assertEqual(runHooks[1].name, "gebLib.Loaded", "client readiness event")
end

do
    local ok, loadError, _, _, _, runHooks = runBootstrap(true, "geblib/camera.lua")

    assertEqual(ok, false, "module failure should fail the bootstrap")
    assert(loadError:find("injected include failure", 1, true), "bootstrap should preserve the include error")
    assertEqual(gebLib.Loaded, false, "failed bootstrap must remain unavailable")
    assertEqual(#runHooks, 0, "failed bootstrap must not publish readiness")
end

print("bootstrap: ok")
