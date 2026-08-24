AddCSLuaFile()

ENT.PrintName = "Geblib Decal"
ENT.Type = "anim"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT   

function ENT:SetupDataTables()
    self:NetworkVar("Float", "LifeTime")
    self:NetworkVar("Float", "DecalSize")
    self:NetworkVarNotify( "DecalSize", function(self, name, old, new) 
        if CLIENT then
            local size = math.abs(new)
            self:SetRenderBounds(Vector(-size, -size, -1), Vector(size, size, 1))
        end
    end)
    self:NetworkVar("String", "DecalToRender")
    self:NetworkVarNotify( "DecalToRender", function(self, name, old, new) 
        if CLIENT then
            self.m_DecalMat = Material(new)
        end
    end)
end

function ENT:Initialize()
    local angles = self:GetAngles()
    local randomAngle = Angle(angles.x, angles.y, angles.z)
    self:SetAngles(randomAngle)

    self:DrawShadow(false)
end

function ENT:Draw()

end

function ENT:Think()
    if self.m_DoAnim then
        local progress = math.Clamp(FrameTime() * self.m_AnimSpeed, 0, 1)
        local size = Lerp(math.ease.InOutSine(progress), self:GetDecalSize(), self.m_DesiredSize)
        if math.abs(size - self.m_DesiredSize) < 0.01 then
            size = self.m_DesiredSize
            self.m_DoAnim = false
        end
        self:SetDecalSize(size)
    end

    local lifeTime = self:GetLifeTime()
    if CurTime() > lifeTime then
        self:Remove()
    end
end

local noMat = Material("matsys_regressiontest/background")
function ENT:DrawTranslucent()
    local decalSize = math.abs(self:GetDecalSize())
    local size = Vector(decalSize,decalSize,0)

    local currentColor = self:GetColor() or color_white
    local color = Color(currentColor.r, currentColor.g, currentColor.b, currentColor.a)
    local decal = self.m_DecalMat or noMat

    local lifeTime = self:GetLifeTime()

    render.SetMaterial( decal )

    local blend = 1
    if CurTime() > lifeTime - 1 then
        blend = Lerp(math.Clamp(math.abs(lifeTime - CurTime() - 1), 0, 1), 1, 0)
    end
    color.a = color.a * blend

    render.DrawBox( self:GetPos(), self:GetAngles(), -size, size, color )
end

function ENT:SetDecal(path)
    self:SetDecalToRender(path)
end

function ENT:DoAnimation(bool, speed)
    if bool == nil then bool = true end

    if bool then
        self.m_DesiredSize = self:GetDecalSize()
        self:SetDecalSize( 0 )
    elseif self.m_DesiredSize then
        self:SetDecalSize( self.m_DesiredSize )
        self.m_DesiredSize = nil
    end
    
    self.m_DoAnim = bool
    self.m_AnimSpeed = speed or 18
end
