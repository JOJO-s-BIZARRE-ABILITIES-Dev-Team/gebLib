local Surface = {}

local ROCK_MODELS = {
    "models/props_debris/physics_debris_rock1.mdl",
    "models/props_debris/physics_debris_rock2.mdl",
    "models/props_debris/physics_debris_rock3.mdl",
    "models/props_debris/physics_debris_rock4.mdl",
    "models/props_debris/physics_debris_rock5.mdl",
    "models/props_debris/physics_debris_rock6.mdl",
    "models/props_debris/physics_debris_rock7.mdl",
    "models/props_debris/physics_debris_rock8.mdl",
    "models/props_debris/physics_debris_rock9.mdl",
    "models/props_debris/physics_debris_rock10.mdl",
    "models/props_debris/physics_debris_rock11.mdl",
}

local METAL_MODELS = {
    "models/props_debris/metal_panelshard01a.mdl",
    "models/props_debris/metal_panelshard01b.mdl",
    "models/props_debris/metal_panelshard01c.mdl",
    "models/props_debris/metal_panelshard01d.mdl",
}

local ANTLION_MODELS = {
    "models/gibs/antlion_gib_medium_1.mdl",
    "models/gibs/antlion_gib_medium_2.mdl",
    "models/gibs/antlion_gib_medium_3.mdl",
    "models/gibs/antlion_gib_medium_3a.mdl",
    "models/gibs/antlion_gib_small_1.mdl",
    "models/gibs/antlion_gib_small_2.mdl",
    "models/gibs/antlion_gib_small_3.mdl",
}

Surface.RockModels = ROCK_MODELS

if util and util.PrecacheModel then
    local sets = {ROCK_MODELS, METAL_MODELS, ANTLION_MODELS}
    for setIndex = 1, #sets do
        for modelIndex = 1, #sets[setIndex] do
            util.PrecacheModel(sets[setIndex][modelIndex])
        end
    end
end

local cachedMaterials = {}
local traceResult = {}
local traceData = {
    mask = MASK_VISIBLE,
    output = traceResult,
}

function Surface.NormalizeMaterial(materialType)
    if materialType == MAT_TILE or materialType == MAT_DEFAULT then return MAT_CONCRETE end
    if materialType == MAT_GRASS then return MAT_DIRT end
    if materialType == MAT_BLOODYFLESH then return MAT_FLESH end
    if materialType == MAT_GRATE or materialType == MAT_COMPUTER then return MAT_METAL end
    return materialType
end

function Surface.Models(materialType)
    if materialType == MAT_METAL then return METAL_MODELS end
    if materialType == MAT_ANTLION then return ANTLION_MODELS end
    return ROCK_MODELS
end

function Surface.PhysicsMaterial(materialType)
    if materialType == MAT_METAL then return "metal" end
    if materialType == MAT_ANTLION or materialType == MAT_FLESH then return "flesh" end
    if materialType == MAT_DIRT then return "dirt" end
    return "concrete"
end

function Surface.Color(materialType)
    if materialType == MAT_SLOSH then return {r = 205, g = 235, b = 255, a = 235} end
    if materialType == MAT_DIRT then return {r = 104, g = 83, b = 58, a = 255} end
    if materialType == MAT_METAL then return {r = 150, g = 155, b = 160, a = 255} end
    if materialType == MAT_ANTLION or materialType == MAT_FLESH then
        return {r = 185, g = 145, b = 55, a = 255}
    end
    return {r = 145, g = 140, b = 130, a = 255}
end

local function validTexture(path)
    if type(path) ~= "string" or path == "" then return false end
    local lowered = string.lower(path)
    if lowered == "**empty**" or lowered == "**displacement**" or lowered == "**studio**" then
        return false
    end
    return string.sub(lowered, 1, 5) ~= "tools"
end

function Surface.MaterialAt(position, normal, hitTexture, materialType, allowTrace)
    if not validTexture(hitTexture) and allowTrace ~= false then
        traceData.start = position + normal * 24
        traceData.endpos = position - normal * 96
        util.TraceLine(traceData)
        hitTexture = traceResult.HitTexture
        materialType = traceResult.MatType
    end

    materialType = Surface.NormalizeMaterial(materialType or MAT_CONCRETE)
    if materialType == MAT_SLOSH then return nil, materialType end
    if not validTexture(hitTexture) then return nil, materialType end

    local cached = cachedMaterials[hitTexture]
    if cached ~= nil then return cached or nil, materialType end

    local source = Material(hitTexture)
    local texture = source and source:GetTexture("$basetexture")
    local textureName = texture and texture:GetName()
    if not textureName or textureName == "" then
        cachedMaterials[hitTexture] = false
        return nil, materialType
    end

    local name = "geblib_debris_surface_" .. util.CRC(textureName)
    CreateMaterial(name, "VertexLitGeneric", {
        ["$basetexture"] = textureName,
        ["$model"] = "1",
    })

    cached = "!" .. name
    cachedMaterials[hitTexture] = cached
    return cached, materialType
end

function Surface.Model(materialType)
    local models = Surface.Models(Surface.NormalizeMaterial(materialType or MAT_CONCRETE))
    return models[math.random(1, #models)]
end

return Surface
