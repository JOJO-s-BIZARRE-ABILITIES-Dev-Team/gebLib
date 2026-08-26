gebLib.Camera = {}
gebLib.Camera.__index = gebLib.Camera

local Camera = gebLib.Camera
gebLib._NextCameraId = gebLib._NextCameraId or 0

local Runtime = gebLib._Runtime
if not Runtime then
    local loader = include or function(path) return assert(loadfile("lua/" .. path))() end
    Runtime = loader("geblib/runtime.lua")
end

local function RenderOverride(self)
	self:DrawModel()
	self:FrameAdvance()
end

local function failCamera(camera)
	camera:Stop()
end

local function updateCameraFrame(camera)
	camera.CurFrame = (SysTime() - camera.Start) * camera.FPS
end

local function maintainCameraPresentation(camera)
	if SERVER or not camera.UseDefaultHooks then return end

	local owner = camera.Player
	if IsValid(camera.Copy) then
		if camera.OriginalNoDraw == nil then camera.OriginalNoDraw = owner:GetNoDraw() end
		owner:SetNoDraw(true)
	end
	if camera.OldAng then owner:SetEyeAngles(camera.OldAng) end
	if camera.OldPos then owner:SetPos(camera.OldPos) end
end

local function runCameraEvents(camera, ply, pos, angles, fov, view)
	for index = 1, #camera.EventOrder do
		local frame = camera.EventOrder[index]
		local data = camera.Events[frame]
		if not data.Ended and camera.CurFrame >= frame and camera.CurFrame <= data.EndFrame then
			local ok, origin, viewAngles, viewFov = camera:RunCallback(data.Function, ply, pos, angles, fov)
			if not ok or not camera.Playing then return false end
			if view then
				if origin then view.origin = origin end
				if viewAngles then view.angles = viewAngles end
				if viewFov then view.fov = viewFov end
			end
		elseif not data.Ended and camera.CurFrame >= data.EndFrame then
			data.Ended = true
		end
	end

	return true
end

local function stepCamera(camera)
    if not camera.Playing then return false end
    if not camera:IsValid() then
        camera:Stop()
        return false
    end

    updateCameraFrame(camera)
    maintainCameraPresentation(camera)

    if CLIENT and not camera.Simulated then return true end
    if not camera:RunThink() or not camera.Playing then return false end

    if CLIENT and not runCameraEvents(camera, camera.Player, vector_origin, angle_zero, 70) then
        return false
    end

    if camera.CurFrame >= camera.MaxFrames then
        camera:Stop()
        return false
    end

    return true
end

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
    self.EventOrder = {}
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
function Camera:RunCallback(callback, ...)
	return Runtime.Invoke(self, "Cinematic Camera " .. tostring(self), callback, failCamera, ...)
end

function Camera:RunThink()
	if not self.ThinkFunc or not self.Playing then return true end
	return self:RunCallback(self.ThinkFunc, self)
end

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

	Runtime.Register(self, "Cinematic Camera " .. tostring(self), stepCamera, failCamera, failCamera)

	if CLIENT and not simulate then
		gebLib.CameraModifiers.Register(self.ThinkName, 10000, function(ply, view)
			if ply ~= self.Player then return false end
			if not self.Playing or not self:IsValid() then self:Stop() return false end

			updateCameraFrame(self)
			view.drawviewer = true

			if not self:RunThink() or not self.Playing then return true end
			if not runCameraEvents(self, ply, view.origin, view.angles, view.fov, view) then return true end

			if self.CurFrame >= self.MaxFrames then self:Stop() end

			self.LastPos = view.origin
			self.LastAng = view.angles
			return true
		end)
	end

	return true
end

function Camera:Stop()
    if not self.Playing then return false end

	self.Playing = false
	Runtime.Unregister(self)
	self:RemoveDefaultHooks()

	if CLIENT and IsValid(self.Player) and self.OriginalNoDraw ~= nil then
		self.Player:SetNoDraw(self.OriginalNoDraw)
		self.OriginalNoDraw = nil
	end
	if CLIENT and IsValid(self.Copy) then
		self.Copy:Remove()
	end
	self.Copy = NULL

	if self.EndFunc then
		Runtime.Invoke(self, "Cinematic Camera " .. tostring(self) .. " end callback", self.EndFunc, nil, self)
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

	if not self.Events[initFrame] then self.EventOrder[#self.EventOrder + 1] = initFrame end
    self.Events[initFrame] = {Function = func, Ended = false, EndFrame = endFrame, Start = 0}
	table.sort(self.EventOrder)
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

	local copy = gebLib.PlayerReplica.Create(ply, RENDERGROUP_OPAQUE, true)
	if not IsValid(copy) then return false end

    copy:SetNoDraw(false)
    copy:SetPos(oldPos)
    copy:SetAngles(angles)
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

end

function Camera:RemoveDefaultHooks()
	hook.Remove("DrawOverlay", self.HookName .. "_BlackBars")
	hook.Remove("HUDShouldDraw", self.HookName .. "_NoHud")

	if self.ThinkName and gebLib.CameraModifiers then
		gebLib.CameraModifiers.Remove(self.ThinkName)
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
