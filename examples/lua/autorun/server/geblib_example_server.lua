local Example = gebLibExample
if not Example then return end

local selectedPower = setmetatable({}, {__mode = "k"})

Example.SelectPowerMessage:Receive(function(player, power)
    if not player:gebLib_ValidAndAlive() then return end

    selectedPower[player] = power
    player:gebLib_ChatAddText(
        Color(120, 210, 255),
        "Example power: ",
        color_white,
        tostring(power)
    )
end)

local function strike(player)
    if not player:gebLib_ValidAndAlive() then return end

    local power = selectedPower[player] or 1
    local direction = Example.AttackDirection(player)
    local strength = Example.AttackStrength(power)
    local origin = player:GetShootPos()
    local contact = gebLib.Combat.TraceAttack({
        origin = origin,
        direction = direction,
        distance = 700,
        attacker = player,
        water = true,
        mins = Vector(-6, -6, -6),
        maxs = Vector(6, 6, 6),
        refineRadius = 8,
    })

    if not contact then
        player:gebLib_ChatAddText(Color(255, 180, 120), "No contact")
        return
    end

    local target = contact.Entity
    if IsValid(target) and not target:IsWorld() then
        local force = gebLib.Combat.DirectionalRadialForce(
            target,
            contact.HitPos,
            direction,
            strength * 18,
            500,
            0.35,
            1
        )

        gebLib.Combat.ApplyHit(target, {
            damage = 8 * power,
            attacker = player,
            inflictor = player:GetActiveWeapon(),
            damageType = DMG_CLUB,
            position = contact.HitPos,
            force = force,
            knockbackOptions = {
                playerLift = 2,
                enableGravity = true,
            },
        })

        if target:gebLib_IsPerson() and target:gebLib_Alive() then
            target:gebLib_ApplyStatusEffect(
                "geblib.example.bleed",
                4,
                power,
                player,
                player:GetActiveWeapon()
            )
        end
    else
        target = nil
    end

    local surface = gebLib.Surface.Describe(contact.SurfaceProps)
    gebLib.PrintDebug(
        "example contact",
        contact.Distance,
        surface.material,
        surface.impactHardSound
    )

    Example.ImpactMessage:Broadcast(
        player,
        target,
        contact.HitPos,
        contact.HitNormal,
        math.Clamp(contact.MatType or MAT_CONCRETE, 0, 255),
        strength,
        Color(255, 190, 90)
    )
end

concommand.Add("geblib_example_strike", function(player)
    if not IsValid(player) then
        print("Run geblib_example_strike from a player's console")
        return
    end
    strike(player)
end)

concommand.Add("geblib_example_action", function(player)
    if not player:gebLib_ValidAndAlive() then return end

    if not player:gebLib_PlayAction("gesture_item_place", 1.15) then
        player:gebLib_ChatAddText(Color(255, 180, 120), "This model has no example sequence")
    end
end)

hook.Add("gebLib.PlayerFullyConnected", "gebLibExample.Welcome", function(player)
    if not IsValid(player) then return end

    player:gebLib_ChatAddText(
        Color(120, 210, 255),
        "gebLib example ready. Try geblib_example_strike"
    )
end)

hook.Add("PlayerDisconnected", "gebLibExample.PowerCleanup", function(player)
    selectedPower[player] = nil
end)
