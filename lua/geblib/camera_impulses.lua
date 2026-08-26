if SERVER then return end

gebLib.CameraImpulses = {}

local CameraImpulses = gebLib.CameraImpulses
local channels = {}

local Channel = {}
Channel.__index = Channel

local function copyNumbers(values)
    local copy = {}
    for key, value in pairs(values) do copy[key] = tonumber(value) or 0 end
    return copy
end

local function decayValue(value, rate, age)
    return value * math.exp(-math.max(tonumber(rate) or 0, 0) * age)
end

function Channel:Push(values, decayRates, combine, now)
    if not istable(values) then error("camera impulse values must be a table", 2) end
    self.Impulses[#self.Impulses + 1] = {
        StartedAt = now or RealTime(),
        Values = copyNumbers(values),
        DecayRates = istable(decayRates) and copyNumbers(decayRates)
            or {default = tonumber(decayRates) or 6},
        Combine = combine or "add",
    }
end

function Channel:PushAt(position, radius, values, decayRates, viewer, combine, now)
    viewer = IsValid(viewer) and viewer or LocalPlayer()
    if not IsValid(viewer) then return false end
    local attenuation = gebLib.Math.DistanceFalloff(
        viewer:WorldSpaceCenter():Distance(position),
        radius
    )
    if attenuation <= 0 then return false end
    local scaled = {}
    for key, value in pairs(values) do scaled[key] = value * attenuation end
    self:Push(scaled, decayRates, combine, now)
    return true
end

function Channel:Sustain(values, decayRates, now)
    now = now or RealTime()
    for key, value in pairs(values) do
        local sustained = self.Sustained[key] or {}
        self.Sustained[key] = sustained
        sustained.Value = tonumber(value) or 0
        sustained.Rate = istable(decayRates)
            and (tonumber(decayRates[key]) or tonumber(decayRates.default) or 6)
            or tonumber(decayRates) or 6
        sustained.RefreshedAt = now
    end
end

function Channel:Sample(now)
    now = now or RealTime()
    local values = self.Values
    for key in pairs(values) do values[key] = nil end

    for index = #self.Impulses, 1, -1 do
        local impulse = self.Impulses[index]
        local age = math.max(now - impulse.StartedAt, 0)
        local alive = false
        for key, original in pairs(impulse.Values) do
            local rate = impulse.DecayRates[key] or impulse.DecayRates.default or 6
            local value = decayValue(original, rate, age)
            if math.abs(value) >= 0.001 then
                if impulse.Combine == "max" then
                    local current = values[key] or 0
                    if math.abs(value) > math.abs(current) then values[key] = value end
                else
                    values[key] = (values[key] or 0) + value
                end
                alive = true
            end
        end
        if not alive then table.remove(self.Impulses, index) end
    end
    for key, sustained in pairs(self.Sustained) do
        local value = decayValue(
            sustained.Value,
            sustained.Rate,
            math.max(now - sustained.RefreshedAt, 0)
        )
        if math.abs(value) < 0.001 then
            self.Sustained[key] = nil
        elseif math.abs(value) > math.abs(values[key] or 0) then
            values[key] = value
        end
    end
    return values
end

function Channel:Get(key)
    return self.Values[key] or 0
end

function Channel:Clear()
    self.Impulses = {}
    self.Sustained = {}
    self.Values = {}
end

function CameraImpulses.Create(name, priority, adapter)
    if not isstring(name) or name == "" then error("camera impulse channel requires a name", 2) end
    if not isfunction(adapter) then error("camera impulse channel requires an adapter", 2) end

    local channel = channels[name]
    if not channel then
        channel = setmetatable({
            Name = name,
            Impulses = {},
            Sustained = {},
            Values = {},
        }, Channel)
        channels[name] = channel
    end
    channel.Adapter = adapter
    channel.Priority = tonumber(priority) or 0
    gebLib.CameraModifiers.Register(name, channel.Priority, function(player, view)
        channel:Sample(RealTime())
        return channel.Adapter(player, view, channel)
    end)
    return channel
end

function CameraImpulses.Remove(name)
    local channel = channels[name]
    if not channel then return false end
    channel:Clear()
    channels[name] = nil
    gebLib.CameraModifiers.Remove(name)
    return true
end

function CameraImpulses.Clear()
    local names = {}
    for name in pairs(channels) do names[#names + 1] = name end
    for index = 1, #names do CameraImpulses.Remove(names[index]) end
end
