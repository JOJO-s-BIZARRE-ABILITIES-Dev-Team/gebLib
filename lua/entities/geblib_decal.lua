AddCSLuaFile()

ENT.PrintName = "gebLib Decal"
ENT.Type = "anim"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local fallbackMaterial = Material("matsys_regressiontest/background")

function ENT:Initialize()
    self:DrawShadow(false)
    self.gebLib_DecalSize = self.gebLib_DecalSize or 32
    self.gebLib_LifeTime = self.gebLib_LifeTime or CurTime() + 3
    self:SetDecalSize(self.gebLib_DecalSize)
end

function ENT:SetDecal(path)
    self.gebLib_DecalMaterial = Material(path)
end

function ENT:SetDecalSize(size)
    size = math.abs(size)
    self.gebLib_DecalSize = size
    self:SetRenderBounds(Vector(-size, -size, -1), Vector(size, size, 1))
end

function ENT:GetDecalSize()
    return self.gebLib_DecalSize or 0
end

function ENT:SetLifeTime(time)
    self.gebLib_LifeTime = time
end

function ENT:GetLifeTime()
    return self.gebLib_LifeTime or 0
end

function ENT:DoAnimation(animate, speed)
    if animate == nil then animate = true end

    if animate then
        self.gebLib_DesiredSize = self:GetDecalSize()
        self:SetDecalSize(0)
    elseif self.gebLib_DesiredSize then
        self:SetDecalSize(self.gebLib_DesiredSize)
        self.gebLib_DesiredSize = nil
    end

    self.gebLib_Animating = animate
    self.gebLib_AnimationSpeed = speed or 18
end

function ENT:Think()
    if self.gebLib_Animating then
        local progress = math.Clamp(FrameTime() * self.gebLib_AnimationSpeed, 0, 1)
        local size = Lerp(math.ease.InOutSine(progress), self:GetDecalSize(), self.gebLib_DesiredSize)

        if math.abs(size - self.gebLib_DesiredSize) < 0.01 then
            size = self.gebLib_DesiredSize
            self.gebLib_Animating = false
        end

        self:SetDecalSize(size)
    end

    if CurTime() >= self:GetLifeTime() then
        self:Remove()
    end
end

function ENT:DrawTranslucent()
    local size = Vector(self:GetDecalSize(), self:GetDecalSize(), 0)
    local color = self:GetColor()
    local remaining = self:GetLifeTime() - CurTime()

    if remaining < 1 then
        color = Color(color.r, color.g, color.b, color.a * math.Clamp(remaining, 0, 1))
    end

    render.SetMaterial(self.gebLib_DecalMaterial or fallbackMaterial)
    render.DrawBox(self:GetPos(), self:GetAngles(), -size, size, color)
end
