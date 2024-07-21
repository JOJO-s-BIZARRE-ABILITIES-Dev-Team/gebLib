local inext = ipairs({})

local entityCache = nil
local playerCache = nil

function ents.Pairs()
	if not entityCache then entityCache = ents.GetAll() end
	return inext, entityCache, 0
end

function player.Pairs()
	if not playerCache then playerCache = player.GetAll() end
	return inext, playerCache, 0
end

hook.Add("OnEntityCreated", "gebLib.cache.EntityCache", function(ent)
	entityCache = nil
	playerCache = nil
end)

hook.Add("EntityRemoved", "gebLib.cache.EntityCache", function(ent)
	entityCache = nil
	playerCache = nil
end)
