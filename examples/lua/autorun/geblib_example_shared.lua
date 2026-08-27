if not gebLib or not gebLib.Loaded then
    ErrorNoHalt("[gebLib example] gebLib must load before the example addon\n")
    return
end

gebLibExample = gebLibExample or {}
local Example = gebLibExample

Example.ImpactMessage = gebLib.Net.ToClient("geblib.example.impact.v1", {
    gebLib.Net.Player,
    gebLib.Net.Optional(gebLib.Net.Entity),
    gebLib.Net.Vector,
    gebLib.Net.Normal,
    gebLib.Net.Range(0, 255),
    gebLib.Net.Float,
    gebLib.Net.Color,
}, {
    unreliable = true,
})

Example.SelectPowerMessage = gebLib.Net.ToServer("geblib.example.select_power.v1", {
    gebLib.Net.Range(1, 4),
}, {
    rate = 2,
    burst = 3,
})

gebLib.StatusEffects.Register("geblib.example.bleed", {
    interval = 1,

    onTick = function(target, effect)
        if CLIENT then return end

        gebLib.Combat.ApplyDamage(target, {
            damage = effect.level,
            attacker = effect.source,
            inflictor = effect.inflictor,
            damageType = DMG_SLASH,
            position = target:WorldSpaceCenter(),
        })
    end,

    onReapply = function(target, effect, duration, level, source, inflictor)
        if level ~= effect.level then return false end

        effect.stacks = math.min((effect.stacks or 1) + 1, 3)
        effect.expiresAt = math.max(effect.expiresAt, CurTime() + duration)
        effect.source = source
        effect.inflictor = inflictor
        return true
    end,

    onApply = function(target, effect)
        effect.stacks = 1
    end,
})

function Example.AttackDirection(player)
    return gebLib.Math.SafeDirection(player:GetAimVector(), player:GetForward())
end

function Example.AttackStrength(power)
    local normalized = gebLib.Math.SmoothStep((power - 1) / 3)
    return Lerp(normalized, 90, 260)
end
