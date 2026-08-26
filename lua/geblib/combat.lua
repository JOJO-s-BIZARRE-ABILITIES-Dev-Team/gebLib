gebLib.Combat = gebLib.Combat or {}

local Combat = gebLib.Combat
local Math = gebLib.Math

local function validTarget(entity, options)
    if not IsValid(entity)
        or entity == options.attacker
        or entity == options.inflictor
        or entity:IsWorld()
        or options.requireSolid ~= false and not entity:IsSolid()
    then
        return false
    end
    if options.alivePlayers ~= false and entity:IsPlayer() and not entity:Alive() then
        return false
    end
    return not options.filter or options.filter(entity) ~= false
end

function Combat.ContactFromTrace(trace, origin, direction)
    if not trace or not trace.Hit or trace.HitSky then return nil end

    local normal = trace.HitNormal
    if not normal or normal:LengthSqr() == 0 then normal = -direction end
    local position = trace.HitPos
    return {
        Hit = true,
        HitSky = false,
        HitWorld = trace.HitWorld == true,
        HitPos = position,
        HitNormal = normal:GetNormalized(),
        Entity = trace.Entity,
        MatType = trace.MatType,
        SurfaceProps = trace.SurfaceProps or 0,
        SurfaceFlags = trace.SurfaceFlags or 0,
        HitNoDraw = trace.HitNoDraw,
        Direction = direction,
        Distance = math.max(0, (position - origin):Dot(direction)),
        DistanceSqr = origin:DistToSqr(position),
        Fraction = trace.Fraction,
    }
end

function Combat.TraceWater(origin, endPosition, direction, filter, mask)
    local trace = util.TraceLine({
        start = origin,
        endpos = endPosition,
        filter = filter,
        mask = mask or MASK_WATER,
    })
    if not trace.Hit or trace.HitSky or trace.StartSolid then return nil end

    local contact = Combat.ContactFromTrace(trace, origin, direction)
    if not contact then return nil end
    if not trace.HitNormal or trace.HitNormal:LengthSqr() == 0 then
        contact.HitNormal = vector_up
    end
    contact.HitWorld = true
    contact.Entity = game.GetWorld()
    contact.MatType = MAT_SLOSH
    contact.IsWater = true
    return contact
end

function Combat.TraceAttack(options)
    local origin = options.origin
    local direction = Math.SafeDirection(options.direction, vector_up)
    local distance = math.max(tonumber(options.distance) or 0, 0)
    local endPosition = origin + direction * distance
    local traceData = {
        start = origin,
        endpos = endPosition,
        filter = options.traceFilter or options.attacker,
        mask = options.mask or MASK_SHOT_HULL,
    }
    if options.mins and options.maxs then
        traceData.mins = options.mins
        traceData.maxs = options.maxs
    end

    local trace = options.mins and util.TraceHull(traceData) or util.TraceLine(traceData)
    if options.refineRadius and trace.Hit and not trace.HitSky
        and trace.HitNormal and trace.HitNormal:LengthSqr() > 0 then
        local normal = trace.HitNormal:GetNormalized()
        local refined = util.TraceLine({
            start = trace.HitPos + normal * 4,
            endpos = trace.HitPos - normal * (options.refineRadius * 2 + 8),
            filter = options.traceFilter or options.attacker,
            mask = options.refineMask or MASK_SHOT,
        })
        local sameSurface = refined.Hit and not refined.HitSky
            and (trace.HitWorld and refined.HitWorld
                or not trace.HitWorld and IsValid(trace.Entity) and refined.Entity == trace.Entity)
        if sameSurface then trace = refined end
    end

    local solidContact = Combat.ContactFromTrace(trace, origin, direction)
    local waterContact
    if options.water then
        waterContact = Combat.TraceWater(
            origin,
            endPosition,
            direction,
            options.traceFilter or options.attacker,
            options.waterMask
        )
        if waterContact and solidContact and waterContact.Distance > solidContact.Distance then
            waterContact = nil
        end
    end

    local contact = solidContact
    if waterContact and (not contact or waterContact.Distance < contact.Distance) then
        contact = waterContact
    end
    return contact, solidContact, waterContact, endPosition, trace
end

function Combat.CollectCone(options)
    local origin = options.origin
    local direction = Math.SafeDirection(options.direction, vector_up)
    local distance = math.max(tonumber(options.distance) or 0, 0)
    local results = {}

    for _, entity in ipairs(ents.FindInCone(
        origin,
        direction,
        distance,
        tonumber(options.dot) or 0
    )) do
        if validTarget(entity, options) then
            local center = entity:WorldSpaceCenter()
            local forwardDistance = (center - origin):Dot(direction)
            if forwardDistance >= (options.minimumForward or 0)
                and forwardDistance <= (options.maximumForward or distance) then
                local trace
                if options.visible ~= false then
                    trace = util.TraceLine({
                        start = origin,
                        endpos = center,
                        filter = options.traceFilter or options.attacker,
                        mask = options.visibilityMask or MASK_SHOT,
                    })
                end
                if not trace or not trace.Hit or trace.Entity == entity then
                    local closest = origin + direction * forwardDistance
                    local contact = trace
                        and Combat.ContactFromTrace(trace, origin, direction)
                    if not contact then
                        contact = {
                            Hit = true,
                            HitSky = false,
                            HitWorld = false,
                            HitPos = entity:NearestPoint(closest),
                            HitNormal = -direction,
                            Entity = entity,
                            MatType = entity:GetMaterialType(),
                            SurfaceProps = 0,
                            SurfaceFlags = 0,
                            Direction = direction,
                            Distance = forwardDistance,
                            Fraction = distance > 0 and forwardDistance / distance or 0,
                        }
                    end
                    contact.Entity = entity
                    contact.LateralDistanceSqr = center:DistToSqr(closest)
                    results[#results + 1] = contact
                end
            end
        end
    end
    return results
end

function Combat.ClosestToRay(contacts)
    local best
    for index = 1, #contacts do
        local contact = contacts[index]
        if not best
            or contact.LateralDistanceSqr < best.LateralDistanceSqr
            or contact.LateralDistanceSqr == best.LateralDistanceSqr
                and contact.Distance < best.Distance then
            best = contact
        end
    end
    return best
end

function Combat.CollectSphere(options)
    local results = {}
    local origin = options.origin
    for _, entity in ipairs(ents.FindInSphere(origin, options.radius)) do
        if validTarget(entity, options) then
            local center = entity:WorldSpaceCenter()
            local offset = center - origin
            local distance = offset:Length()
            local forwardOffset = center - (options.forwardOrigin or origin)
            if not options.forward or forwardOffset:Dot(options.forward) >= 0 then
                local visible = true
                local trace
                if options.visible then
                    trace = util.TraceLine({
                        start = options.visibilityOrigin or origin,
                        endpos = center,
                        filter = options.traceFilter or options.attacker,
                        mask = options.visibilityMask or MASK_SHOT,
                    })
                    visible = not trace.Hit or trace.Entity == entity
                end
                if visible then
                    results[#results + 1] = {
                        Entity = entity,
                        Center = center,
                        Offset = offset,
                        Distance = distance,
                        Falloff = Math.DistanceFalloff(distance, options.radius, options.exponent),
                        HitPos = trace and trace.Hit and trace.HitPos or entity:NearestPoint(origin),
                    }
                end
            end
        end
    end
    return results
end

function Combat.DirectionalRadialForce(entity, origin, direction, amount, radius, minimumScale, maximumScale)
    local offset = entity:WorldSpaceCenter() - origin
    local distance = offset:Length()
    local radial = Math.SafeDirection(offset, direction)
    local forceDirection = Math.SafeDirection(direction * 0.75 + radial * 0.25, direction)
    local falloff = Math.DistanceFalloff(distance, radius)
    local scale = Lerp(falloff, minimumScale or 0, maximumScale or 1)
    return forceDirection * amount * scale
end

function Combat.ApplyDamage(entity, options)
    if not IsValid(entity) then return nil end
    local damage = DamageInfo()
    damage:SetDamage(tonumber(options.damage) or 0)
    damage:SetAttacker(IsValid(options.attacker) and options.attacker or game.GetWorld())
    damage:SetInflictor(IsValid(options.inflictor) and options.inflictor
        or IsValid(options.attacker) and options.attacker
        or game.GetWorld())
    damage:SetDamageType(options.damageType or DMG_GENERIC)
    if options.position then damage:SetDamagePosition(options.position) end
    if options.force then damage:SetDamageForce(options.force) end

    if options.suppressHostEvents and SuppressHostEvents then SuppressHostEvents(nil) end
    entity:TakeDamageInfo(damage)
    if options.suppressHostEvents and SuppressHostEvents and IsValid(options.attacker) then
        SuppressHostEvents(options.attacker)
    end
    return damage
end

function Combat.ApplyKnockback(entity, force, options)
    if not IsValid(entity) or not force then return false end
    options = options or {}

    if entity:IsPlayer() and options.playerLift then
        entity:SetPos(entity:GetPos() + vector_up * options.playerLift)
    end

    local living = entity:IsPlayer() or entity:IsNPC() or entity:IsNextBot()
    if living then
        if options.living ~= false then entity:SetVelocity(force) end
        if not options.physicsForLiving or entity:IsPlayer() then return true end
    end

    local removeConstraints = isfunction(options.removeConstraints)
        and options.removeConstraints(entity)
        or options.removeConstraints == true
    local restoreGravity = isfunction(options.restoreGravity)
        and options.restoreGravity(entity)
        or options.restoreGravity == true
    if removeConstraints then constraint.RemoveAll(entity) end
    if restoreGravity then entity:SetGravity(physenv.GetGravity():Length()) end
    local physics = entity:GetPhysicsObject()
    if not IsValid(physics) then return false end
    if options.enableGravity then physics:EnableGravity(true) end
    if options.physicsMode == "velocity" then
        physics:SetVelocity(force)
    else
        if physics.Wake then physics:Wake() end
        physics:ApplyForceCenter(force)
    end
    return true
end

function Combat.ApplyHit(entity, options)
    local damage = Combat.ApplyDamage(entity, options)
    if options.knockback ~= false and options.force then
        Combat.ApplyKnockback(entity, options.force, options.knockbackOptions)
    end
    return damage
end

function Combat.ApplyRadialImpact(options)
    local results = Combat.CollectSphere(options)
    for index = 1, #results do
        local hit = results[index]
        if hit.Falloff > 0 then
            local direction = Math.SafeDirection(
                hit.Offset:GetNormalized() + vector_up * (options.lift or 0),
                vector_up
            )
            local force = direction * options.force * hit.Falloff
            local damage = (options.damage or 0) * hit.Falloff
            if damage > 0 and (not options.canDamage or options.canDamage(hit.Entity)) then
                Combat.ApplyDamage(hit.Entity, {
                    damage = damage,
                    attacker = options.attacker,
                    inflictor = options.inflictor,
                    damageType = options.damageType or bit.bor(DMG_BLAST, DMG_CRUSH),
                    position = hit.Center,
                    force = force,
                })
            end

            local knockback = force
            if hit.Entity:IsPlayer() and options.playerVelocityDivisor then
                local speed = options.force * hit.Falloff / options.playerVelocityDivisor
                knockback = direction * math.min(speed, options.playerVelocityCap or speed)
            end
            Combat.ApplyKnockback(
                hit.Entity,
                knockback,
                hit.Entity:IsPlayer()
                    and options.playerKnockbackOptions
                    or options.knockbackOptions
            )
        end
    end
    return results
end
