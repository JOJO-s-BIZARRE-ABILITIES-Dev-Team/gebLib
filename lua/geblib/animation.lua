gebLib.Animation = {}
gebLib.Animation.__index = gebLib.Animation

local Animation = gebLib.Animation
gebLib._NextAnimationId = gebLib._NextAnimationId or 0

local Runtime = gebLib._Runtime
if not Runtime then
    local loader = include or function(path) return assert(loadfile("lua/" .. path))() end
    Runtime = loader("geblib/runtime.lua")
end

local function failAnimation(animation)
    animation:Remove()
end

local function runAnimationCallback(animation, label, callback)
    return Runtime.Invoke(
        animation,
        "Animation " .. tostring(animation.Sequence) .. " " .. label,
        callback,
        failAnimation,
        animation
    )
end

local function runAnimationEvents(animation, playback)
    local order = animation.EventOrder
    local first = playback > 0 and 1 or #order
    local last = playback > 0 and #order or 1
    local increment = playback > 0 and 1 or -1

    for index = first, last, increment do
        local name = order[index]
        local event = animation.Events[name]
        local due = playback > 0 and animation:GetFrame() >= event.Frame
            or playback < 0 and animation:GetFrame() <= event.Frame

        if due and not event.Played then
            event.Played = true
            if not runAnimationCallback(animation, "event " .. name, event.Function) then return false end
            if animation.Removed or not animation.Playing then return not animation.Removed end
        end
    end

    return true
end

local function stepAnimation(animation)
    if not IsValid(animation.Entity) then
        animation:Remove()
        return false
    end

    if animation.Frames <= 0 or not animation:IsValid() or not animation:IsActive() then
        animation.Playing = false
        return false
    end
    if not animation.Playing then return true end

    local playback = animation:GetPlayback()
    if playback == 0 then return true end

    if animation:GetCycle() >= 0 and animation:GetCycle() <= 0.1 and animation.NewLoop then
        animation.NewLoop = false
        animation:ReloadEvents()
    end

    if animation.Init and not animation.Initialized then
        animation.Initialized = true
        if not runAnimationCallback(animation, "init callback", animation.Init) then return false end
        if animation.Removed or not animation.Playing then return not animation.Removed end
    end

    if not runAnimationEvents(animation, playback) then return false end

    if playback > 0 then
        if animation:GetCycle() >= 1 and not animation.Looped then
            animation:Stop()
            if animation.End then runAnimationCallback(animation, "end callback", animation.End) end
            return false
        elseif animation:GetCycle() >= 0.9 and animation.Looped then
            animation.NewLoop = true
        end
    elseif animation:GetCycle() <= 0 and not animation.Looped then
        animation:Stop()
        if animation.End then runAnimationCallback(animation, "end callback", animation.End) end
        return false
    elseif animation:GetCycle() <= 0 and animation.Looped then
        animation:ReloadEvents()
    end

    return true
end

function Animation.New(entity, sequence)
    if not IsValid(entity) then
        error("Cannot create a gebLib animation for an invalid entity")
    end

    if isstring(sequence) then
        sequence = entity:LookupSequence(sequence)
    end

    if not isnumber(sequence) or sequence < 0 then
        error("animation sequence must exist", 2)
    end

    local self = setmetatable({}, Animation)
    gebLib._NextAnimationId = gebLib._NextAnimationId + 1

    self.Entity = entity
    self.Sequence = sequence
    self.Activity = entity:GetSequenceActivity(sequence)
    self.Init = nil
    self.End = nil
    self.Events = {}
    self.EventOrder = {}
    self.ThinkName = nil
    self.HookName = "gebLib.Animation." .. gebLib._NextAnimationId
    self.Initialized = false
    self.Playing = false
    self.Removed = false

    self.FPS = 0
    self.Frames = 0
    self.Looped = false

    --Sadly fps and total frames is not in the same table as the other data, so i need to get the animation info table
    if sequence ~= -1 then
        local sequenceInfo = entity:GetSequenceInfo(sequence)
        local animIndex = sequenceInfo and sequenceInfo.anims and sequenceInfo.anims[1]
        local animInfo = animIndex and entity:GetAnimInfo(animIndex)

        if animInfo then
            self.FPS = animInfo.fps or 0
            self.Frames = animInfo.numframes or 0
        end
        if sequenceInfo then
            self.Looped = bit.band(sequenceInfo.flags or 0, 1) == 1
        end
    end
    
    return self
end

--Main Functions
function Animation:Play(playback)
    if self:IsValid() then
        local entity = self.Entity
        local sequence = self.Sequence

        playback = playback or entity:GetPlaybackRate()
        if playback == 0 then playback = 1 end
        if not isnumber(playback) then
            error("animation playback must be a number", 2)
        end
        
        self.Playing = true
        self.Initialized = false
        self.NewLoop = false
        self:ReloadEvents()

        self.ThinkName = self.HookName
        Runtime.Register(self, "Animation " .. tostring(sequence), stepAnimation, failAnimation, failAnimation)
        entity:ResetSequence(sequence)
        entity:ResetSequenceInfo()
        entity:SetPlaybackRate(playback)
        entity:SetCycle(playback < 0 and 1 or 0)
        return true
    end

    return false
end

function Animation:Pause()
    if self:IsActive() then
        self:SetPlayback(0)
        self.Playing = false
        return true
    end

    return false
end

function Animation:Resume(playback)
    playback = playback or 1
    if not isnumber(playback) then
        error("animation playback must be a number", 2)
    end

    if self:IsActive() then
        self:SetPlayback(playback)
        self.Playing = true
        return true
    end

    return false
end

function Animation:Stop()
    Runtime.Unregister(self)

    if self:IsActive() then
        self.Entity:ResetSequenceInfo()
        self:SetPlayback(0)
        self:SetCycle(0)
    end

    self.Playing = false
    self.Initialized = false
end

function Animation:Remove()
    if self.Removed then return end

    self:Stop()
    self.Removed = true

    gebLib.PrintDebug("Removed animation")
end

--Event functions
function Animation:AddEvent(name, frame, func)
    if not isstring(name) or name == "" then
        error("animation event name must be a non-empty string", 2)
    end

    if not isnumber(frame) or frame < 0 then
        error("animation event frame must be zero or greater", 2)
    end

    if not isfunction(func) then
        error("animation event callback must be a function", 2)
    end

    local event = self.Events[name]
    if not event then
        event = {}
        self.Events[name] = event
        self.EventOrder[#self.EventOrder + 1] = name
    end

    event.Frame = frame
    event.Function = func
    event.Played = false
    table.sort(self.EventOrder, function(leftName, rightName)
        local left = self.Events[leftName]
        local right = self.Events[rightName]
        if left.Frame == right.Frame then return leftName < rightName end
        return left.Frame < right.Frame
    end)
    gebLib.PrintDebug("Successfully added an event on " .. tostring(frame) .. ". frame!")
end

function Animation:ReloadEvent(name)
    if not self:HasEvents() then return end

    if self:HasEvent(name) then
        self.Events[name].Played = false 
    else
        gebLib.PrintDebug("Event: " .. tostring(name) .. " cannot be reloaded because it does not exist!")
    end
end

function Animation:ReloadEvents()
    if not self:HasEvents() then return end

    for _, event in pairs(self.Events) do
        event.Played = false
    end

    gebLib.PrintDebug("Sequence: " .. tostring(self.Sequence) .. " has reloaded all events!")
end

function Animation:HasEvent(name)
    return self.Events[name] ~= nil
end

function Animation:HasEvents()
    return next(self.Events) ~= nil
end

function Animation:IsValid()
    return not self.Removed and IsValid(self.Entity) and self.Sequence ~= -1
end

function Animation:IsActive()
    return self:IsValid() and self.Entity:GetSequence() == self.Sequence
end

function Animation:IsPlaying()
    if self:IsValid() and self:IsActive() then
        return self.Playing
    end
    return false
end

function Animation:IsFinished()
    if self:IsActive() then
        if self:GetPlayback() > 0 then
            return self:GetCycle() >= 1
        elseif self:GetPlayback() < 0 then
            return self:GetCycle() <= 0
        end

        return false
    else
        return false
    end
end

function Animation:CycleToFrame(cycle)
    cycle = math.Clamp(cycle, 0, 1)
    return cycle * self:GetFrames()
end

function Animation:Print()
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
function Animation:SetInit(func)
    if func ~= nil and not isfunction(func) then
        error("animation init callback must be a function", 2)
    end
    self.Init = func
end

function Animation:SetEnd(func)
    if func ~= nil and not isfunction(func) then
        error("animation end callback must be a function", 2)
    end
    self.End = func
end

function Animation:SetPlayback(rate)
    self.Entity:SetPlaybackRate(rate)
end

function Animation:GetPlayback()
    return self.Entity:GetPlaybackRate()
end

function Animation:SetCycle(cycle)
    cycle = math.Clamp(cycle, 0, 1)
    self.Entity:SetCycle(cycle)
end

function Animation:GetCycle()
    return self.Entity:GetCycle()
end

function Animation:SetFrames(frames)
    if not isnumber(frames) or frames < 0 then
        error("animation frame count must be zero or greater", 2)
    end
    self.Frames = frames
end

function Animation:GetFrames()
    return self.Frames
end

function Animation:SetFrame(frame)
    if self:IsValid() and self:GetFrames() > 0 then
        self.Entity:SetCycle(math.Clamp(frame / self:GetFrames(), 0, 1))
    end
end

function Animation:GetFrame()
    return self:GetCycle() * self:GetFrames()
end
