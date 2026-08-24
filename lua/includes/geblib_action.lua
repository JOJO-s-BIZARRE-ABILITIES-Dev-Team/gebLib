-- An Action class, for handling timed actions. Used instead of timers. Does not support prediction
-- I literally took it from Dragon Ball GM
local gebLib = gebLib
--
gebLib.Action         = {}
gebLib.Action.__index = gebLib.Action
--
local Action = gebLib.Action
Action.ActionList     = {}

function Action.Create( entity, duration )
    local durTime = duration or 0 
    if isnumber( entity ) and not duration then
        durTime = entity
        entity = game.GetWorld()
    end

    local self = setmetatable( {}, Action )
    self.Entity             = entity
    self.Duration           = durTime
    self.Events             = {}
    self.Timescale          = 1
    self.Repetitions        = 0
    self.StartDelay         = 0

    self.Playing            = false
    self.ThinkName          = nil
    self.ActionIndex        = table.insert( Action.ActionList, self )
    self.LifeTime           = 0

    self.StartTime = 0
    self.RepeatedFor = 0
    self.PauseTime = nil
    self.Removed = false

    return self
end

function Action:SetupThinking()
    local thinkName = "gebLib.Action.Think_" .. self:GetIndex()
    self.ThinkName = thinkName
    --
    self.StartTime = CurTime() + self.StartDelay
    self.RepeatedFor = 0
    hook.Add("Think", thinkName, function()
        if self.Removed then return end
        if not IsValid( self.Entity ) then self:Remove() return end
        if not self.Playing then return end

        for k, EventInfo in pairs( self.Events ) do
            if not EventInfo.Played and CurTime() > self.StartTime + ( EventInfo.Timestamp / self.Timescale ) then
                EventInfo.Function( self )
                EventInfo.Played = true
                if self.Removed or not self.Playing then return end
            end
        end

        -- Kill action when time comes
        if CurTime() > ( self.StartTime + ( self.Duration / self.Timescale ) ) then
            if ( self.Repetitions == -1 ) then -- Infinite loop
                self.StartTime = CurTime() 
                self.RepeatedFor = self.RepeatedFor + 1
                self:ReloadEvents()
                return 
            end

            if self.RepeatedFor < self.Repetitions then -- Handle repetitions
                self.StartTime = CurTime() 
                self.RepeatedFor = self.RepeatedFor + 1
                self:ReloadEvents() -- Reload all events so they can be played again
            else
                self:Stop()
            end
        end
    end)
end

-- Action:Start() - Starts the action. Argument #1 - how many times action will repeat, #2 - after how many seconds action will begin
function Action:Start( repetitions, delay )
    if self.Removed or self:GetTimeScale() <= 0 then return end
    
    self.Playing = true
    self.StartDelay = delay or 0
    self.Repetitions = repetitions or 0  
    self.PauseTime = nil
    --
    if self.FuncOnStart then
        self.FuncOnStart( self )
        if self.Removed then return end
    end
    --
    self:SetupThinking()
end

-- Action:Stop() - Stops and removes the action
function Action:Stop()
    self.Playing = false
    self:Remove()
end

-- Action:Pause() - Pauses the action
function Action:Pause()
    if not self.Playing or self.Removed then return end

    self.PauseTime = CurTime()
    self.Playing = false
end

-- Action:Resume() - Resumes the action
function Action:Resume()
    if self.Playing or self.Removed or not self.PauseTime then return end

    self.StartTime = self.StartTime + ( CurTime() - self.PauseTime )
    self.PauseTime = nil

    self.Playing = true
end

-- Action:Remove() - Removes and stops the action
function Action:Remove()
    if self.Removed then return end

    local actionId = self:GetIndex()
    if self.ThinkName then
        hook.Remove( "Think", self.ThinkName )
    end

    self.Playing = false
    self.Removed = true
    --
    if self.FuncOnRemove then
        self.FuncOnRemove( self )
    end
    --
    Action.ActionList[ actionId ] = nil

    gebLib.PrintDebug( "Removed an Action " .. tostring( actionId ) )
end
--
function Action:SetTimeScale( timeScale ) self.Timescale = timeScale end
function Action:GetTimeScale() return self.Timescale end
function Action:IsPlaying() return self.Playing end
function Action:GetIndex() return self.ActionIndex end
--
function Action:SetInit( func )
    self.Events[ "__event_Init" ] = { Timestamp = 0, Function = func, Played = false }
end

function Action:SetEnd( func )
    self.Events[ "__event_End" ] = { Timestamp = self.Duration, Function = func, Played = false }
end

function Action:OnStart( func )
    self.FuncOnStart = func
end

function Action:OnRemove( func )
    self.FuncOnRemove = func
end

function Action:AddEvent( name, time, func )
    if time > self.Duration then
        error("Incorrect timestamp!")
    end

    self.Events[ name ] = { Timestamp = time, Function = func, Played = false }
end

function Action:ReloadEvent( name )
    if not self:HasEvents() then return end

    if self:HasEvent( name ) then
        self.Events[ name ].Played = false 
    else
        gebLib.PrintDebug( "Event: " .. tostring( name ) .. " cannot be reloaded because it does not exist!" )
    end
end

function Action:ReloadEvents()
    if not self:HasEvents() then return end

    for _, Event in pairs( self.Events ) do
        Event.Played = false
    end

    gebLib.PrintDebug( "Action: " .. tostring( self:GetIndex() ) .. " has reloaded all events!" )
end

function Action:HasEvent( name ) return self.Events[ name ] ~= nil end
function Action:HasEvents() return not table.IsEmpty( self.Events ) end
--
