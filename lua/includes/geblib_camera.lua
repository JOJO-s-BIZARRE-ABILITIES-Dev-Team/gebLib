--This is the gebLib camera animation system
if SERVER then return end

gebLib_camera = {}
gebLib_camera.__index = gebLib_camera

--------------------
--Contributors: T0M
--------------------

--Constructor
function gebLib_camera.New(name, ply, fps, maxFrames)
    self = setmetatable({}, gebLib_camera)

    self.Name = name
    self.Player = ply
    self.FPS = fps --Recommended is 60
    self.MaxFrames = maxFrames
    self.Events = {}
    self.FrameChecks = {}

    self.Playing = false
    self.ThinkName = nil
    self.EndFunc = nil
    self.ThinkFunc = nil

    self.CurFrame = 0
    self.Start = 0 --Time the camera was started
    self.LastTime = 0

    self.LastPos = nil

    return self
end

--General Functions
function gebLib_camera:Play(simulate)
    self.Playing = true
    self.Start = CurTime()
    self.ThinkName = self.Player:GetName() .. self.Player:EntIndex() .. "gebLib_camera"

    --Reset event start times
    for frame, data in pairs(self.Events) do
        data.Start = CurTime()
    end
    
    if not simulate then
        hook.Add("CalcView", self.ThinkName, function(ply, pos, angles, fov)
            if not self.Player:IsValid() then self:Stop() return end

            self.CurFrame = (CurTime() - self.Start) * self.FPS
            local view = {
                origin = vector_origin,
                angles = angle_zero,
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
            return view
        end, HOOK_HIGH)
    else --For other players, simulate the camera behaviour, so everything is properly synced
        hook.Add("Think", self.ThinkName, function()
            if not self.Player:IsValid() then self:Stop() return end

            self.CurFrame = (CurTime() - self.Start) * self.FPS
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

function gebLib_camera:Stop()
    self.EndFunc(self)

    self.Playing = false
    hook.Remove("CalcView", self.ThinkName)
    hook.Remove("Think", self.ThinkName)
end

function gebLib_camera:SetThink(func)
    self.ThinkFunc = func
end

function gebLib_camera:SetEnd(func)
    self.EndFunc = func
end

function gebLib_camera:AddEvent(initFrame, endFrame, func)
    self.Events[initFrame] = {Function = func, Ended = false, EndFrame = endFrame, Start = 0}
end

--Helper Functions
--Returns the time based on the fps, end frame and the current frame, this should be used with every lerp function.
--Formula for creating this
--(CurTime() - someTimeBefore) / (eventLength / cameraFPS)
function gebLib_camera:GetTime(eventFrame, mult)
    assert(eventFrame, "eventFrame it nil! Please specify the camera event.")
    mult = mult or 1

    local event = self.Events[eventFrame]

    local result = math.Remap(self.CurFrame, eventFrame, event.EndFrame, 0, 1)
    return math.Clamp(result * mult, 0, 1)
end

--Used for one time logic in events, because calcView can run faster than the cam's fps, so this ensures it gets run only once
function gebLib_camera:FrameFirstTime(frame)
    if self.CurFrame >= frame and not self.FrameChecks[frame] then
        self.FrameChecks[frame] = true
        return true
    end

    return false
end