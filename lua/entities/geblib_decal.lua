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
            local mins, maxs =  self:GetRenderBounds()
            self:SetRenderBounds( mins * new, maxs * new )
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
        self:SetDecalSize( Lerp( math.ease.InOutSine( FrameTime() * (self.m_AnimSpeed) ), self:GetDecalSize(), self.m_DesiredSize ) )
    end

    local lifeTime = self:GetLifeTime()
    if CurTime() > lifeTime then
        self:Remove()
    end
end

local noMat = Material("matsys_regressiontest/background")
function ENT:DrawTranslucent()
    local decalSize = self:GetDecalSize()
    local size = Vector(decalSize,decalSize,0)

    local color = self:GetColor() or color_white
    local decal = self.m_DecalMat or noMat

    local lifeTime = self:GetLifeTime()

    render.SetMaterial( decal )

    local blend = 1
    if CurTime() > lifeTime - 1 then
        blend = Lerp( math.abs( lifeTime - CurTime() - 1 ) / 1, 1, 0 )
    end
    color.a = color.a * blend

    render.DrawBox( self:GetPos(), self:GetAngles(), size, -size, color )
end

function ENT:SetDecal(path)
    self:SetDecalToRender(path)
end

function ENT:DoAnimation(bool, speed)
    if bool then
        self.m_DesiredSize = self:GetDecalSize()
        self:SetDecalSize( 0 )
    else
        self:SetDecalSize( self.m_DesiredSize )
        self.m_DesiredSize = nil
    end
    
    self.m_DoAnim = bool or true
    self.m_AnimSpeed = speed or 18
end