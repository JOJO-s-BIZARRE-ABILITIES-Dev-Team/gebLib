if SERVER then return end

local Renderer = {}
local SmoothStep = gebLib.Math.SmoothStep
local white = Color(255, 255, 255)
local paleBlue = Color(224, 244, 250)
local hotOrange = Color(255, 119, 20)
local warmWhite = Color(255, 250, 226)
-- The TEXTUREFLAGS enum names are documentation-only in Garry's Mod.
local maskTextureFlags = bit.bor(2, 4, 8, 256, 8192) -- trilinear, clamp S/T, no mipmaps, 8-bit alpha

local materials = {
    PostProcess = Material("geblib/impact_frames/impact_post"),
    Radial = Material("geblib/impact_frames/radial_ink.png", "smooth noclamp"),
    Slashes = Material("geblib/impact_frames/slashes_ink.png", "smooth noclamp"),
    Fragments = Material("geblib/impact_frames/fragments_ink.png", "smooth noclamp")
}

local maskOverrideMaterial = CreateMaterial("gebLib_ImpactFrames_MaskOverride", "UnlitGeneric", {
    ["$basetexture"] = "color/white",
    ["$model"] = "1",
    ["$nocull"] = "1"
})

local maskSurfaces = {
    Attacker = {
        TargetName = "geblib_impact_attacker_mask",
        MaterialName = "gebLib_ImpactFrames_AttackerMaskDisplay"
    },
    Victim = {
        TargetName = "geblib_impact_victim_mask",
        MaterialName = "gebLib_ImpactFrames_VictimMaskDisplay"
    }
}
local maskWidth = 0
local maskHeight = 0
local shaderFailureReported = false
local shaderBinaryPresent = not file or not file.Exists
    or file.Exists("shaders/fxc/geblib_impact_ps20b.vcs", "GAME")
local impactFramesShader = CreateClientConVar(
    "geblib_impact_frames_shader",
    "1",
    true,
    false,
    "Use the impact-frame shader",
    0,
    1
)

local function NextRandom(instance, minimum, maximum)
    instance.RandomState = (instance.RandomState * 1664525 + 1013904223) % 4294967296
    local value = instance.RandomState / 4294967296
    return minimum + (maximum - minimum) * value
end

local function ResolveAnchorPosition(instance)
    if IsValid(instance.AnchorEntity) then
        local position
        if instance.AnchorBone then position = instance.AnchorEntity:GetBonePosition(instance.AnchorBone) end
        position = position or instance.AnchorEntity:WorldSpaceCenter()
        if instance.AnchorOffset then position = position + instance.AnchorOffset end
        return position
    end

    return instance.AnchorPosition or instance.WorldPosition
end

local function ResolveComposition(instance, screenWidth, screenHeight)
    local focusX = screenWidth * instance.FocusX
    local focusY = screenHeight * instance.FocusY
    local anchor = ResolveAnchorPosition(instance)
    local projectedAnchor

    if anchor then
        projectedAnchor = anchor:ToScreen()
        if projectedAnchor.visible then
            focusX = math.Clamp(projectedAnchor.x, screenWidth * 0.06, screenWidth * 0.94)
            focusY = math.Clamp(projectedAnchor.y, screenHeight * 0.08, screenHeight * 0.92)
        end
    end

    local directionX
    local directionY
    if anchor and instance.WorldDirection then
        local projectedEnd = (anchor + instance.WorldDirection * 256):ToScreen()
        if projectedAnchor and projectedAnchor.visible and projectedEnd and projectedEnd.visible then
            directionX = projectedEnd.x - projectedAnchor.x
            directionY = projectedEnd.y - projectedAnchor.y
        end
    end

    local length = directionX and math.sqrt(directionX * directionX + directionY * directionY) or 0
    if length < 0.001 then
        local radians = math.rad(instance.Rotation)
        directionX = math.cos(radians)
        directionY = math.sin(radians)
    else
        directionX = directionX / length
        directionY = directionY / length
    end

    return focusX, focusY, directionX, directionY
end

local function ApplyExposureJitter(instance, art, focusX, focusY, directionX, directionY, screenWidth, screenHeight)
    local amount = instance.FrameJitter
    if amount <= 0 then return focusX, focusY, directionX, directionY end

    local positionScale = screenHeight * 0.0035 * amount
    focusX = math.Clamp(focusX + art.FocusJitterX * positionScale, screenWidth * 0.04, screenWidth * 0.96)
    focusY = math.Clamp(focusY + art.FocusJitterY * positionScale, screenHeight * 0.05, screenHeight * 0.95)

    local angle = math.rad(art.DirectionJitter * 1.2 * amount)
    local cosine = math.cos(angle)
    local sine = math.sin(angle)
    return focusX,
        focusY,
        directionX * cosine - directionY * sine,
        directionX * sine + directionY * cosine
end

local function BuildExposureArt(instance)
    instance.ExposureArt = {}

    for exposureIndex, exposure in ipairs(instance.Sequence) do
        local art = {
            Lines = {},
            Rotation = NextRandom(instance, -3.5, 3.5),
            TextureScale = NextRandom(instance, 0.98, 1.08),
            FocusJitterX = NextRandom(instance, -1, 1),
            FocusJitterY = NextRandom(instance, -1, 1),
            DirectionJitter = NextRandom(instance, -1, 1),
            StarRadii = {},
            CoreWedges = {},
            Ribbons = {}
        }

        local density = math.max(0, tonumber(exposure.LineDensity) or 0)
        local lineCount = math.min(220, math.floor(instance.LineCount * instance.Intensity * density))
        local directionBias = math.Clamp(tonumber(exposure.DirectionBias) or 0.65, 0, 1)

        for index = 1, lineCount do
            local angleOffset
            if NextRandom(instance, 0, 1) < directionBias then
                local side = NextRandom(instance, 0, 1) < 0.5 and 0 or math.pi
                angleOffset = side + NextRandom(instance, -0.42, 0.42)
            else
                angleOffset = NextRandom(instance, 0, math.pi * 2)
            end

            art.Lines[index] = {
                AngleOffset = angleOffset,
                InnerRadius = NextRandom(instance, 0.06, 0.34),
                OuterRadius = NextRandom(instance, 0.52, 1.08),
                Width = NextRandom(instance, 0.8, 5.4) * instance.Intensity
            }
        end

        local spikeCount = math.max(8, math.floor(tonumber(exposure.StarSpikes) or 18))
        for index = 1, spikeCount do
            art.StarRadii[index] = NextRandom(instance, 0.68, 1.18)
        end

        for index = 1, 14 do
            art.CoreWedges[index] = {
                AngleOffset = NextRandom(instance, -1.05, 1.05),
                Start = NextRandom(instance, 0.04, 0.18),
                Length = NextRandom(instance, 0.48, 1.2),
                Width = NextRandom(instance, 0.018, 0.075)
            }
        end

        for index = 1, 6 do
            art.Ribbons[index] = {
                Offset = NextRandom(instance, -0.55, 0.55),
                Width = NextRandom(instance, 0.016, 0.065),
                Length = NextRandom(instance, 0.55, 1.15),
                Phase = NextRandom(instance, -0.3, 0.3),
                Alpha = NextRandom(instance, 0.5, 1)
            }
        end

        instance.ExposureArt[exposureIndex] = art
    end
end

local function CalculateExposureState(instance, now)
    local progress = math.Clamp((now - instance.StartTime) / instance.Duration, 0, 1)
    local cursor = progress * instance.TotalWeight
    local accumulated = 0

    for index, exposure in ipairs(instance.Sequence) do
        local weight = math.max(0.01, tonumber(exposure.Weight) or 1)
        local nextAccumulated = accumulated + weight
        if cursor < nextAccumulated or index == #instance.Sequence then
            local localProgress = math.Clamp((cursor - accumulated) / weight, 0, 1)
            local effectScale = exposure.FadeOut and 1 - SmoothStep(localProgress) or 1
            return exposure, instance.ExposureArt[index], localProgress, effectScale, index, progress
        end
        accumulated = nextAccumulated
    end
end

local function GetExposureState(instance, now)
    local frameNumber = FrameNumber()
    local cached = instance.LastExposureState
    if cached and instance.LastExposureFrame == frameNumber then
        return cached.Exposure, cached.Art, cached.LocalProgress, cached.EffectScale
    end

    local exposure, art, localProgress, effectScale, index, timelineProgress = CalculateExposureState(instance, now)
    local previousIndex = instance.LastExposureIndex
    if previousIndex and index > previousIndex + 1 then
        index = previousIndex + 1
        exposure = instance.Sequence[index]
        art = instance.ExposureArt[index]
        localProgress = 0
        effectScale = 1
    elseif previousIndex and index > previousIndex and timelineProgress >= 1 then
        localProgress = 0
        effectScale = 1
    end

    cached = {
        Exposure = exposure,
        Art = art,
        LocalProgress = localProgress,
        EffectScale = effectScale
    }
    instance.LastExposureState = cached
    instance.LastExposureFrame = frameNumber
    instance.LastExposureIndex = index
    instance.LastExposureTime = now
    return exposure, art, localProgress, effectScale
end

local function EnsureMaskSurfaces()
    maskWidth = ScrW()
    maskHeight = ScrH()

    for _, key in ipairs({"Attacker", "Victim"}) do
        local maskSurface = maskSurfaces[key]
        if not maskSurface.Target then
            maskSurface.Target = GetRenderTargetEx(
                maskSurface.TargetName,
                1,
                1,
                RT_SIZE_FULL_FRAME_BUFFER,
                MATERIAL_RT_DEPTH_SEPARATE,
                maskTextureFlags,
                0,
                IMAGE_FORMAT_BGRA8888
            )
            if not maskSurface.Target then return false end

            maskSurface.DisplayMaterial = CreateMaterial(maskSurface.MaterialName, "UnlitGeneric", {
                ["$basetexture"] = maskSurface.Target:GetName(),
                ["$translucent"] = "1",
                ["$vertexalpha"] = "1",
                ["$vertexcolor"] = "1",
                ["$ignorez"] = "1"
            })
        end
    end

    if not materials.PostProcess:IsError() then
        materials.PostProcess:SetTexture("$texture1", maskSurfaces.Attacker.Target)
        materials.PostProcess:SetTexture("$texture2", maskSurfaces.Victim.Target)
    end

    return true
end

local function RenderEntityMask(maskSurface, entities, color, strength, label)
    local view = render.GetViewSetup and render.GetViewSetup() or nil
    local pushed = false
    local started3D = false
    local ok, err = xpcall(function()
        render.PushRenderTarget(maskSurface.Target)
        pushed = true
        render.Clear(0, 0, 0, 0, true, true)

        if strength > 0 and #entities > 0 then
            cam.Start3D(
                view and view.origin or EyePos(),
                view and view.angles or EyeAngles(),
                view and view.fov or 90,
                0,
                0,
                maskWidth,
                maskHeight,
                view and view.znear or nil,
                view and view.zfar or nil
            )
            started3D = true

            render.SuppressEngineLighting(true)
            render.SetWriteDepthToDestAlpha(false)
            render.ResetModelLighting(1, 1, 1)
            render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
            render.MaterialOverride(maskOverrideMaterial)

            for _, entity in ipairs(entities) do
                local unsafeBoneMerge = IsValid(entity)
                    and entity:IsEffectActive(EF_BONEMERGE)
                    and entity:IsEffectActive(EF_NODRAW)
                if IsValid(entity) and not entity:IsDormant() and not unsafeBoneMerge then
                    local entityOk, entityError = pcall(function()
                        entity:SetupBones()
                        render.OverrideColorWriteEnable(true, false)
                        render.OverrideAlphaWriteEnable(true, false)
                        render.SetBlend(1)
                        entity:DrawModel()
                        render.OverrideColorWriteEnable(false, false)
                        render.OverrideAlphaWriteEnable(false, false)
                        render.SetBlend(math.Clamp(strength, 0, 1))
                        entity:DrawModel()
                    end)
                    render.OverrideColorWriteEnable(false, false)
                    render.OverrideAlphaWriteEnable(false, false)
                    if not entityOk then
                        ErrorNoHalt("[gebLib] " .. label .. " mask draw failed: " .. tostring(entityError) .. "\n")
                    end
                end
            end
        end
    end, debug.traceback)

    render.MaterialOverride(nil)
    render.SetBlend(1)
    render.SetColorModulation(1, 1, 1)
    render.OverrideColorWriteEnable(false, false)
    render.OverrideAlphaWriteEnable(false, false)
    render.SetWriteDepthToDestAlpha(true)
    render.SuppressEngineLighting(false)
    if started3D then cam.End3D() end
    if pushed then render.PopRenderTarget() end

    if not ok then
        ErrorNoHalt("[gebLib] " .. label .. " mask failed: " .. tostring(err) .. "\n")
        return false
    end

    return true
end

local function RenderDualMasks(instance, exposure, effectScale)
    local legacyStrength = tonumber(exposure.MaskStrength) or 0
    local attackerStrength = (tonumber(exposure.AttackerMaskStrength) or legacyStrength) * effectScale
    local victimStrength = (tonumber(exposure.VictimMaskStrength) or legacyStrength) * effectScale
    local maskEnabled = attackerStrength > 0 or victimStrength > 0
    if not maskEnabled then return true, false end
    if not EnsureMaskSurfaces() then return false, true end

    local attackerColor = exposure.AttackerColor or exposure.Ink or instance.Ink
    local victimColor = exposure.VictimColor or exposure.Ink or instance.Ink
    local attackerOk = RenderEntityMask(
        maskSurfaces.Attacker,
        instance.AttackerEntities,
        attackerColor,
        attackerStrength,
        "attacker"
    )
    local victimOk = RenderEntityMask(
        maskSurfaces.Victim,
        instance.VictimEntities,
        victimColor,
        victimStrength,
        "victim"
    )
    return attackerOk and victimOk, true
end

local function CanUseShader(instance)
    if instance.ShaderFailed then return false end
    if impactFramesShader and not impactFramesShader:GetBool() then return false end
    if not shaderBinaryPresent then return false end
    if materials.PostProcess:IsError() then return false end
    if render.SupportsPixelShaders_2_0 and not render.SupportsPixelShaders_2_0() then return false end

    local shader = materials.PostProcess.GetShader and materials.PostProcess:GetShader() or ""
    return string.lower(shader or "") == "screenspace_general"
end

local function SetShaderColor(material, prefix, color)
    material:SetFloat(prefix .. "_x", color.r / 255)
    material:SetFloat(prefix .. "_y", color.g / 255)
    material:SetFloat(prefix .. "_z", color.b / 255)
end

local function DrawShaderPass(instance, exposure, effectScale, focusX, focusY, directionX, directionY, maskAvailable, maskEnabled)
    if not CanUseShader(instance) then return false end

    local material = materials.PostProcess
    local sceneMix = 1 - (1 - (tonumber(exposure.SceneMix) or 0)) * effectScale
    local posterize = (tonumber(exposure.Posterize) or 0) * effectScale
    local edgeStrength = (tonumber(exposure.EdgeStrength) or 0) * effectScale
    local etchStrength = math.Clamp((tonumber(exposure.EtchStrength) or 0) * effectScale, 0, 1)
    local encodedEtchAndMask = etchStrength + (maskAvailable and maskEnabled and 2 or 0)
    local radial = (tonumber(exposure.Radial) or 0) * effectScale
    local smear = (tonumber(exposure.Smear) or 0) * effectScale
    local paper = exposure.Paper or instance.Paper
    local ink = exposure.Ink or instance.Ink

    local ok, err = xpcall(function()
        material:SetFloat("$c0_x", sceneMix)
        material:SetFloat("$c0_y", posterize)
        material:SetFloat("$c0_z", edgeStrength)
        material:SetFloat("$c0_w", encodedEtchAndMask)
        material:SetFloat("$c1_x", focusX / ScrW())
        material:SetFloat("$c1_y", focusY / ScrH())
        material:SetFloat("$c1_z", directionX)
        material:SetFloat("$c1_w", directionY)
        SetShaderColor(material, "$c2", paper)
        material:SetFloat("$c2_w", radial)
        SetShaderColor(material, "$c3", ink)
        material:SetFloat("$c3_w", smear)

        render.UpdateScreenEffectTexture()
        render.SetMaterial(material)
        render.DrawScreenQuad()
    end, debug.traceback)

    if ok then return true end

    instance.ShaderFailed = true
    if not shaderFailureReported then
        shaderFailureReported = true
        ErrorNoHalt("[gebLib] Impact-frame shader failed, using fallback: " .. tostring(err) .. "\n")
    end
    return false
end

local fallbackColorModify = {
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0,
    ["$pp_colour_contrast"] = 1,
    ["$pp_colour_colour"] = 1,
    ["$pp_colour_mulr"] = 0,
    ["$pp_colour_mulg"] = 0,
    ["$pp_colour_mulb"] = 0
}

local function DrawFallbackPostProcess(exposure, effectScale)
    local posterize = (tonumber(exposure.Posterize) or 0) * effectScale
    local paper = exposure.Paper or paleBlue
    if posterize > 0.001 then
        fallbackColorModify["$pp_colour_addr"] = (paper.r / 255 - 0.5) * posterize * 0.08
        fallbackColorModify["$pp_colour_addg"] = (paper.g / 255 - 0.5) * posterize * 0.08
        fallbackColorModify["$pp_colour_addb"] = (paper.b / 255 - 0.5) * posterize * 0.08
        fallbackColorModify["$pp_colour_contrast"] = 1 + posterize * 0.75
        fallbackColorModify["$pp_colour_colour"] = 1 - posterize * 0.92
        DrawColorModify(fallbackColorModify)
    end

    local sobel = math.Clamp((tonumber(exposure.EdgeStrength) or 0) * effectScale * 0.08, 0, 1)
    if sobel > 0.02 then DrawSobel(sobel) end
end

local function DrawMask(maskSurface, alpha, screenWidth, screenHeight)
    if not maskSurface.DisplayMaterial or alpha <= 0 then return end
    surface.SetMaterial(maskSurface.DisplayMaterial)
    surface.SetDrawColor(255, 255, 255, alpha)
    surface.DrawTexturedRect(0, 0, screenWidth, screenHeight)
end

local function DrawOrientedQuad(centerX, centerY, directionX, directionY, halfLength, halfWidth, color, alpha)
    local perpendicularX = -directionY * halfWidth
    local perpendicularY = directionX * halfWidth
    local lengthX = directionX * halfLength
    local lengthY = directionY * halfLength

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, alpha)
    surface.DrawPoly({
        {x = centerX - lengthX + perpendicularX, y = centerY - lengthY + perpendicularY},
        {x = centerX + lengthX + perpendicularX, y = centerY + lengthY + perpendicularY},
        {x = centerX + lengthX - perpendicularX, y = centerY + lengthY - perpendicularY},
        {x = centerX - lengthX - perpendicularX, y = centerY - lengthY - perpendicularY}
    })
end

local function DrawTaperedSpear(focusX, focusY, directionX, directionY, backLength, forwardLength, width, color, alpha)
    local perpendicularX = -directionY
    local perpendicularY = directionX
    local backX = focusX - directionX * backLength
    local backY = focusY - directionY * backLength
    local shoulderX = focusX + directionX * forwardLength * 0.72
    local shoulderY = focusY + directionY * forwardLength * 0.72
    local tipX = focusX + directionX * forwardLength
    local tipY = focusY + directionY * forwardLength

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, alpha)
    surface.DrawPoly({
        {x = backX + perpendicularX * width * 0.24, y = backY + perpendicularY * width * 0.24},
        {x = focusX - directionX * backLength * 0.08 + perpendicularX * width, y = focusY - directionY * backLength * 0.08 + perpendicularY * width},
        {x = shoulderX + perpendicularX * width * 0.16, y = shoulderY + perpendicularY * width * 0.16},
        {x = tipX, y = tipY},
        {x = shoulderX - perpendicularX * width * 0.16, y = shoulderY - perpendicularY * width * 0.16},
        {x = focusX - directionX * backLength * 0.08 - perpendicularX * width, y = focusY - directionY * backLength * 0.08 - perpendicularY * width},
        {x = backX - perpendicularX * width * 0.24, y = backY - perpendicularY * width * 0.24}
    })
end

local function DrawAsymmetricContactCore(instance, exposure, art, effectScale, focusX, focusY, directionX, directionY, screenHeight)
    if not exposure.ContactCore or effectScale <= 0 then return end

    local alpha = 255 * (tonumber(exposure.CoreAlpha) or 1) * effectScale
    local size = screenHeight * (tonumber(exposure.CoreScale) or 0.14) * instance.Intensity
    local outerColor = exposure.CoreOuterColor or exposure.Ink or instance.Ink
    local coreColor = exposure.CoreColor or white
    local negativeColor = exposure.CoreNegativeColor or exposure.Paper or instance.Paper
    local perpendicularX = -directionY
    local perpendicularY = directionX
    local baseAngle = math.atan2(directionY, directionX)

    for index, wedge in ipairs(art.CoreWedges) do
        local angle = baseAngle + wedge.AngleOffset
        local cosine = math.cos(angle)
        local sine = math.sin(angle)
        local start = size * wedge.Start
        local length = size * wedge.Length
        local halfWidth = size * wedge.Width
        local startX = focusX + cosine * start
        local startY = focusY + sine * start
        local endX = focusX + cosine * length
        local endY = focusY + sine * length
        local color = index % 4 == 0 and negativeColor or outerColor

        draw.NoTexture()
        surface.SetDrawColor(color.r, color.g, color.b, alpha * (index % 4 == 0 and 0.9 or 0.72))
        surface.DrawPoly({
            {x = startX - sine * halfWidth * 0.18, y = startY + cosine * halfWidth * 0.18},
            {x = endX, y = endY},
            {x = startX + sine * halfWidth * 0.18, y = startY - cosine * halfWidth * 0.18}
        })
    end

    DrawTaperedSpear(focusX, focusY, directionX, directionY, size * 0.72, size * 4.2, size * 0.19, outerColor, alpha)
    DrawTaperedSpear(focusX, focusY, directionX, directionY, size * 0.42, size * 3.55, size * 0.075, coreColor, alpha)
    DrawOrientedQuad(focusX, focusY, perpendicularX, perpendicularY, size * 1.15, size * 0.022, coreColor, alpha * 0.82)
end

local function DrawEnergyRibbons(instance, exposure, art, localProgress, effectScale, focusX, focusY, directionX, directionY, screenWidth, screenHeight)
    if not exposure.EnergyRibbons or effectScale <= 0 then return end

    local outerColor = exposure.RibbonOuterColor or hotOrange
    local coreColor = exposure.RibbonCoreColor or warmWhite
    local perpendicularX = -directionY
    local perpendicularY = directionX
    local intensity = tonumber(exposure.RibbonIntensity) or 1

    for _, ribbon in ipairs(art.Ribbons) do
        local travel = (localProgress * 1.45 + ribbon.Phase - 0.32) * screenWidth
        local centerX = focusX + directionX * travel + perpendicularX * ribbon.Offset * screenHeight
        local centerY = focusY + directionY * travel + perpendicularY * ribbon.Offset * screenHeight
        local halfLength = screenWidth * ribbon.Length
        local halfWidth = screenHeight * ribbon.Width * intensity
        local alpha = 255 * ribbon.Alpha * effectScale

        DrawOrientedQuad(centerX, centerY, directionX, directionY, halfLength, halfWidth, outerColor, alpha * 0.82)
        DrawOrientedQuad(centerX, centerY, directionX, directionY, halfLength * 1.03, halfWidth * 0.28, coreColor, alpha)
    end
end

local function DrawContactStar(exposure, art, alpha, focusX, focusY, directionX, directionY, screenHeight)
    if not exposure.Star or alpha <= 0 then return end

    local color = exposure.StarColor or white
    local size = screenHeight * (tonumber(exposure.StarScale) or 0.15)
    local perpendicularX = -directionY
    local perpendicularY = directionX
    local baseAngle = math.atan2(directionY, directionX)
    local spikeCount = #art.StarRadii
    local points = {}

    DrawOrientedQuad(focusX, focusY, directionX, directionY, size * 2.8, size * 0.018, color, alpha * 0.75)
    DrawOrientedQuad(focusX, focusY, perpendicularX, perpendicularY, size * 1.8, size * 0.014, color, alpha * 0.58)

    for index = 1, spikeCount * 2 do
        local outer = index % 2 == 1
        local spikeIndex = math.floor((index + 1) / 2)
        local angle = baseAngle + (index - 1) * math.pi / spikeCount
        local radius = outer and size * art.StarRadii[spikeIndex] or size * 0.16
        points[index] = {
            x = focusX + math.cos(angle) * radius,
            y = focusY + math.sin(angle) * radius
        }
    end

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, alpha)
    surface.DrawPoly(points)
end

local function DrawSpeedLines(instance, exposure, art, color, alpha, focusX, focusY, directionX, directionY, screenWidth, screenHeight)
    if alpha <= 0 or #art.Lines == 0 then return end

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, alpha)

    local directionAngle = math.atan2(directionY, directionX)
    local radiusScale = math.max(screenWidth, screenHeight) * (tonumber(exposure.Expansion) or 1)
    local widthScale = screenHeight / 1080

    for _, line in ipairs(art.Lines) do
        local angle = directionAngle + line.AngleOffset
        local cosine = math.cos(angle)
        local sine = math.sin(angle)
        local inner = line.InnerRadius * radiusScale
        local outer = line.OuterRadius * radiusScale
        local halfWidth = line.Width * widthScale
        local perpendicularX = -sine * halfWidth
        local perpendicularY = cosine * halfWidth
        local innerX = focusX + cosine * inner
        local innerY = focusY + sine * inner
        local outerX = focusX + cosine * outer
        local outerY = focusY + sine * outer

        surface.DrawPoly({
            {x = innerX + perpendicularX * 0.2, y = innerY + perpendicularY * 0.2},
            {x = outerX + perpendicularX, y = outerY + perpendicularY},
            {x = outerX - perpendicularX, y = outerY - perpendicularY},
            {x = innerX - perpendicularX * 0.2, y = innerY - perpendicularY * 0.2}
        })
    end
end

local textureLookup = {
    radial = materials.Radial,
    slashes = materials.Slashes,
    fragments = materials.Fragments
}

local function DrawExposureOverlay(instance, exposure, art, localProgress, effectScale, usedShader, maskAvailable, maskEnabled, focusX, focusY, directionX, directionY, screenWidth, screenHeight)
    local paper = exposure.Paper or instance.Paper
    local ink = exposure.Ink or instance.Ink
    local directionDegrees = math.deg(math.atan2(directionY, directionX))

    if not usedShader then
        local sceneMix = 1 - (1 - (tonumber(exposure.SceneMix) or 0)) * effectScale
        surface.SetDrawColor(paper.r, paper.g, paper.b, 255 * (1 - sceneMix))
        surface.DrawRect(0, 0, screenWidth, screenHeight)
    end

    local texture = textureLookup[exposure.Texture]
    local textureAlpha = 255 * (tonumber(exposure.TextureAlpha) or 0) * effectScale
    if texture and not texture:IsError() and textureAlpha > 0 then
        local scale = (tonumber(exposure.TextureScale) or 1.05) * art.TextureScale
        local materialAspect = math.max(texture:Width(), 16) / math.max(texture:Height(), 9)
        local width = screenWidth * scale
        local height = width / materialAspect
        if height < screenHeight * scale then
            height = screenHeight * scale
            width = height * materialAspect
        end

        local color = exposure.TextureColor or ink
        surface.SetMaterial(texture)
        surface.SetDrawColor(color.r, color.g, color.b, textureAlpha)
        surface.DrawTexturedRectRotated(
            focusX,
            focusY,
            width,
            height,
            directionDegrees + instance.Rotation + art.Rotation
                + (tonumber(exposure.TextureRotation) or 0)
        )
    end

    DrawEnergyRibbons(
        instance,
        exposure,
        art,
        localProgress,
        effectScale,
        focusX,
        focusY,
        directionX,
        directionY,
        screenWidth,
        screenHeight
    )

    DrawSpeedLines(
        instance,
        exposure,
        art,
        exposure.LineColor or ink,
        255 * (tonumber(exposure.LineAlpha) or 0) * effectScale,
        focusX,
        focusY,
        directionX,
        directionY,
        screenWidth,
        screenHeight
    )

    if not usedShader and maskAvailable and maskEnabled then
        DrawMask(maskSurfaces.Attacker, 255, screenWidth, screenHeight)
        DrawMask(maskSurfaces.Victim, 255, screenWidth, screenHeight)
    end

    DrawAsymmetricContactCore(
        instance,
        exposure,
        art,
        effectScale,
        focusX,
        focusY,
        directionX,
        directionY,
        screenHeight
    )

    DrawContactStar(
        exposure,
        art,
        255 * (tonumber(exposure.StarAlpha) or 1) * effectScale,
        focusX,
        focusY,
        directionX,
        directionY,
        screenHeight
    )
end

function Renderer.Prepare(instance)
    BuildExposureArt(instance)
end

function Renderer.DrawPostProcess(instance, now)
    local exposure, art, localProgress, effectScale = GetExposureState(instance, now)
    local screenWidth = ScrW()
    local screenHeight = ScrH()
    local focusX, focusY, directionX, directionY = ResolveComposition(instance, screenWidth, screenHeight)
    focusX, focusY, directionX, directionY = ApplyExposureJitter(
        instance,
        art,
        focusX,
        focusY,
        directionX,
        directionY,
        screenWidth,
        screenHeight
    )
    local usedShader = false
    local maskAvailable = true
    local maskEnabled = false

    if effectScale > 0.005 then
        maskAvailable, maskEnabled = RenderDualMasks(instance, exposure, effectScale)
        usedShader = DrawShaderPass(
            instance,
            exposure,
            effectScale,
            focusX,
            focusY,
            directionX,
            directionY,
            maskAvailable,
            maskEnabled
        )
        if not usedShader then DrawFallbackPostProcess(exposure, effectScale) end
    end

    instance.LastRenderState = {
        FrameNumber = FrameNumber(),
        Exposure = exposure,
        Art = art,
        LocalProgress = localProgress,
        EffectScale = effectScale,
        FocusX = focusX,
        FocusY = focusY,
        DirectionX = directionX,
        DirectionY = directionY,
        ScreenWidth = screenWidth,
        ScreenHeight = screenHeight,
        UsedShader = usedShader,
        MaskAvailable = maskAvailable,
        MaskEnabled = maskEnabled
    }
end

function Renderer.DrawOverlay(instance, now)
    local state = instance.LastRenderState
    if not state or state.FrameNumber ~= FrameNumber() then
        local exposure, art, localProgress, effectScale = GetExposureState(instance, now)
        local screenWidth = ScrW()
        local screenHeight = ScrH()
        local focusX, focusY, directionX, directionY = ResolveComposition(instance, screenWidth, screenHeight)
        focusX, focusY, directionX, directionY = ApplyExposureJitter(
            instance,
            art,
            focusX,
            focusY,
            directionX,
            directionY,
            screenWidth,
            screenHeight
        )
        state = {
            Exposure = exposure,
            Art = art,
            LocalProgress = localProgress,
            EffectScale = effectScale,
            FocusX = focusX,
            FocusY = focusY,
            DirectionX = directionX,
            DirectionY = directionY,
            ScreenWidth = screenWidth,
            ScreenHeight = screenHeight,
            UsedShader = false,
            MaskAvailable = false,
            MaskEnabled = false
        }
    end

    DrawExposureOverlay(
        instance,
        state.Exposure,
        state.Art,
        state.LocalProgress,
        state.EffectScale,
        state.UsedShader,
        state.MaskAvailable,
        state.MaskEnabled,
        state.FocusX,
        state.FocusY,
        state.DirectionX,
        state.DirectionY,
        state.ScreenWidth,
        state.ScreenHeight
    )
end

function Renderer.IsShaderAvailable()
    return CanUseShader({ShaderFailed = false})
end

return Renderer

