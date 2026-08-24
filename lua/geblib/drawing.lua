gebLib.Drawing = gebLib.Drawing or {}
local Drawing = gebLib.Drawing

function Drawing.Circle(x, y, radius, color, progress, angle, segments)
    progress = math.Clamp(progress or 100, 0, 100) / 100
    angle = angle or 180
    segments = math.max(3, segments or 100)

    local centerX = x + radius
    local centerY = y + radius
    local vertices = {{x = centerX, y = centerY}}

    for index = 0, segments do
        local radians = math.rad((index / segments) * (-360 * progress) + angle)
        vertices[#vertices + 1] = {
            x = centerX + math.sin(radians) * radius,
            y = centerY + math.cos(radians) * radius,
        }
    end

    vertices[#vertices + 1] = {x = centerX, y = centerY}

    draw.NoTexture()
    surface.SetDrawColor(color)
    surface.DrawPoly(vertices)
end

function Drawing.CircularBar(x, y, progress, radius, thickness, angle, color)
    render.SetStencilWriteMask(0xFF)
    render.SetStencilTestMask(0xFF)
    render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_NEVER)
    render.SetStencilFailOperation(STENCIL_REPLACE)

    Drawing.Circle(
        x - (radius - thickness),
        y - (radius - thickness),
        radius - thickness,
        color_white,
        100
    )

    render.SetStencilCompareFunction(STENCIL_GREATER)
    render.SetStencilFailOperation(STENCIL_KEEP)
    Drawing.Circle(x - radius, y - radius, radius, color, progress, angle)
    render.SetStencilEnable(false)
end

function Drawing.TextWithShadow(text, font, x, y, color, horizontalAlign, verticalAlign, shadowColor)
    shadowColor = shadowColor or color_black
    draw.SimpleText(text, font, x + 1.5, y + 1.5, shadowColor, horizontalAlign, verticalAlign)
    return draw.SimpleText(text, font, x, y, color, horizontalAlign, verticalAlign)
end
