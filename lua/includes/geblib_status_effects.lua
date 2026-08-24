local Entity = FindMetaTable("Entity")

local StatusEffects = gebLib.StatusEffects or {}
gebLib.StatusEffects = StatusEffects

StatusEffects.Definitions = StatusEffects.Definitions or {}
StatusEffects.ActiveEntities = StatusEffects.ActiveEntities or setmetatable({}, {__mode = "k"})

local definitions = StatusEffects.Definitions
local activeEntities = StatusEffects.ActiveEntities

local function validateDefinition(name, definition)
    if not isstring(name) or name == "" then
        error("status effect name must be a non-empty string", 3)
    end

    if not istable(definition) then
        error("status effect definition must be a table", 3)
    end

    local callbacks = {"onApply", "onTick", "onReapply", "onRemove"}
    for _, callbackName in ipairs(callbacks) do
        local callback = definition[callbackName]
        if callback ~= nil and not isfunction(callback) then
            error(callbackName .. " must be a function", 3)
        end
    end

    if definition.interval ~= nil then
        if not isnumber(definition.interval) or definition.interval < 0 then
            error("status effect interval must be zero or greater", 3)
        end
    end
end

local function isLivingEntity(entity)
    return IsValid(entity) and (entity:IsPlayer() or entity:IsNPC() or entity:IsNextBot())
end

local function isAlive(entity)
    if not isLivingEntity(entity) then return false end
    if entity:IsPlayer() then return entity:Alive() end
    return entity:Health() > 0
end

local function effectMap(entity, create)
    local effects = entity.gebLib_StatusEffects
    if effects or not create then return effects end

    effects = {}
    entity.gebLib_StatusEffects = effects
    activeEntities[entity] = true
    return effects
end

local function removeEffect(entity, name, reason)
    local effects = effectMap(entity, false)
    local effect = effects and effects[name]
    if not effect or effect.removing then return false end

    effect.removing = true
    effects[name] = nil

    if next(effects) == nil then
        entity.gebLib_StatusEffects = nil
        activeEntities[entity] = nil
    end

    local onRemove = effect.definition.onRemove
    if onRemove then
        onRemove(entity, effect, reason or "removed")
    end

    return true
end

function StatusEffects.Register(name, definition)
    validateDefinition(name, definition)
    definitions[name] = definition
    return definition
end

function StatusEffects.Get(name)
    return definitions[name]
end

function StatusEffects.Unregister(name)
    definitions[name] = nil
end

function Entity:gebLib_ApplyStatusEffect(name, duration, level, source, inflictor)
    local definition = definitions[name]
    if not definition then
        error("unknown status effect: " .. tostring(name), 2)
    end

    if not isLivingEntity(self) then
        error("status effects can only be applied to living entities", 2)
    end

    duration = duration or 0
    level = level or 1

    if not isnumber(duration) or duration < 0 then
        error("status effect duration must be zero or greater", 2)
    end

    if not isnumber(level) or level < 1 then
        error("status effect level must be one or greater", 2)
    end

    local now = CurTime()
    local effects = effectMap(self, true)
    local current = effects[name]

    if current then
        local onReapply = definition.onReapply
        if onReapply and onReapply(self, current, duration, level, source, inflictor) then
            return effects[name]
        end

        if effects[name] ~= current then
            return effects[name]
        end

        if level < current.level then
            return current
        end

        if level == current.level then
            local newExpiration = duration == math.huge and math.huge or now + duration
            if newExpiration > current.expiresAt then
                current.expiresAt = newExpiration
                current.source = source
                current.inflictor = inflictor
            end
            return current
        end

        removeEffect(self, name, "replaced")
        effects = effectMap(self, true)
        if effects[name] then return effects[name] end
    end

    local interval = definition.interval
    if interval == nil then interval = 1 end

    local effect = {
        name = name,
        target = self,
        source = source,
        inflictor = inflictor,
        level = level,
        appliedAt = now,
        expiresAt = duration == math.huge and math.huge or now + duration,
        nextTickAt = now + interval,
        definition = definition,
    }

    effects[name] = effect

    if definition.onApply then
        definition.onApply(self, effect)
    end

    if effects[name] ~= effect then
        return effects[name]
    end

    if duration == 0 then
        removeEffect(self, name, "expired")
        return nil
    end

    return effect
end

function Entity:gebLib_RemoveStatusEffect(name, reason)
    return removeEffect(self, name, reason)
end

function Entity:gebLib_GetStatusEffect(name)
    local effects = effectMap(self, false)
    return effects and effects[name] or nil
end

function Entity:gebLib_GetStatusEffects()
    return effectMap(self, false) or {}
end

function Entity:gebLib_HasStatusEffect(name)
    return self:gebLib_GetStatusEffect(name) ~= nil
end

function Entity:gebLib_ClearStatusEffects(reason)
    local effects = effectMap(self, false)
    if not effects then return 0 end

    local names = {}
    for name in pairs(effects) do
        names[#names + 1] = name
    end

    local removed = 0
    for _, name in ipairs(names) do
        if removeEffect(self, name, reason or "cleared") then
            removed = removed + 1
        end
    end

    return removed
end

hook.Add("Tick", "gebLib.StatusEffects", function()
    local now = CurTime()

    for entity in pairs(activeEntities) do
        local effects = effectMap(entity, false)

        if not IsValid(entity) then
            activeEntities[entity] = nil
        elseif effects then
            local names = {}
            for name in pairs(effects) do
                names[#names + 1] = name
            end

            for _, name in ipairs(names) do
                local effect = effects[name]

                if effect then
                    if not isAlive(entity) then
                        removeEffect(entity, name, "death")
                    elseif now >= effect.expiresAt then
                        removeEffect(entity, name, "expired")
                    else
                        local onTick = effect.definition.onTick
                        if onTick and now >= effect.nextTickAt then
                            local interval = effect.definition.interval
                            if interval == nil then interval = 1 end

                            effect.nextTickAt = interval == 0 and now or now + interval
                            onTick(entity, effect)
                        end
                    end
                end
            end
        end
    end
end)

hook.Add("EntityRemoved", "gebLib.StatusEffects", function(entity)
    entity:gebLib_ClearStatusEffects("entity removed")
end)

hook.Add("PlayerDeath", "gebLib.StatusEffects", function(player)
    player:gebLib_ClearStatusEffects("death")
end)
