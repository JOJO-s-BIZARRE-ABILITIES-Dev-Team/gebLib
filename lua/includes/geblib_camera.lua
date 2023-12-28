if SERVER then return end

gebLib_Camera = {}
gebLib_Camera.__index = gebLib_Camera

--------------------
--Contributors: T0M
--------------------

--Helper functions
local function RenderOverride(self)
	self:DrawModel()
	self:FrameAdvance()
end

--Constructor
function gebLib_Camera.New(name, ply, fps, maxFrames, createFake, useDefaultHooks)
	if createFake == nil then createFake = true end
	if useDefaultHooks == nil then useDefaultHooks = true end
	if fps == nil then fps = 60 end
	if maxFrames and maxFrames < 0 then maxFrames = nil end
	
    self = setmetatable({}, gebLib_Camera)

    self.Name = name
    self.Player = ply
    self.FPS = fps --Recommended is 60
    self.MaxFrames = maxFrames
    self.Events = {}
    self.FrameChecks = {}

    self.Playing = false
	self.Simulated = false
    self.ThinkName = nil
    self.EndFunc = nil
    self.ThinkFunc = nil
	self.UseDefaultHooks = useDefaultHooks

    self.CurFrame = 0
    self.Start = 0
    self.LastTime = 0
	self.Copy = NULL

	self.OldPos = nil
	self.OldAng = nil

    self.LastPos = vector_origin
    self.LastAng = angle_zero

	if createFake then
		self:AddFakePlayerCopy()
	end

    return self
end

--General Functions
function gebLib_Camera:Play(simulate)
    self.Playing = true
    self.Start = SysTime()
    self.ThinkName = tostring(self)
	self.Simulated = simulate

	self:AddDefaultHooks()

    --Reset event start times
    for frame, data in pairs(self.Events) do
        data.Start = SysTime()
    end

	-- If user has not specified the ending frame of the camera, then try to figure it from events
	if not self.MaxFrames then
		local largestEventFrame = -1
	
		for frame, data in pairs(self.Events) do
			if data.EndFrame > largestEventFrame then
				largestEventFrame = data.EndFrame
			end
		end

		self.MaxFrames = largestEventFrame
	end
    
    if not simulate then
        hook.Add("CalcView", self.ThinkName, function(ply, pos, angles, fov)
            if not self.Player:IsValid() then self:Stop() return end
            
            self.CurFrame = (SysTime() - self.Start) * self.FPS
            local view = {
                origin = pos,
                angles = angles,
                fov = fov,
                drawviewer = true
            }
            if self.ThinkFunc and self.Playing then
                self.ThinkFunc(self)
            end
            
            for frame, data in pairs(self.Events) do
                if not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame <= data.EndFrame then
                    view.origin, view.angles = data.Function(ply, pos, angles, fov)
                elseif not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame >= data.EndFrame then
                    data.Ended = true
                end
            end
            
            if self.CurFrame >= self.MaxFrames then
                self.EndFunc(self)
                self:Stop()
            end
            
            self.LastPos = view.origin
            self.LastAng = view.angles
            return view
        end, HOOK_HIGH)
    else --For other players, simulate the camera behaviour, so everything is properly synced
        hook.Add("Think", self.ThinkName, function()
            if not self.Player:IsValid() then self:Stop() return end

            self.CurFrame = (SysTime() - self.Start) * self.FPS
            local ply = self.Player
            local pos = vector_origin
            local angles = angle_zero
            local fov = 70

            if self.ThinkFunc and self.Playing then
                self.ThinkFunc(self)
            end
    
            for frame, data in pairs(self.Events) do
                if not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame <= data.EndFrame then
                    data.Function(ply, pos, angles, fov)
                elseif not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame >= data.EndFrame then
                    data.Ended = true
                end
            end
            
            if self.CurFrame >= self.MaxFrames then
                self:Stop()
            end
        end)
    end
end

function gebLib_Camera:Stop()
	self:RemoveDefaultHooks()
    self.EndFunc(self)

    self.Playing = false

	self.Player:SetNoDraw(false)
	self.Copy:Remove()
end

function gebLib_Camera:SetThink(func)
    self.ThinkFunc = func
end

function gebLib_Camera:SetEnd(func)
    self.EndFunc = func
end

function gebLib_Camera:AddEvent(initFrame, endFrame, func)
	if endFrame == nil or endFrame < 0 then
		endFrame = self.MaxFrames
	end

    self.Events[initFrame] = {Function = func, Ended = false, EndFrame = endFrame, Start = 0}
end

function gebLib_Camera:AddFakePlayerCopy()
	local ply = self.Player
    
    --Experimental
    local angles = ply:GetAimVector():Angle()
    angles:Normalize()
    angles.x = 0

	local oldPos = ply:GetPos()

	self.OldPos = oldPos
	self.OldAng = angles

	local copy = ClientsideModel(ply:GetModel())
    copy:SetPos(oldPos)
    copy:SetAngles(angles)
    copy:SetSkin(ply:GetSkin())
    copy:SetPlaybackRate(1)
	copy:SetBodygroup(1, 1)
	copy:SetSequence(ply:GetSequence())
	copy.RenderOverride = RenderOverride
	self.Copy = copy
end

function gebLib_Camera:AddDefaultHooks()
	if SERVER then return end
	if not self.UseDefaultHooks then return end

	local screenWidth = ScrW()
	local screenHeight = ScrH()
	local blackBarSize = screenHeight * 0.09
	local bottomPos = screenHeight - blackBarSize + 1

	local start = SysTime()
	local animDuration = 1 

	if not self.Simulated then
		hook.Add("DrawOverlay", tostring(self) .. "_BlackBars", function()
			local lerpedSize = Lerp((SysTime() - start) / animDuration, 0, blackBarSize)
			local lerpedBottom = Lerp((SysTime() - start) / animDuration, screenHeight + 1, bottomPos) --Need to lerp the bottom pos, so it goes from down to up
	
			surface.SetDrawColor(color_black)
			surface.DrawRect(0, 0, screenWidth, lerpedSize)
			surface.DrawRect(0, lerpedBottom, screenWidth, lerpedSize)
		end)
		
		hook.Add("HUDShouldDraw", tostring(self) .. "_NoHud", function()
			return false
		end)
	end

	hook.Add("Think", tostring(self) .. "_DefaultThink", function()
		local owner = self.Player

		if not self:IsValid() then self:Stop() return end

        owner:SetNoDraw(true)
        owner:SetEyeAngles(self.OldAng)
        owner:SetPos(self.OldPos)
	end)
end

function gebLib_Camera:RemoveDefaultHooks()
	hook.Remove("DrawOverlay", tostring(self) .. "_BlackBars")
	hook.Remove("HUDShouldDraw", tostring(self) .. "_NoHud")
	hook.Remove("Think", tostring(self) .. "_DefaultThink")

	hook.Remove("CalcView", self.ThinkName)
    hook.Remove("Think", self.ThinkName)
end

--Helper Functions
--Returns the time based on the fps, end frame and the current frame, this should be used with every lerp function.
--Formula for creating this
--(SysTime() - someTimeBefore) / (eventLength / cameraFPS)
function gebLib_Camera:GetTime(startFrame, endFrame, mult)
    mult = mult or 1

    local result = math.Remap(self.CurFrame, startFrame, endFrame, 0, 1)
    return math.Clamp(result * mult, 0, 1)
end

--Used for one time logic in the current cinematic
--- if (Camera:FrameFirstTime(50)) then do stuff will only run once when the frame first ran
function gebLib_Camera:FrameFirstTime(frame)
    if self.CurFrame >= frame and not self.FrameChecks[frame] then
        self.FrameChecks[frame] = true
        return true
    end

    return false
end

function gebLib_Camera:IsValid()
	return self.Player:IsValid() and self.Player:Alive()
end

function gebLib_Camera:__tostring()
	return self.Name .. "_" .. tostring(self.Player)
end
