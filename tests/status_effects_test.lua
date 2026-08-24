local failures = 0
local now = 0
local hooks = {}

local function fail(message)
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then fail(message or "expected truthy value") end
end

function isstring(value) return type(value) == "string" end
function istable(value) return type(value) == "table" end
function isfunction(value) return type(value) == "function" end
function isnumber(value) return type(value) == "number" end
function CurTime() return now end
function IsValid(entity) return type(entity) == "table" and entity.valid == true end

hook = {}
function hook.Add(event, name, callback)
    hooks[event] = hooks[event] or {}
    hooks[event][name] = callback
end

local function runHook(event, ...)
    for _, callback in pairs(hooks[event] or {}) do
        callback(...)
    end
end

local Entity = {}
Entity.__index = Entity

function FindMetaTable(name)
    assertEqual(name, "Entity", "unexpected metatable lookup")
    return Entity
end

function Entity:IsPlayer() return self.kind == "player" end
function Entity:IsNPC() return self.kind == "npc" end
function Entity:IsNextBot() return self.kind == "nextbot" end
function Entity:Alive() return self.alive end
function Entity:Health() return self.health end

local function newEntity(kind)
    return setmetatable({
        valid = true,
        alive = true,
        health = 100,
        kind = kind or "player",
    }, Entity)
end

SERVER = true
CLIENT = false
gebLib = {}

dofile("lua/geblib/status_effects.lua")

do
    local events = {}
    local target = newEntity()
    local firstSource = {}
    local secondSource = {}

    gebLib.StatusEffects.Register("poison", {
        interval = 1,
        onApply = function(_, effect)
            events[#events + 1] = "apply:" .. effect.level
        end,
        onTick = function()
            events[#events + 1] = "tick"
        end,
        onRemove = function(_, _, reason)
            events[#events + 1] = "remove:" .. reason
        end,
    })

    local effect = target:gebLib_ApplyStatusEffect("poison", 10, 1, firstSource)
    assertTrue(effect ~= nil, "initial application should return the applied effect")
    assertEqual(effect.expiresAt, 10, "initial expiration")
    assertEqual(events[1], "apply:1", "initial apply callback")

    now = 0.5
    runHook("Tick")
    assertEqual(#events, 1, "effect should not tick before its interval")

    now = 1
    runHook("Tick")
    assertEqual(events[2], "tick", "effect should tick at its interval")

    local same = target:gebLib_ApplyStatusEffect("poison", 3, 1, secondSource)
    assertEqual(same, effect, "same-level reapplication should retain the instance")
    assertEqual(effect.expiresAt, 10, "shorter reapplication should not shorten the effect")
    assertEqual(effect.source, firstSource, "ignored reapplication should not replace the source")

    target:gebLib_ApplyStatusEffect("poison", 20, 1, secondSource)
    assertEqual(effect.expiresAt, 21, "longer reapplication should refresh expiration")
    assertEqual(effect.source, secondSource, "accepted reapplication should replace the source")

    local stronger = target:gebLib_ApplyStatusEffect("poison", 5, 2, firstSource)
    assertTrue(stronger ~= effect, "stronger application should create a new instance")
    assertEqual(events[#events - 1], "remove:replaced", "stronger application should remove the old effect")
    assertEqual(events[#events], "apply:2", "stronger application should apply the new effect")

    local ignored = target:gebLib_ApplyStatusEffect("poison", 100, 1, secondSource)
    assertEqual(ignored, stronger, "weaker application should be ignored")
    assertEqual(stronger.level, 2, "weaker application should not change level")
end

do
    local target = newEntity("npc")

    gebLib.StatusEffects.Register("bleeding", {
        onReapply = function(_, effect, duration)
            effect.stacks = (effect.stacks or 1) + 1
            effect.expiresAt = effect.expiresAt + duration
            return true
        end,
    })

    now = 0
    local effect = target:gebLib_ApplyStatusEffect("bleeding", 4)
    local reapplied = target:gebLib_ApplyStatusEffect("bleeding", 3)

    assertEqual(reapplied, effect, "custom reapplication should retain the instance")
    assertEqual(effect.stacks, 2, "custom reapplication should control stack state")
    assertEqual(effect.expiresAt, 7, "custom reapplication should control duration")
end

do
    local removed = 0
    local target = newEntity()

    gebLib.StatusEffects.Register("self_removing", {
        interval = 0,
        onTick = function(entity)
            entity:gebLib_RemoveStatusEffect("self_removing", "tick callback")
        end,
        onRemove = function()
            removed = removed + 1
        end,
    })

    now = 0
    target:gebLib_ApplyStatusEffect("self_removing", 10)
    runHook("Tick")
    runHook("Tick")

    assertTrue(not target:gebLib_HasStatusEffect("self_removing"), "tick callback should be able to remove itself")
    assertEqual(removed, 1, "self-removal should run onRemove once")
end

do
    local reason
    local target = newEntity()

    gebLib.StatusEffects.Register("short", {
        onRemove = function(_, _, removeReason)
            reason = removeReason
        end,
    })

    now = 10
    target:gebLib_ApplyStatusEffect("short", 2)
    now = 12
    runHook("Tick")

    assertTrue(not target:gebLib_HasStatusEffect("short"), "expired effect should be removed")
    assertEqual(reason, "expired", "expiration reason")
end

do
    local target = newEntity()
    gebLib.StatusEffects.Register("stun", {})
    target:gebLib_ApplyStatusEffect("stun", 20)
    target.alive = false
    runHook("Tick")
    assertTrue(not target:gebLib_HasStatusEffect("stun"), "death should clear active effects")
end

do
    local removed = 0
    local target = newEntity()

    gebLib.StatusEffects.Register("cleanup", {
        onRemove = function() removed = removed + 1 end,
    })

    target:gebLib_ApplyStatusEffect("cleanup", 20)
    runHook("EntityRemoved", target)
    assertEqual(removed, 1, "entity removal should call effect cleanup")
    assertEqual(target.gebLib_StatusEffects, nil, "entity removal should release the effect map")
end

if failures > 0 then
    error(tostring(failures) .. " status effect test(s) failed")
end

print("status effects: ok")
