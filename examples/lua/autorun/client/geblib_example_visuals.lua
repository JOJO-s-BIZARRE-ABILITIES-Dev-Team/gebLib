local Example = gebLibExample
if not Example then return end

local batchesEnabled = CreateClientConVar("geblib_example_batches", "0", true, false)
local hudEnabled = CreateClientConVar("geblib_example_hud", "1", true, false)
local activeImpactFrames = {}
local lastImpactAt = 0

gebLib.ImpactFrames.RegisterSequence("geblib.example.impact", {
    {
        Weight = 1,
        SceneMix = 0.08,
        Posterize = 0.9,
        EdgeStrength = 3.5,
        EtchStrength = 0.65,
        Radial = 0.35,
        Smear = 0.2,
        Texture = "radial",
        TextureAlpha = 0.75,
        LineDensity = 0.9,
        LineAlpha = 0.8,
        ContactCore = true,
        CoreScale = 0.12,
        EnergyRibbons = true,
        RibbonIntensity = 0.7,
        Star = true,
        StarScale = 0.1,
        AttackerMaskStrength = 0.65,
        VictimMaskStrength = 0.9,
    },
    {
        Weight = 0.65,
        SceneMix = 0.55,
        EdgeStrength = 1,
        Texture = "fragments",
        TextureAlpha = 0.35,
        LineDensity = 0.25,
        LineAlpha = 0.35,
        FadeOut = true,
    },
})

gebLib.ImpactFrames.RegisterPreset("geblib.example.impact", {
    Sequence = "geblib.example.impact",
    Duration = 0.16,
    Intensity = 1,
    Priority = 50,
    Channel = "geblib.example.combat",
    Paper = Color(230, 242, 248),
    Ink = Color(15, 32, 44),
    OnFinish = function(id)
        activeImpactFrames[id] = nil
    end,
})

gebLib.Visuals.RegisterProjectedDecalAnimation("geblib.example.scorch", {
    texture = "decals/scorch1",
    frameCount = 1,
    duration = 0,
    poolSize = 8,
})

Example.ImpactMessage:Receive(function(attacker, target, position, normal, materialType, strength, color)
    lastImpactAt = RealTime()
    materialType = gebLib.Surface.NormalizeMaterial(materialType)

    local emitted, smoke = gebLib.Visuals.CreateImpactDebris(position, normal, strength, {
        material = materialType,
        direction = IsValid(attacker) and attacker:GetAimVector() or normal,
        count = strength * 0.45,
        modelCount = 10,
        propCount = 7,
        particleCount = 55,
        lifetime = 5,
        propLifetime = 4,
        smokeCount = 24,
        smokeColor = gebLib.Surface.Color(materialType),
    })

    gebLib.PrintDebug("example visual pieces", emitted, smoke)
    gebLib.Visuals.CreateShockwave(position, normal, strength * 1.8, 0.3, {
        startRadius = 8,
        color = color,
        distortionScale = 1.15,
    })

    local emitter = gebLib.Visuals.AcquireParticleEmitter(
        "geblib.example.impact.fragments",
        position,
        false,
        0.75
    )
    gebLib.Visuals.CreateDebrisBurst("effects/fleck_cement1", position, 18, {
        emitter = emitter,
        lifetimeMin = 0.35,
        lifetimeMax = 0.8,
        sizeMin = 1,
        sizeMax = 3,
        endSize = 0,
        speedMin = 120,
        speedMax = 320,
        direction = normal,
        spread = 0.8,
        collide = false,
        color = color,
        maxActiveParticles = 180,
    })

    if materialType ~= MAT_SLOSH then
        gebLib.Visuals.ProjectAnimatedDecal(
            "geblib.example.scorch",
            game.GetWorld(),
            position,
            normal,
            0.35,
            color_white
        )
        local decal = gebLib.Visuals.CreateDecal(
            "decals/scorch1",
            position + normal * 1.5,
            normal:Angle(),
            18,
            2
        )
        if IsValid(decal) then decal:DoAnimation(true, 24) end
    end

    local frameId = gebLib.ImpactFrames.Play("geblib.example.impact", {
        AnchorPosition = position,
        WorldDirection = IsValid(attacker) and attacker:GetAimVector() or normal,
        SubjectEntity = attacker,
        TargetEntity = target,
        Intensity = math.Clamp(strength / 180, 0.7, 1.5),
    })
    if frameId then activeImpactFrames[frameId] = true end

    if Example.KickCamera then Example.KickCamera(position, strength) end
end)

local activeWave
concommand.Add("geblib_example_wave", function()
    if activeWave and activeWave:IsActive() then
        activeWave:Cancel()
        activeWave = nil
        return
    end

    local player = LocalPlayer()
    if not IsValid(player) then return end

    local trace = player:GetEyeTrace()
    local direction = gebLib.Math.Horizontal(player:GetAimVector())
    direction = gebLib.Math.SafeDirection(direction, player:GetForward())

    activeWave = gebLib.Visuals.CreateDebrisWave({
        origin = trace.HitPos,
        direction = direction,
        count = 24,
        interval = 0.025,
        maxStepsPerFrame = 6,
        distanceStep = 28,
        spread = 45,
        lifetime = 4,
        floor = {
            startHeight = 72,
            depth = 220,
            filter = player,
            minNormalZ = 0.35,
        },
        prop = {
            offset = vector_up * 4,
            scaleMin = 0.7,
            scaleMax = 1.2,
            velocity = vector_up * 180,
            velocityJitter = 90,
            angularVelocity = 120,
            shadows = false,
        },
        model = {
            offset = vector_up * 2,
            scaleMin = 1.4,
            scaleMax = 2.2,
            shadows = false,
        },
        water = {
            strength = 38,
            particleCount = 48,
            particleScale = 1.3,
            gunshotSplashes = false,
        },
        events = {
            [1] = function(wave)
                gebLib.Visuals.CreateShockwave(wave.Origin, vector_up, 90, 0.2)
            end,
        },
        onStep = function(wave, step, position)
            if position and step % 8 == 0 then
                gebLib.Visuals.CreateDecal(
                    "decals/scorch1",
                    position + vector_up,
                    angle_zero,
                    10,
                    1.5
                )
            end
        end,
        onComplete = function(wave)
            chat.AddText(
                Color(120, 210, 255),
                "Wave: ",
                color_white,
                tostring(wave:GetSpawnedCount()),
                " spawned, ",
                tostring(wave:GetSkippedCount()),
                " skipped"
            )
            activeWave = nil
        end,
        onCancel = function()
            activeWave = nil
        end,
    })
end)

local beamBatch = gebLib.Visuals.BeamBatch.New("trails/laser")
local spriteBatch = gebLib.Visuals.SpriteBatch.New("sprites/light_glow02_add")

hook.Add("PostDrawTranslucentRenderables", "gebLibExample.VisualBatches", function()
    if not batchesEnabled:GetBool() then return end

    local player = LocalPlayer()
    if not IsValid(player) then return end

    local startPosition = player:EyePos() + player:GetAimVector() * 40
    local endPosition = startPosition + player:GetAimVector() * 220
    beamBatch:AddSegment(startPosition, endPosition, 3, Color(90, 190, 255, 180))
    beamBatch:Flush()

    spriteBatch:Add(endPosition, 18, 18, Color(180, 230, 255, 220))
    spriteBatch:Flush()
end)

hook.Add("HUDPaint", "gebLibExample.Drawing", function()
    if not hudEnabled:GetBool() then return end

    local progress = math.Clamp((RealTime() - lastImpactAt) / 1.5, 0, 1)
    local x = ScrW() - 72
    local y = ScrH() - 72
    gebLib.Drawing.Circle(x - 24, y - 24, 24, Color(10, 20, 28, 180), 100)
    gebLib.Drawing.CircularBar(x, y, (1 - progress) * 100, 24, 5, 180, Color(90, 190, 255))
    gebLib.Drawing.TextWithShadow(
        tostring(gebLib.Visuals.GetDebrisCount()),
        "DermaDefaultBold",
        x,
        y,
        color_white,
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
end)

hook.Add("ShutDown", "gebLibExample.VisualCleanup", function()
    if activeWave and activeWave:IsActive() then activeWave:Cancel() end
    for id in pairs(activeImpactFrames) do gebLib.ImpactFrames.Stop(id) end
    gebLib.Visuals.ReleaseParticleEmitter("geblib.example.impact.fragments")
end)
