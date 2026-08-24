gebLib.Camera = {}
gebLib.Camera.__index = gebLib.Camera

local Camera = gebLib.Camera
gebLib._NextCameraId = gebLib._NextCameraId or 0

--------------------
--Contributors: T0M
--------------------

--Helper functions
local function RenderOverride(self)
	self:DrawModel()
	self:FrameAdvance()
end

--Constructor
function Camera.New(name, ply, fps, maxFrames, createFake, useDefaultHooks)
	if not IsValid(ply) or not ply:IsPlayer() then
		error("Cannot create a gebLib camera for an invalid player")
	end

	if createFake == nil then createFake = true end
	if useDefaultHooks == nil then useDefaultHooks = true end
	if fps == nil then fps = 60 end
	if not isnumber(fps) or fps <= 0 then
		error("camera fps must be greater than zero", 2)
	end
	if maxFrames ~= nil and not isnumber(maxFrames) then
		error("camera max frames must be a number", 2)
	end
	if maxFrames and maxFrames < 0 then maxFrames = nil end
	name = tostring(name or "camera")
	
    local self = setmetatable({}, Camera)
    gebLib._NextCameraId = gebLib._NextCameraId + 1

    self.Name = name
    self.Player = ply
    self.FPS = fps --Recommended is 60
    self.MaxFrames = maxFrames
    self.Events = {}
    self.FrameChecks = {}

    self.Playing = false
	self.Simulated = false
    self.ThinkName = nil
    self.HookName = "gebLib.Camera." .. gebLib._NextCameraId
    self.EndFunc = nil
    self.ThinkFunc = nil
	self.UseDefaultHooks = useDefaultHooks
	self.CreateFake = createFake

    self.CurFrame = 0
    self.Start = 0
    self.LastTime = 0
	self.Copy = NULL

	self.OldPos = nil
	self.OldAng = nil
	self.OriginalNoDraw = nil

    self.LastPos = vector_origin
    self.LastAng = angle_zero

    return self
end

--General Functions
function Camera:Play(simulate)
    if self.Playing or not self:IsValid() then return false end

	local maxFrames = self.MaxFrames
	if maxFrames == nil then
		for _, event in pairs(self.Events) do
			if maxFrames == nil or event.EndFrame > maxFrames then
				maxFrames = event.EndFrame
			end
		end
	end

	if maxFrames == nil then
		error("camera requires maxFrames or at least one event", 2)
	end

	self.MaxFrames = maxFrames
    self.Playing = true
    self.Start = SysTime()
    self.ThinkName = self.HookName
	self.Simulated = simulate
	self.FrameChecks = {}

	if CLIENT and self.CreateFake and not IsValid(self.Copy) then
		self:AddFakePlayerCopy()
	end

    --Reset event start times
    for frame, data in pairs(self.Events) do
        data.Start = SysTime()
        data.Ended = false
    end

	self:AddDefaultHooks()

	if SERVER then
		hook.Add("Think", self.ThinkName, function()
			if not self:IsValid() then self:Stop() return end

			self.CurFrame = (SysTime() - self.Start) * self.FPS

			if self.ThinkFunc and self.Playing then
                self.ThinkFunc(self)
            end

			if self.CurFrame >= self.MaxFrames then
                self:Stop()
            end
		end)

		return true
	end
    
    if not simulate then
        hook.Add("CalcView", self.ThinkName, function(ply, pos, angles, fov)
            if not IsValid(self.Player) then self:Stop() return end
            
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
                    local origin, viewAngles = data.Function(ply, pos, angles, fov)
                    if origin then view.origin = origin end
                    if viewAngles then view.angles = viewAngles end
                    if not self.Playing then return view end
                elseif not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame >= data.EndFrame then
                    data.Ended = true
                end
            end
            
            if self.CurFrame >= self.MaxFrames then
                self:Stop()
            end
            
            self.LastPos = view.origin
            self.LastAng = view.angles
            return view
        end)
    else --For other players, simulate the camera behaviour, so everything is properly synced
        hook.Add("Think", self.ThinkName, function()
            if not IsValid(self.Player) then self:Stop() return end

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
                    if not self.Playing then return end
                elseif not data.Ended and data.Function and self.CurFrame >= frame and self.CurFrame >= data.EndFrame then
                    data.Ended = true
                end
            end
            
            if self.CurFrame >= self.MaxFrames then
                self:Stop()
            end
        end)
    end

	return true
end

function Camera:Stop()
    if not self.Playing then return false end

	self.Playing = false
	self:RemoveDefaultHooks()

	if CLIENT and IsValid(self.Player) and self.OriginalNoDraw ~= nil then
		self.Player:SetNoDraw(self.OriginalNoDraw)
		self.OriginalNoDraw = nil
	end
	if CLIENT and IsValid(self.Copy) then
		self.Copy:Remove()
	end

	if self.EndFunc then
		self.EndFunc(self)
	end

	return true
end

function Camera:SetThink(func)
	if func ~= nil and not isfunction(func) then
		error("camera think callback must be a function", 2)
	end
    self.ThinkFunc = func
end

function Camera:SetEnd(func)
	if func ~= nil and not isfunction(func) then
		error("camera end callback must be a function", 2)
	end
    self.EndFunc = func
end

function Camera:AddEvent(initFrame, endFrame, func)
	if not isnumber(initFrame) or initFrame < 0 then
		error("camera event start frame must be zero or greater", 2)
	end

	if endFrame == nil then
		endFrame = self.MaxFrames or initFrame
	end

	if not isnumber(endFrame) then
		error("camera event end frame must be a number", 2)
	end

	if endFrame < 0 then
		endFrame = self.MaxFrames or initFrame
	end

	if endFrame < initFrame then
		error("camera event end frame must not precede its start frame", 2)
	end

	if not isfunction(func) then
		error("camera event callback must be a function", 2)
	end

    self.Events[initFrame] = {Function = func, Ended = false, EndFrame = endFrame, Start = 0}
end

function Camera:AddFakePlayerCopy()
	if not CLIENT then return false end

	local ply = self.Player
    
    local angles = ply:GetAimVector():Angle()
    angles:Normalize()
    angles.x = 0

	local oldPos = ply:GetPos()

	self.OldPos = oldPos
	self.OldAng = angles

	local copy = ClientsideModel(ply:GetModel())
	if not IsValid(copy) then return false end

    copy:SetPos(oldPos)
    copy:SetAngles(angles)
	copy:DrawShadow(true)
    copy:SetSkin(ply:GetSkin())
    copy:SetPlaybackRate(1)
	copy:SetSequence(ply:GetSequence())
	copy.RenderOverride = RenderOverride
	self.Copy = copy
	return true
end

function Camera:AddDefaultHooks()
	if SERVER then return end
	if not self.UseDefaultHooks then return end

	local screenWidth = ScrW()
	local screenHeight = ScrH()
	local blackBarSize = screenHeight * 0.09
	local bottomPos = screenHeight - blackBarSize + 1

	local start = SysTime()
	local animDuration = 1 

	if not self.Simulated then
		hook.Add("DrawOverlay", self.HookName .. "_BlackBars", function()
			local progress = math.Clamp((SysTime() - start) / animDuration, 0, 1)
			local lerpedSize = Lerp(progress, 0, blackBarSize)
			local lerpedBottom = Lerp(progress, screenHeight + 1, bottomPos) --Need to lerp the bottom pos, so it goes from down to up
	
			surface.SetDrawColor(color_black)
			surface.DrawRect(0, 0, screenWidth, lerpedSize)
			surface.DrawRect(0, lerpedBottom, screenWidth, lerpedSize)
		end)
		
		hook.Add("HUDShouldDraw", self.HookName .. "_NoHud", function()
			return false
		end)
	end

	hook.Add("Think", self.HookName .. "_DefaultThink", function()
		local owner = self.Player

		if not self:IsValid() then self:Stop() return end

		if IsValid(self.Copy) then
			if self.OriginalNoDraw == nil then
				self.OriginalNoDraw = owner:GetNoDraw()
			end

			owner:SetNoDraw(true)
		end
		if self.OldAng then owner:SetEyeAngles(self.OldAng) end
		if self.OldPos then owner:SetPos(self.OldPos) end
	end)
end

function Camera:RemoveDefaultHooks()
	hook.Remove("DrawOverlay", self.HookName .. "_BlackBars")
	hook.Remove("HUDShouldDraw", self.HookName .. "_NoHud")
	hook.Remove("Think", self.HookName .. "_DefaultThink")

	if self.ThinkName then
		hook.Remove("CalcView", self.ThinkName)
		hook.Remove("Think", self.ThinkName)
	end
end

--Helper Functions
--Returns the time based on the fps, end frame and the current frame, this should be used with every lerp function.
--Formula for creating this
--(SysTime() - someTimeBefore) / (eventLength / cameraFPS)
function Camera:GetTime(startFrame, endFrame, mult)
    mult = mult or 1

    local result = math.Remap(self.CurFrame, startFrame, endFrame, 0, 1)
    return math.Clamp(result * mult, 0, 1)
end

--Used for one time logic in the current cinematic
--- if (Camera:FrameFirstTime(50)) then do stuff will only run once when the frame first ran
function Camera:FrameFirstTime(frame)
    if self.CurFrame >= frame and not self.FrameChecks[frame] then
        self.FrameChecks[frame] = true
        return true
    end

    return false
end

function Camera:IsValid()
	return IsValid(self.Player) and self.Player:Alive()
end

function Camera:__tostring()
	return self.Name .. "_" .. tostring(self.Player)
end
