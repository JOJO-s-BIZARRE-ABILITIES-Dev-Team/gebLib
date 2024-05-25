// An Action class, for handling timed actions. Used instead of timers. Does not support prediction
// I literally took it from Dragon Ball GM
local gebLib = gebLib
//
gebLib.Action         = {}
gebLib.Action.__index = gebLib.Action
//
local Action = gebLib.Action
Action.ActionList     = {}

function Action.Create( entity, duration )
    local durTime = duration or 0 
    if isnumber( entity ) and !duration then
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

    return self
end

function Action:SetupThinking()
    local entity = self.Entity
    local thinkName = "gebLib.Action.Think_" .. self:GetIndex()
    self.ThinkName = thinkName
    //
    local startTime = CurTime() + self.StartDelay
    local repeatedFor = 0
    hook.Add("Think", thinkName, function()
        if !IsValid( self.Entity ) then return end
        if !self.Playing then self:Stop() return end // Remove if parent is invalid

        for k, EventInfo in pairs( self.Events ) do
            if EventInfo.Played then continue end
            if CurTime() > startTime + ( EventInfo.Timestamp / self.Timescale ) then
                EventInfo.Function( self )
                EventInfo.Played = true
            end
        end

        // Kill action when time comes
        if CurTime() > ( startTime + ( self.Duration / self.Timescale ) ) then
            if ( self.Repetitions == -1 ) then // Infinite loop
                startTime = CurTime() 
                repeatedFor = repeatedFor + 1
                self:ReloadEvents()
                return 
            end

            if repeatedFor < self.Repetitions then // Handle repetitions
                startTime = CurTime() 
                repeatedFor = repeatedFor + 1
                self:ReloadEvents() // Reload all events so they can be played again
            else
                self:Stop()
            end
        end
    end)
end

// Action:Start() - Starts the action. Argument #1 - how many times action will repeat, #2 - after how many seconds action will begin 
function Action:Start( repetitions, delay )
    if self:GetTimeScale() == 0 then return end // Don't start actions that have 0 timescale. Might break the logic
    
    self.Playing = true
    self.StartDelay = delay or 0
    self.Repetitions = repetitions or 0  
    //
    if self.FuncOnStart then
        self.FuncOnStart( self )
    end
    //
    self:SetupThinking()
end

// Action:Stop() - Stops and removes the action 
function Action:Stop()
    self.Playing = false
    self:Remove()
end

// Action:Pause() - Pauses the action
function Action:Pause() self.Playing = false end

// Action:Resume() - Resumes the action
function Action:Resume() self.Playing = true end

// Action:Remove() - Removes and stops the action
function Action:Remove()
    local actionId = self:GetIndex()
    hook.Remove( "Think", self.ThinkName )
    //
    if self.FuncOnRemove then
        self.FuncOnRemove( self )
    end
    --
    Action.ActionList[ actionId ] = nil
    setmetatable( self, nil )
    self = nil

    gebLib.PrintDebug( "Removed an Action " .. tostring( actionId ) )
end
//
function Action:SetTimeScale( timeScale ) self.Timescale = timeScale end
function Action:GetTimeScale( timeScale ) return self.Timescale end
function Action:IsPlaying() return self.Playing end
function Action:GetIndex() return self.ActionIndex end
//
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
    if self:HasEvents() then return end

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

function Action:HasEvent( name ) return self.Events[ name ] != nil end
function Action:HasEvents() return !table.IsEmpty( self.Events ) end
//