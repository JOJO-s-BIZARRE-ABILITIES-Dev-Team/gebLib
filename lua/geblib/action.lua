gebLib.Action = {}
gebLib.Action.__index = gebLib.Action

local Action = gebLib.Action

local Runtime = gebLib._Runtime
if not Runtime then
    local loader = include or function(path) return assert(loadfile("lua/" .. path))() end
    Runtime = loader("geblib/runtime.lua")
end

gebLib._NextActionId = gebLib._NextActionId or 0

local function nextId()
    gebLib._NextActionId = gebLib._NextActionId + 1
    return gebLib._NextActionId
end

local function resetEvents(action)
    for _, event in pairs(action.Events) do
        event.played = false
    end
end

local function failAction(action)
    action:Remove()
end

local function runActionCallback(action, label, callback)
    return Runtime.Invoke(action, "Action " .. action.Id .. " " .. label, callback, failAction, action)
end

local function stepAction(action)
    if action.Removed then return false end
    if not IsValid(action.Entity) then
        action:Remove()
        return false
    end
    if not action.Playing then return true end

    local now = CurTime()
    if now < action.StartTime then return true end

    for index = 1, #action.EventOrder do
        local event = action.Events[action.EventOrder[index]]
        if event and not event.played and now >= action.StartTime + event.time / action.TimeScale then
            event.played = true
            if not runActionCallback(action, "event " .. action.EventOrder[index], event.callback) then return false end
            if action.Removed or not action.Playing then return not action.Removed end
        end
    end

    if now < action.StartTime + action.Duration / action.TimeScale then return true end

    if action.Repetitions == -1 or action.RepeatedFor < action.Repetitions then
        action.RepeatedFor = action.RepeatedFor + 1
        action.StartTime = now
        resetEvents(action)
        return true
    end

    action:Stop()
    return false
end

function Action.New(entity, duration)
    if isnumber(entity) and duration == nil then
        duration = entity
        entity = game.GetWorld()
    end

    if not IsValid(entity) then
        error("action entity must be valid", 2)
    end

    duration = duration or 0
    if not isnumber(duration) or duration < 0 then
        error("action duration must be zero or greater", 2)
    end

    local action = setmetatable({}, Action)
    action.Entity = entity
    action.Duration = duration
    action.Events = {}
    action.EventOrder = {}
    action.TimeScale = 1
    action.Repetitions = 0
    action.RepeatedFor = 0
    action.StartDelay = 0
    action.StartTime = 0
    action.PauseTime = nil
    action.Playing = false
    action.Removed = false
    action.Id = nextId()
    action.HookName = "gebLib.Action." .. action.Id
    return action
end

function Action:Start(repetitions, delay)
    if self.Removed or self.Playing or self.TimeScale <= 0 then return false end

    self.Repetitions = repetitions or 0
    self.StartDelay = delay or 0

    if not isnumber(self.Repetitions) or self.Repetitions < -1 or self.Repetitions % 1 ~= 0 then
        error("action repetitions must be -1 or a non-negative integer", 2)
    end

    if not isnumber(self.StartDelay) or self.StartDelay < 0 then
        error("action delay must be zero or greater", 2)
    end

    self.RepeatedFor = 0
    self.StartTime = CurTime() + self.StartDelay
    self.PauseTime = nil
    self.Playing = true
    resetEvents(self)

    if self.OnStartCallback and not runActionCallback(self, "start callback", self.OnStartCallback) then
        return false
    end
    if self.Removed then return false end

    Runtime.Register(self, "Action " .. self.Id, stepAction, failAction, failAction)

    return true
end

function Action:Pause()
    if self.Removed or not self.Playing then return false end
    self.PauseTime = CurTime()
    self.Playing = false
    return true
end

function Action:Resume()
    if self.Removed or self.Playing or not self.PauseTime then return false end
    self.StartTime = self.StartTime + CurTime() - self.PauseTime
    self.PauseTime = nil
    self.Playing = true
    return true
end

function Action:Stop()
    return self:Remove()
end

function Action:Remove()
    if self.Removed then return false end

    Runtime.Unregister(self)
    self.Playing = false
    self.Removed = true

    if self.OnRemoveCallback then
        Runtime.Invoke(self, "Action " .. self.Id .. " remove callback", self.OnRemoveCallback, nil, self)
    end

    return true
end

function Action:SetTimeScale(timeScale)
    if not isnumber(timeScale) or timeScale <= 0 then
        error("action time scale must be greater than zero", 2)
    end
    self.TimeScale = timeScale
end

function Action:GetTimeScale()
    return self.TimeScale
end

function Action:IsPlaying()
    return self.Playing
end

function Action:GetIndex()
    return self.Id
end

function Action:SetInit(callback)
    self:AddEvent("__init", 0, callback)
end

function Action:SetEnd(callback)
    self:AddEvent("__end", self.Duration, callback)
end

function Action:OnStart(callback)
    if callback ~= nil and not isfunction(callback) then
        error("action start callback must be a function", 2)
    end
    self.OnStartCallback = callback
end

function Action:OnRemove(callback)
    if callback ~= nil and not isfunction(callback) then
        error("action remove callback must be a function", 2)
    end
    self.OnRemoveCallback = callback
end

function Action:AddEvent(name, time, callback)
    if not isstring(name) or name == "" then
        error("action event name must be a non-empty string", 2)
    end

    if not isnumber(time) or time < 0 or time > self.Duration then
        error("action event time must be within the action duration", 2)
    end

    if not isfunction(callback) then
        error("action event callback must be a function", 2)
    end

    local event = self.Events[name]
    if not event then
        event = {}
        self.Events[name] = event
        self.EventOrder[#self.EventOrder + 1] = name
    end

    event.time = time
    event.callback = callback
    event.played = false

    table.sort(self.EventOrder, function(leftName, rightName)
        local left = self.Events[leftName]
        local right = self.Events[rightName]
        if left.time == right.time then return leftName < rightName end
        return left.time < right.time
    end)
end

function Action:ReloadEvent(name)
    local event = self.Events[name]
    if event then event.played = false end
end

function Action:ReloadEvents()
    resetEvents(self)
end

function Action:HasEvent(name)
    return self.Events[name] ~= nil
end

function Action:HasEvents()
    return next(self.Events) ~= nil
end
