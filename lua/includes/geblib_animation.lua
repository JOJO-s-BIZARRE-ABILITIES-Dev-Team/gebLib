--This is the gebLib (originated from ba1.4) animation system

gebLib_animation = {}
gebLib_animation.__index = gebLib_animation

--------------------
--Contributors: T0M
--------------------

--not sure if these todos are going to be done, because of how player handles animations
--TODO: Try and adapt the system, so it works with player animations
--TODO: Support layered sequences

--Constructor
function gebLib_animation.New(entity, sequence)
    if not entity:IsValid() then
        gebLib.PrintDebug("Trying to set an animation entity which is nil!")
    end

    if type(sequence) == "string" then
        sequence = entity:LookupSequence(sequence)
    end

    local self = setmetatable({}, gebLib_animation)

    self.Entity = entity
    self.Sequence = sequence
    self.Activity = entity:GetSequenceActivity(sequence)
    self.Init = nil
    self.End = nil
    self.Events = {}
    self.ThinkName = nil
    self.Initialized = false
    self.Playing = false

    self.FPS = 0
    self.Frames = 0
    self.Looped = false

    --Sadly fps and total frames is not in the same table as the other data, so i need to get the animation info table
    if sequence ~= -1 then
        local sequenceInfo = entity:GetSequenceInfo(sequence)
        local animInfo = entity:GetAnimInfo(sequenceInfo.anims[1])
        
        self.FPS = animInfo.fps
        self.Frames = animInfo.numframes
        self.Looped = bit.band(sequenceInfo.flags, 1) == 1 --I GUESSSS?
    end
    
    return self
end

--Main Functions
function gebLib_animation:Play()
    if self:IsValid() then
        local entity = self.Entity
        local sequence = self.Sequence
        
        self.Playing = true
        self:ReloadEvents()

        local thinkName = "gebLib_" .. entity:GetClass() .. entity:EntIndex() .. "_" .. sequence
        self.ThinkName = thinkName

        hook.Add("Think", thinkName, function()
            if not IsValid(self.Entity) then self:Remove() return end
            if self.Frames <= 0 or not self:IsValid() then hook.Remove("Think", thinkName) end
            if self:GetPlayback() == 0 then return end

            if self:GetCycle() >= 0 and self:GetCycle() <= 0.1 and self.NewLoop then
                self.NewLoop = false
                self:ReloadEvents()
            end

            --Run the init function of the animation when the cycle is 0
            if self.Init and not self.Initialized then
                self.Init(self)
                self.Initialized = true
            end

            --Check for animation events
            if self:HasEvents() then
                for _, event in pairs(self.Events) do
                    if self:GetPlayback() > 0 then
                        if self:GetFrame() >= event.Frame and not event.Played then
                            event.Function(self)
                            event.Played = true
                        end
                    elseif self:GetPlayback() < 0 then
                        if self:GetFrame() <= event.Frame and not event.Played then
                            event.Function(self)
                            event.Played = true
                        end
                    end
                end    
            end

            --End of the animation
            if self:GetPlayback() > 0 then
                if self.End and self:GetCycle() >= 1 and not self.Looped then
                    self.Playing = false
                    self.Initialized = false

                    self:Stop()
                    self.End(self)
                elseif self:GetCycle() >= 0.9 and self.Looped then --Different function when the animation is looped
                    self.NewLoop = true
                end
            else --Animations that play in reverse
                if self.End and self:GetCycle() <= 0 and not self.Looped then
                    self.Playing = false
                    self.Initialized = false
    
                    hook.Remove("Think", self.ThinkName)
                    self.End(self)
                elseif self:GetCycle() <= 0 and self.Looped then --Different function when the animation is looped
                    self:ReloadEvents()
                end
            end
        end)
        entity:ResetSequence(sequence)
        entity:ResetSequenceInfo()
        entity:SetCycle(0)
    end
end

--Sometimes we don't want to stop the stop the animation, so we pause it, so it still has the think function and can resume safely
function gebLib_animation:Pause()
    if self:IsValid() then
        self:SetPlayback(0)
        self.Playing = false
    end
end

--Resuems the anim from the cycle, when the pause function was used
function gebLib_animation:Resume(playback)
    playback = playback or 1
    if self:IsValid() then
        self:SetPlayback(playback)
        self.Playing = true
    end
end

function gebLib_animation:Stop()
    if self:IsValid() and self.ThinkName then
        hook.Remove("Think", self.ThinkName)

        self.Entity:ResetSequenceInfo()
        self:SetPlayback(0)
        self:SetCycle(0)

        self.Playing = false
        self.Initialized = false
    end
end

function gebLib_animation:Remove() --Use this when you are not going to use the animation again, should be added to ENT:OnRemove()
    hook.Remove("Think", self.ThinkName)
    setmetatable(self, nil)
    self = nil

    gebLib.PrintDebug("Removed animation")
end

--Event functions
function gebLib_animation:AddEvent(name, frame, func)
    self.Events[name] = {Frame = frame, Function = func, Played = false}
    gebLib.PrintDebug("Successfully added an event on " .. tostring(frame) .. ". frame!")
end

function gebLib_animation:ReloadEvent(name)
    if not self:HasEvents() then return end

    if self:HasEvent(name) then
        self.Events[name].Played = false 
    else
        gebLib.PrintDebug("Event: " .. tostring(name) .. " cannot be reloaded because it does not exist!")
    end
end

function gebLib_animation:ReloadEvents()
    if not self:HasEvents() then return end

    for _, event in pairs(self.Events) do
        event.Played = false
    end

    gebLib.PrintDebug("Sequence: " .. tostring(self.Sequence) .. " has reloaded all events!")
end

function gebLib_animation:HasEvent(name)
    return self.Events[name] ~= nil
end

function gebLib_animation:HasEvents()
    return not table.IsEmpty(self.Events)
end

function gebLib_animation:IsValid()
    if IsValid(self.Entity) and self.Sequence ~= 0 and self.Sequence ~= -1 then
        return true
    end
    ErrorNoHaltWithStack("gebLib Animation is not valid!")
    return false
end

function gebLib_animation:IsActive()
    return self.Entity:GetSequence() == self.Sequence
end

function gebLib_animation:IsPlaying()
    if self:IsValid() and self:IsActive() then
        return self.Playing
    end
    return false
end

function gebLib_animation:IsFinished()
    if self:IsActive() then
        if self:GetPlayback() > 0 then
            return self:GetCycle() >= 1
        else
            return self:GetCycle() <= 0
        end
    else
        return false
    end
end

function gebLib_animation:CycleToFrame(cycle)
    cycle = math.Clamp(cycle, 0, 1)
    return cycle * self:GetFrames()
end

function gebLib_animation:Print()
    print("Entity: " .. tostring(self.Entity))
    print("Sequence ID: " .. tostring(self.Sequence))
    print("Sequence Name: " .. self.Entity:GetSequenceName(self.Sequence))
    print()
    print("Events:")
    if self:HasEvents() then
        for name, event in pairs(self.Events) do
            print("Name: " .. tostring(name))
            print("Frame: " .. tostring(event.Frame))
            print("Function: " .. tostring(event.Function))
            print()
        end
    end
    print("Frames: " .. tostring(self.Frames))
    print("FPS: " .. tostring(self.FPS))
    print("Looped: " .. tostring(self.Looped))
end

--Setters & Getters
function gebLib_animation:SetInit(func)
    self.Init = func
end

function gebLib_animation:SetEnd(func)
    self.End = func
end

function gebLib_animation:SetPlayback(rate)
    self.Entity:SetPlaybackRate(rate)
end

function gebLib_animation:GetPlayback()
    return self.Entity:GetPlaybackRate()
end

function gebLib_animation:SetCycle(cycle)
    cycle = math.Clamp(cycle, 0, 1)
    self.Entity:SetCycle(cycle)
end

function gebLib_animation:GetCycle()
    return self.Entity:GetCycle()
end

function gebLib_animation:SetFrames(frames)
    self.Frames = frames
end

function gebLib_animation:GetFrames() --Cycle is not the same thing as frame, cycle is a num from 0 to 1 representing the percentage
    return self.Frames
end

function gebLib_animation:SetFrame(frame) --Internally sets the cycle. SetCycle is faster, but if you want to use it, you can.
    if self:IsValid() then
        self.Entity:SetCycle(math.Clamp(frame / self:GetFrames(), 0, 1))
    end
end

function gebLib_animation:GetFrame() --Returns current frame of sequence
    --Example: sequence has 40 frames and the current cycle is 0.5 (middle of the animation), so we multiply 0.5 * 40 = 20 frames // makes sense
    return self:GetCycle() * self:GetFrames()
end