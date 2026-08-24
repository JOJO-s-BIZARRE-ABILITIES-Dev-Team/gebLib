
--------------------
--Contributors: T0M
--------------------

-------------------------------------------------------------------
--Custom system that handles buffs, debuffs and other statuses.
--For example, you can very easily make a bleeding or poison effect.
-------------------------------------------------------------------

local MENT = FindMetaTable("Entity")

gebLib_statuseffects = {}
gebLib_statuseffects.__index = gebLib_statuseffects

function gebLib_statuseffects.New(name)
    if not isstring(name) then
        error("Status Effect name must be a string")
    end

    local self = setmetatable({}, gebLib_statuseffects)

    self.Name = name
    self.Entity = nil
    self.Attacker = nil
    self.Inflictor = nil
    
    self.InitFunc = nil
    self.UpdateFunc = nil
    self.EndFunc = nil
    
    self.Initialized = false
    self.Paused = false
    self.UpdateRate = 0 --How fast the update function runs
    self.LifeTime = 0 --How long can the status effect exist

    self.UpdateTime = 0 --Used to check if update function should run
    self.TimePaused = 0
    self.TimeStarted = 0 --When did the status effect start

    self.ThinkName = nil
    self.Ending = false
    self.Removed = false
    self.FirstTimeApplied = true

    self.Flags = {}

    gebLib_statuseffects[self.Name] = self
    return self
end

function gebLib_statuseffects:Start(shouldRestart)
    if self.Removed or self.Ending then return end

    shouldRestart = shouldRestart == nil and false or shouldRestart
    local entity = self.Entity

    if not IsValid(entity) then
        gebLib.PrintDebug("Status: " .. tostring(self.Name) .. " cannot be started, because it's entity is nil!")
        return
    end

    if self.ThinkName then
        if not shouldRestart then return end
        self:Stop()
    end

    --self.LifeTime = self.LifeTime + self.UpdateRate

    -- if BA_IsTimeStopped() then
    --     self:Pause()
    -- end

    local statusIndex = self.Entity.gebLib_StatusEffects and #self.Entity.gebLib_StatusEffects or 0

    local thinkName = "gebLib_" .. entity:GetClass() .. entity:EntIndex() .. self.Name .. statusIndex
    self.ThinkName = thinkName

    self.TimeStarted = CurTime()
    self.UpdateTime = CurTime()
    self.Ending = false
    self.Paused = false
    hook.Add("Tick", thinkName, function()
        if self.Paused then return end

        if not self.Entity:gebLib_Alive() and not self:HasFlag(GEBLIB_EFFECT_FLAGS.PERSIST) then
            self:End()
            return
        end

        if not self.Initialized then
            self:Init()
            if self.Ending or not self.ThinkName then return end
        end

        if self.UpdateRate > 0 then
            if CurTime() - self.UpdateTime >= self.UpdateRate then
                self:Update()
                if not self.ThinkName or self.Paused then return end
            end
        end

        if self:GetLifeTime() >= self.LifeTime then
            self:End()
        end
    end)

    -- --Time stop handling
    -- hook.Add("BA_TimeStop_StopTime", self.ThinkName, function(tsEntity, firstStopper)
    --     self:Pause()
    -- end)

    -- hook.Add("BA_TimeStop_TimeResume", self.ThinkName, function(tsEntity, firstStopper, stoppers)
    --     local timeFromTS = (CurTime() - self.TimePaused)
    --     self.TimeStarted = self.TimeStarted + timeFromTS
    --     self.UpdateTime = self.UpdateTime + timeFromTS
    --     self:Unpause()
    -- end)
end

function gebLib_statuseffects:Stop() --This will stop the status effect, but won't delete it, instead it will reset some values to default state, so it can be run again
    if self.ThinkName then
        hook.Remove("Tick", self.ThinkName)
        -- hook.Remove("BA_TimeStop_StopTime", self.ThinkName)
        -- hook.Remove("BA_TimeStop_TimeResume", self.ThinkName)

        self.ThinkName = nil
        if self.Initialized and self.EndFunc then
            self.Ending = true
            self.EndFunc(self)
        end

        self.Initialized = false
        self.Ending = false
        self.Paused = false

        self.UpdateTime = 0
        self.TimeStarted = 0
    end
end

function gebLib_statuseffects:Pause() 
    if self.Paused then return end

    self.TimePaused = CurTime()
    self.Paused = true
end

function gebLib_statuseffects:Unpause() 
    if not self.Paused then return end

    local pausedFor = CurTime() - self.TimePaused
    self.TimeStarted = self.TimeStarted + pausedFor
    self.UpdateTime = self.UpdateTime + pausedFor
    self.TimePaused = 0
    self.Paused = false
end

function gebLib_statuseffects:Remove()
    if self.Removed then return end

    if self.ThinkName then
        hook.Remove("Tick", self.ThinkName)
        -- hook.Remove("BA_TimeStop_StopTime", self.ThinkName)
        -- hook.Remove("BA_TimeStop_TimeResume", self.ThinkName)
    end

    self.ThinkName = nil
    self.Initialized = false
    self.Paused = false
    self.Removed = true
    if IsValid(self.Entity) and self.Entity.gebLib_StatusEffects and self.Entity.gebLib_StatusEffects[self.Name] == self then
        self.Entity.gebLib_StatusEffects[self.Name] = nil
    end
end

function gebLib_statuseffects:Init()
    self.Initialized = true
    if self.InitFunc then
        self.InitFunc(self)
    end
    if self.FirstTimeApplied then self.FirstTimeApplied = false end
end

function gebLib_statuseffects:Update()
    self.UpdateTime = CurTime()
    if self.UpdateFunc then
        self.UpdateFunc(self)
    end
end

function gebLib_statuseffects:End()
    if self.Ending then return end

    self.Ending = true
    if self.EndFunc then
        self.EndFunc(self)
    end
    self:Remove()
end

--Getters & Setters
function gebLib_statuseffects:SetInit(func)
    self.InitFunc = func
end

function gebLib_statuseffects:SetUpdate(updateRate, func)
    self.UpdateRate = updateRate
    self.UpdateFunc = func
end

function gebLib_statuseffects:SetEnd(func)
    self.EndFunc = func
end

function gebLib_statuseffects:GetLifeTime()
    return CurTime() - self.TimeStarted
end

function gebLib_statuseffects:AddFlag(flag)
    table.insert(self.Flags, flag)
end

--Used for one time logic when the effect is first added on to an entity
function gebLib_statuseffects:IsFirstTime()
    return self.FirstTimeApplied
end

function gebLib_statuseffects:HasFlag(someFlag)
    for _, flag in ipairs(self.Flags) do
        if flag == someFlag then
            return true
        end
    end
    return false
end

--Entity Functions
function MENT:gebLib_AddStatusEffect(name, lifeTime, attacker, inflictor, shouldAppend)
    shouldAppend = shouldAppend == nil and true or shouldAppend --If entity already has status effect, It won't replace, but prolong the effect

    if not gebLib_statuseffects[name] then
        gebLib.PrintDebug("Status Effect: " .. tostring(name) .. " Does not exist!")
        return nil
    end

    if not self.gebLib_StatusEffects then
        self.gebLib_StatusEffects = {}
    end

    local status = self:gebLib_GetStatusEffect(name)
    if status and shouldAppend then
        status.LifeTime = status.LifeTime + (lifeTime or 0)
        gebLib.PrintDebug("Appending to status: " .. tostring(name))
    else
        if status then status:End() end

        status = table.Copy(gebLib_statuseffects[name])
        status.LifeTime = lifeTime or 0
        status.Entity = self
        status.Attacker = attacker
        status.Inflictor = inflictor
        self.gebLib_StatusEffects[name] = status
    end

    hook.Run( "gebLib.statuseffects.OnStatusEffectApplied", self, name, lifeTime, attacker, inflictor, shouldAppend )
    return status
end

function MENT:gebLib_GetStatusEffects()
    return self.gebLib_StatusEffects
end

function MENT:gebLib_GetStatusEffect(name)
    if not self.gebLib_StatusEffects then return nil end

    return self.gebLib_StatusEffects[name]
end

function MENT:gebLib_HasStatusEffect(name)
    return self:gebLib_GetStatusEffect(name) ~= nil
end

--Hooks
hook.Add("EntityRemoved", "gebLib.statuseffects.RemoveStatusEffects", function(ent) --Make sure status effects are removed on death
    local statusEffects = ent:gebLib_GetStatusEffects()

    if statusEffects then
        for name, effect in pairs(statusEffects) do
            if not effect:HasFlag(GEBLIB_EFFECT_FLAGS.PERSIST) then

                effect:End()
            end
        end
    end
end)

hook.Add("PlayerDeath", "gebLib.statuseffects.RemoveStatusEffects", function(ent)
    local statusEffects = ent:gebLib_GetStatusEffects()

    if statusEffects then
        for name, effect in pairs(statusEffects) do
            if not effect:HasFlag(GEBLIB_EFFECT_FLAGS.PERSIST) then
                effect:End()
            end
        end
    end
end)
