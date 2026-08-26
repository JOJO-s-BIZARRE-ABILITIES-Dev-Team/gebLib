gebLib.Visuals = gebLib.Visuals or {}
local Visuals = gebLib.Visuals

local loadInternal = include or function(path)
    return assert(loadfile("lua/" .. path))()
end

local Runtime = gebLib._Runtime or loadInternal("geblib/runtime.lua")
local Surface = loadInternal("geblib/visuals/surface.lua")
Visuals.RockDebrisModels = Surface.RockModels

if Visuals.ClearDebrisBatches then Visuals.ClearDebrisBatches() end

loadInternal("geblib/visuals/decal.lua")(Visuals)

local DebrisRuntime = loadInternal("geblib/visuals/runtime.lua")(Visuals)
local Profile = loadInternal("geblib/visuals/profile.lua")(Visuals, function()
    return DebrisRuntime.Heap
end)
DebrisRuntime.SetProfile(Profile)

local Batch = loadInternal("geblib/visuals/debris_batch.lua")(
    Visuals,
    Runtime,
    Surface,
    Profile
)

loadInternal("geblib/visuals/particles.lua")(Visuals, Profile)
loadInternal("geblib/visuals/impact.lua")(Visuals, Surface, Profile, Batch)
loadInternal("geblib/visuals/wave.lua")(Visuals, Runtime, Surface, Profile, Batch)
