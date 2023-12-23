local PANEL = {}

PANEL.Color = Color(255, 255, 255)
PANEL.Alpha = 255
PANEL.HoverAlpha = 50
PANEL.Focus = false

function PANEL:Init()
    self.Nodes = {}
	self:SetText("")
end

function PANEL:PostInit()
	self.DefaultW, self.DefaultH = self:GetSize()
	self.DefaultX, self.DefaultY = self:GetPos()

	self.PostInitialized = true
end

function PANEL:Think()
	if not self.PostInitialized then
		self:PostInit()
	end
end

function PANEL:Paint(w, h)
    local Poly = {
        { x = w / 2, y = 0 },
        { x = 0 + w, y = 0 + h / 2 },
        { x = w / 2, y = 0 + h },
        { x = 0, y = 0 + h / 2 },
    }

    self:SetPos( self.DefaultX + self.DefaultW / 2 - w / 2, self.DefaultY + self.DefaultH / 2 - h / 2 )

    surface.SetDrawColor( self.Color ) 
	draw.NoTexture()
	surface.DrawPoly( Poly )
end

function PANEL:DoClick()
	local originX, originY = self:GetParent().OriginX, self:GetParent().OriginY

	for k, skill in ipairs( self:GetParent().Skills ) do
		local defX = skill.DefaultX
		local defY = skill.DefaultY
		skill:MoveTo( originX, originY, 1 )

		skill.DefaultX = originX
		skill.DefaultY = originY
	end
end

function PANEL:OnCursorEntered()
	self.Focus = true
	self:SizeTo( self.DefaultW * 1.2, self.DefaultH * 1.2, 0.1, 0, 2 )
	self:AlphaTo( self.HoverAlpha, 0.1 )
end

function PANEL:OnCursorExited()
	self.Focus = false
	self:SizeTo( self.DefaultW, self.DefaultH, 0.1 )
	self:AlphaTo( self.Alpha, 0.1 )
end

function PANEL:OnRemove()
end

function PANEL:ConnectTo( panel )
	if !IsValid( panel ) then error( "Trying to connect to non-valid panel!") return end
	self.ParentSkill = panel
end

derma.DefineControl( "gebLib.Skill", "", PANEL, "DButton" )
