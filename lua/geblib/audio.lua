if SERVER then return end

gebLib.Audio = {}

local Audio = gebLib.Audio
local sessions = setmetatable({}, {__mode = "k"})

local Session = {}
Session.__index = Session

local function validChannel(channel)
    return channel and (not IsValid or IsValid(channel))
end

function Audio.New()
    local session = setmetatable({Generation = 0, RetryAt = 0}, Session)
    sessions[session] = true
    return session
end

function Session:IsPlaying()
    return self.Kind == "patch" and self.Handle ~= nil
        or self.Kind == "file" and validChannel(self.Handle)
        or self.Requested == true
end

function Session:Stop(fadeTime)
    self.Generation = self.Generation + 1
    self.Requested = false
    self.RestartAt = nil
    self.RestartInterval = nil
    local handle = self.Handle
    self.Handle = nil
    self.Kind = nil
    if not handle then return false end
    if fadeTime and fadeTime > 0 and handle.FadeOut then
        handle:FadeOut(fadeTime)
    elseif handle.Stop then
        handle:Stop()
    end
    return true
end

function Session:PlayPatch(owner, path, options)
    self:Stop()
    if not IsValid(owner) or not isstring(path) or path == "" then return false end
    local patch = CreateSound(owner, path)
    if not patch then return false end
    options = options or {}
    self.Handle = patch
    self.Kind = "patch"
    self.Path = path
    self.Owner = owner
    self.Volume = options.volume or 1
    self.Pitch = options.pitch or 100
    patch:PlayEx(self.Volume, self.Pitch)
    return true
end

function Session:Restart()
    local handle = self.Handle
    if not handle then return false end
    if handle.Stop then handle:Stop() end
    if self.Kind == "patch" and handle.PlayEx then
        handle:PlayEx(self.Volume or 1, self.Pitch or 100)
    elseif self.Kind == "file" and handle.Play then
        handle:Play()
    end
    return true
end

function Session:ScheduleRestart(interval, now)
    self.RestartInterval = math.max(tonumber(interval) or 0, 0)
    self.RestartAt = (now or RealTime()) + self.RestartInterval
end

function Session:Update(now)
    now = now or RealTime()
    if not self.RestartAt or now < self.RestartAt then return false end
    if not self:Restart() then
        self.RestartAt = nil
        self.RestartInterval = nil
        return false
    end
    self.RestartAt = now + self.RestartInterval
    return true
end

function Session:PlayFile(path, flags, options)
    options = options or {}
    if RealTime() < self.RetryAt then return false end
    if self.Requested or self.Kind == "file" and validChannel(self.Handle) then return true end

    self:Stop()
    self.Requested = true
    self.Generation = self.Generation + 1
    local generation = self.Generation
    sound.PlayFile(path, flags or "noplay noblock", function(channel)
        if generation ~= self.Generation then
            if validChannel(channel) and channel.Stop then channel:Stop() end
            return
        end
        self.Requested = false
        if not validChannel(channel) then
            self.RetryAt = RealTime() + (options.retryDelay or 1)
            if options.onFailure then options.onFailure() end
            return
        end

        self.Handle = channel
        self.Kind = "file"
        self.Path = path
        self.Volume = options.volume or self.Volume or 1
        self.Pitch = options.pitch or self.Pitch or 100
        if options.looping ~= nil and channel.EnableLooping then
            channel:EnableLooping(options.looping == true)
        end
        if channel.SetVolume then channel:SetVolume(self.Volume) end
        if self.Pitch ~= 100 and channel.SetPlaybackRate then
            channel:SetPlaybackRate(self.Pitch / 100)
        end
        if options.onReady then options.onReady(channel) end
        if options.play ~= false and channel.Play then channel:Play() end
    end)
    return true
end

function Session:SetVolume(volume, duration)
    self.Volume = volume
    local handle = self.Handle
    if not handle then return false end
    if self.Kind == "patch" and handle.ChangeVolume then
        handle:ChangeVolume(volume, duration or 0)
    elseif handle.SetVolume then
        handle:SetVolume(volume)
    end
    return true
end

function Session:SetPitch(pitch, duration)
    self.Pitch = pitch
    local handle = self.Handle
    if not handle then return false end
    if handle.ChangePitch then handle:ChangePitch(pitch, duration or 0) return true end
    if handle.SetPlaybackRate then handle:SetPlaybackRate(pitch / 100) return true end
    return false
end

function Session:Remove()
    self:Stop()
    sessions[self] = nil
end

function Audio.StopAll()
    for session in pairs(sessions) do session:Stop() end
end

hook.Add("ShutDown", "gebLib.Audio", Audio.StopAll)
