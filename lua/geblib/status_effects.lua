local Entity = FindMetaTable("Entity")

local StatusEffects = gebLib.StatusEffects or {}
gebLib.StatusEffects = StatusEffects

local Runtime = gebLib._Runtime
if not Runtime then
    local loader = include or function(path) return assert(loadfile("lua/" .. path))() end
    Runtime = loader("geblib/runtime.lua")
end

local state = gebLib._StatusEffectsState or {
    definitions = {},
    definitionViews = setmetatable({}, {__mode = "k"}),
    entityEffects = setmetatable({}, {__mode = "k"}),
    activeEntities = setmetatable({}, {__mode = "k"}),
    effectDefinitions = setmetatable({}, {__mode = "k"}),
}
gebLib._StatusEffectsState = state

local definitions = state.definitions
local definitionViews = state.definitionViews
local entityEffects = state.entityEffects
local activeEntities = state.activeEntities
local effectDefinitions = state.effectDefinitions

local function validateDefinition(name, definition)
    if not isstring(name) or name == "" then
        error("status effect name must be a non-empty string", 3)
    end
    if not istable(definition) then
        error("status effect definition must be a table", 3)
    end

    local callbacks = {"onApply", "onTick", "onReapply", "onRemove"}
    for index = 1, #callbacks do
        local callbackName = callbacks[index]
        local callback = definition[callbackName]
        if callback ~= nil and not isfunction(callback) then
            error(callbackName .. " must be a function", 3)
        end
    end

    if definition.interval ~= nil
        and (not isnumber(definition.interval) or definition.interval < 0)
    then
        error("status effect interval must be zero or greater", 3)
    end
end

local function ownDefinition(definition)
    local owned = {}
    for key, value in pairs(definition) do owned[key] = value end
    if owned.interval == nil then owned.interval = 1 end
    return owned
end

local function viewDefinition(definition)
    local view = definitionViews[definition]
    if view then return view end

    view = setmetatable({}, {
        __index = definition,
        __newindex = function()
            error("status effect definitions are immutable after registration", 2)
        end,
        __metatable = false,
    })
    definitionViews[definition] = view
    return view
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
    local effects = entityEffects[entity]
    if effects or not create then return effects end

    effects = {}
    entityEffects[entity] = effects
    activeEntities[entity] = true
    return effects
end

local removeEffect

local function runEffectCallback(effect, callbackName, ...)
    local definition = effectDefinitions[effect]
    local callback = definition and definition[callbackName]
    if not callback then return true end

    return Runtime.Invoke(
        effect,
        "Applied Status Effect " .. tostring(effect.name) .. " " .. callbackName,
        callback,
        function(current)
            if current.target then removeEffect(current.target, current.name, "callback error") end
        end,
        ...
    )
end

removeEffect = function(entity, name, reason)
    local effects = effectMap(entity, false)
    local effect = effects and effects[name]
    if not effect or effect.removing then return false end

    effect.removing = true
    effects[name] = nil

    if next(effects) == nil then
        entityEffects[entity] = nil
        activeEntities[entity] = nil
    end

    local definition = effectDefinitions[effect]
    effectDefinitions[effect] = nil
    if definition and definition.onRemove then
        Runtime.Invoke(
            effect,
            "Applied Status Effect " .. tostring(name) .. " onRemove",
            definition.onRemove,
            nil,
            entity,
            effect,
            reason or "removed"
        )
    end

    return true
end

function StatusEffects.Register(name, definition)
    validateDefinition(name, definition)
    local owned = ownDefinition(definition)
    definitions[name] = owned
    return viewDefinition(owned)
end

function StatusEffects.Get(name)
    local definition = definitions[name]
    return definition and viewDefinition(definition) or nil
end

function StatusEffects.Unregister(name)
    definitions[name] = nil
end

function Entity:gebLib_ApplyStatusEffect(name, duration, level, source, inflictor)
    local definition = definitions[name]
    if not definition then error("unknown status effect: " .. tostring(name), 2) end
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
        local currentDefinition = effectDefinitions[current]
        local handled = false
        if currentDefinition and currentDefinition.onReapply then
            local ok, callbackHandled = runEffectCallback(
                current,
                "onReapply",
                self,
                current,
                duration,
                level,
                source,
                inflictor
            )
            if not ok then return effects[name] end
            handled = callbackHandled == true
        end
        if handled then return effects[name] end
        if effects[name] ~= current then return effects[name] end

        if level < current.level then return current end
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

    local effect = {
        name = name,
        target = self,
        source = source,
        inflictor = inflictor,
        level = level,
        appliedAt = now,
        expiresAt = duration == math.huge and math.huge or now + duration,
        nextTickAt = now + definition.interval,
    }

    effects[name] = effect
    effectDefinitions[effect] = definition

    if definition.onApply then
        local ok = runEffectCallback(effect, "onApply", self, effect)
        if not ok then return effects[name] end
    end
    if effects[name] ~= effect then return effects[name] end

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
    local snapshot = {}
    local effects = effectMap(self, false)
    if effects then
        for name, effect in pairs(effects) do snapshot[name] = effect end
    end
    return snapshot
end

function Entity:gebLib_HasStatusEffect(name)
    return self:gebLib_GetStatusEffect(name) ~= nil
end

function Entity:gebLib_ClearStatusEffects(reason)
    local effects = effectMap(self, false)
    if not effects then return 0 end

    local names = {}
    for name in pairs(effects) do names[#names + 1] = name end

    local removed = 0
    for index = 1, #names do
        if removeEffect(self, names[index], reason or "cleared") then removed = removed + 1 end
    end
    return removed
end

hook.Add("Tick", "gebLib.StatusEffects", function()
    local now = CurTime()

    for entity in pairs(activeEntities) do
        local effects = effectMap(entity, false)
        if not IsValid(entity) then
            activeEntities[entity] = nil
            entityEffects[entity] = nil
        elseif effects then
            local names = {}
            for name in pairs(effects) do names[#names + 1] = name end

            for index = 1, #names do
                local name = names[index]
                local effect = effects[name]
                if effect then
                    if not isAlive(entity) then
                        removeEffect(entity, name, "death")
                    elseif now >= effect.expiresAt then
                        removeEffect(entity, name, "expired")
                    elseif now >= effect.nextTickAt then
                        local definition = effectDefinitions[effect]
                        if definition then
                            effect.nextTickAt = definition.interval == 0 and now or now + definition.interval
                            runEffectCallback(effect, "onTick", entity, effect)
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
