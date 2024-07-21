local PANEL = {}

function PANEL:Init()
	self.Skills = {}
	self.OriginX = self:GetWide() / 2
	self.OriginY = self:GetTall() / 2
end

function PANEL:PostInit()
	self.PostInitialized = true
end

function PANEL:Think()
	if ! self.PostInitialized then
		self:PostInit()
	end
end

function PANEL:Paint(w, h)
	for k, skill in ipairs(self.Skills) do
		local parentSkill = skill.ParentSkill

		if IsValid(parentSkill) then
			local skill1X, skill1Y = parentSkill:GetPos()
			local skill2X, skill2Y = skill:GetPos()

			skill1X = skill1X + (parentSkill:GetWide() / 2)
			skill1Y = skill1Y + (parentSkill:GetTall() / 2)

			skill2X = skill2X + (skill:GetWide() / 2)
			skill2Y = skill2Y + (skill:GetTall() / 2)

			surface.DrawLine(skill1X, skill1Y, skill2X, skill2Y)
		end
	end
end

function PANEL:OnRemove()
	for k, v in ipairs(self.Skills) do
		v:Remove()
	end
end

function PANEL:AddSkill()
	local skill = vgui.Create("gebLib.Skill", self)
	skill.tableIndex = table.insert(self.Skills, skill)
	skill:MoveToFront()

	return skill
end

function PANEL:SetOrigin(x, y)
	self.OriginX = x
	self.OriginY = y
end

derma.DefineControl("gebLib.SkillTree", "", PANEL, "Panel")
