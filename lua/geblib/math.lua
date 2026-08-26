gebLib.Math = gebLib.Math or {}

local Math = gebLib.Math

function Math.SmoothStep(value)
    value = math.Clamp(tonumber(value) or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

function Math.Horizontal(vector, output)
    output = output or Vector()
    output:SetUnpacked(vector.x, vector.y, 0)
    return output
end

function Math.SafeDirection(vector, fallback, output)
    output = output or Vector()
    if vector and vector:LengthSqr() > 0.0001 then
        output:SetUnpacked(vector.x, vector.y, vector.z)
    else
        fallback = fallback or vector_up
        output:SetUnpacked(fallback.x, fallback.y, fallback.z)
    end
    output:Normalize()
    return output
end

function Math.DistanceFalloff(distance, radius, exponent)
    radius = math.max(tonumber(radius) or 0, 0.0001)
    local falloff = 1 - math.Clamp((tonumber(distance) or 0) / radius, 0, 1)
    exponent = tonumber(exponent) or 1
    if exponent ~= 1 then falloff = falloff ^ math.max(exponent, 0.0001) end
    return falloff
end
