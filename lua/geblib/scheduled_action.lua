local ScheduledAction = {}
ScheduledAction.__index = ScheduledAction
gebLib.ScheduledAction = ScheduledAction

local Runtime = gebLib._Runtime
if not Runtime then
    local loader = include or function(path) return assert(loadfile("lua/" .. path))() end
    Runtime = loader("geblib/runtime.lua")
end

gebLib._NextScheduledActionId = gebLib._NextScheduledActionId or 0

local states = setmetatable({}, {__mode = "k"})

local function nextId()
    gebLib._NextScheduledActionId = gebLib._NextScheduledActionId + 1
    return gebLib._NextScheduledActionId
end

local function stateOf(action)
    return states[action]
end

local function isPending(state)
    return state and (state.status == "pending" or state.status == "paused") or false
end

local function advance(state, now)
    local elapsed = math.max(0, now - state.lastUpdate)
    state.elapsed = state.elapsed + elapsed * state.timeScale
    state.lastUpdate = now
end

local function cancelAction(action)
    action:Cancel()
end

local function stepAction(action)
    local state = stateOf(action)
    if not isPending(state) then return false end

    if not IsValid(state.owner) then
        action:Cancel()
        return false
    end

    if state.status == "paused" then return true end

    advance(state, CurTime())
    if state.elapsed < state.delay then return true end

    Runtime.Unregister(action)
    state.status = "completed"
    Runtime.Invoke(
        action,
        "Scheduled Action " .. state.id .. " callback",
        state.callback,
        nil,
        action
    )
    return false
end

function ScheduledAction.After(owner, delay, callback)
    if not IsValid(owner) then
        error("scheduled action owner must be valid", 2)
    end
    if not isnumber(delay) or delay < 0 then
        error("scheduled action delay must be zero or greater", 2)
    end
    if not isfunction(callback) then
        error("scheduled action callback must be a function", 2)
    end

    local action = setmetatable({}, ScheduledAction)
    local state = {
        owner = owner,
        delay = delay,
        callback = callback,
        elapsed = 0,
        lastUpdate = CurTime(),
        timeScale = 1,
        status = "pending",
        id = nextId(),
    }
    states[action] = state

    Runtime.Register(
        action,
        "Scheduled Action " .. state.id,
        stepAction,
        cancelAction,
        cancelAction
    )
    return action
end

function ScheduledAction:Cancel()
    local state = stateOf(self)
    if not isPending(state) then return false end

    Runtime.Unregister(self)
    state.status = "cancelled"
    return true
end

function ScheduledAction:Pause()
    local state = stateOf(self)
    if not state or state.status ~= "pending" then return false end

    advance(state, CurTime())
    state.status = "paused"
    return true
end

function ScheduledAction:Resume()
    local state = stateOf(self)
    if not state or state.status ~= "paused" then return false end
    if not IsValid(state.owner) then
        self:Cancel()
        return false
    end

    state.lastUpdate = CurTime()
    state.status = "pending"
    return true
end

function ScheduledAction:SetTimeScale(timeScale)
    if not isnumber(timeScale) or timeScale <= 0 then
        error("scheduled action time scale must be greater than zero", 2)
    end

    local state = stateOf(self)
    if not isPending(state) then return false end

    if state.status == "pending" then advance(state, CurTime()) end
    state.timeScale = timeScale
    return true
end

function ScheduledAction:IsPending()
    return isPending(stateOf(self))
end

return ScheduledAction
