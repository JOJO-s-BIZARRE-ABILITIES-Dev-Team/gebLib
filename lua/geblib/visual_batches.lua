if SERVER then return end

local Visuals = gebLib.Visuals

local BeamBatch = {}
BeamBatch.__index = BeamBatch

function BeamBatch.New(material)
    return setmetatable({
        Material = isstring(material) and Material(material) or material,
        Count = 0,
        Points = {},
        Widths = {},
        Textures = {},
        Colors = {},
    }, BeamBatch)
end

function BeamBatch:AddUnpacked(x, y, z, width, textureCoordinate, color)
    local index = self.Count + 1
    local point = self.Points[index]
    local storedColor = self.Colors[index]
    if not point then
        point = Vector()
        storedColor = Color(0, 0, 0, 0)
        self.Points[index] = point
        self.Colors[index] = storedColor
    end
    point:SetUnpacked(x, y, z)
    storedColor.r = color.r
    storedColor.g = color.g
    storedColor.b = color.b
    storedColor.a = color.a
    self.Widths[index] = width
    self.Textures[index] = textureCoordinate
    self.Count = index
    return self
end

function BeamBatch:Add(position, width, textureCoordinate, color)
    return self:AddUnpacked(
        position.x,
        position.y,
        position.z,
        width,
        textureCoordinate,
        color
    )
end

function BeamBatch:BreakUnpacked(x, y, z)
    if self.Count == 0 then return self end
    local previous = self.Colors[self.Count]
    local alpha = previous.a
    previous.a = 0
    self:Add(self.Points[self.Count], 0, 0, previous)
    self:AddUnpacked(x, y, z, 0, 0, previous)
    previous.a = alpha
    return self
end

function BeamBatch:Break(position)
    return self:BreakUnpacked(position.x, position.y, position.z)
end

function BeamBatch:AddSegment(startPosition, endPosition, width, color)
    self:Break(startPosition)
    self:Add(startPosition, width, 0, color)
    self:Add(endPosition, width, 1, color)
    return self
end

function BeamBatch:Reset()
    self.Count = 0
    return self
end

function BeamBatch:Flush(material)
    local count = self.Count
    if count < 2 then self.Count = 0 return false end
    render.SetMaterial(material or self.Material)
    render.StartBeam(count)
    for index = 1, count do
        render.AddBeam(
            self.Points[index],
            self.Widths[index],
            self.Textures[index],
            self.Colors[index]
        )
    end
    render.EndBeam()
    self.Count = 0
    return true
end

local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch

function SpriteBatch.New(material)
    return setmetatable({
        Material = isstring(material) and Material(material) or material,
        Count = 0,
        Positions = {},
        Widths = {},
        Heights = {},
        Colors = {},
    }, SpriteBatch)
end

function SpriteBatch:AddUnpacked(x, y, z, width, height, color)
    local index = self.Count + 1
    local storedPosition = self.Positions[index]
    local storedColor = self.Colors[index]
    if not storedPosition then
        storedPosition = Vector()
        storedColor = Color(0, 0, 0, 0)
        self.Positions[index] = storedPosition
        self.Colors[index] = storedColor
    end
    storedPosition:SetUnpacked(x, y, z)
    storedColor.r = color.r
    storedColor.g = color.g
    storedColor.b = color.b
    storedColor.a = color.a
    self.Widths[index] = width
    self.Heights[index] = height or width
    self.Count = index
    return self
end

function SpriteBatch:Add(position, width, height, color)
    return self:AddUnpacked(position.x, position.y, position.z, width, height, color)
end

function SpriteBatch:Reset()
    self.Count = 0
    return self
end

function SpriteBatch:Flush(material)
    if self.Count == 0 then return false end
    render.SetMaterial(material or self.Material)
    for index = 1, self.Count do
        render.DrawSprite(
            self.Positions[index],
            self.Widths[index],
            self.Heights[index],
            self.Colors[index]
        )
    end
    self.Count = 0
    return true
end

Visuals.BeamBatch = BeamBatch
Visuals.SpriteBatch = SpriteBatch
