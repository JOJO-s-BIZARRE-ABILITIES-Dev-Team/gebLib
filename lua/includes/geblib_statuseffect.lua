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

gebLib_statuseffects = {} --List of all default status effects

function gebLib_statuseffects.New(name)
	local self = setmetatable({}, gebLib_statuseffects)

	if not isstring(name) then
		gebLib.PrintDebug("Status Effect name is invalid!")
	end

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
	self.FirstTimeApplied = true

	self.Flags = {}

	gebLib_statuseffects[self.Name] = self
	return self
end

function gebLib_statuseffects:Start(shouldRestart)
	shouldRestart = shouldRestart == nil and false or shouldRestart
	local entity = self.Entity

	if not entity:IsValid() then
		gebLib.PrintDebug("Status: " .. tostring(self.Name) .. " cannot be started, because it's entity is nil!")
		return
	end

	if self.ThinkName then
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
	hook.Add("Tick", thinkName, function()
		if self.Paused then return end

		if not self.Entity:gebLib_Alive() then
			self:End()
		end

		if not self.Initialized then
			self:Init()
		end

		if self.UpdateRate > 0 then
			if CurTime() - self.UpdateTime >= self.UpdateRate then
				self:Update()
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
		self:End()
		hook.Remove("Tick", self.ThinkName)
		-- hook.Remove("BA_TimeStop_StopTime", self.ThinkName)
		-- hook.Remove("BA_TimeStop_TimeResume", self.ThinkName)

		self.ThinkName = nil
		self.Initialized = false
		self.Ending = false

		self.UpdateTime = 0
		self.TimeStarted = 0
	end
end

function gebLib_statuseffects:Pause()
	self.TimePaused = CurTime()
	self.Paused = true
end

function gebLib_statuseffects:Unpause()
	self.Paused = false
end

function gebLib_statuseffects:Remove()
	if self.ThinkName then
		hook.Remove("Tick", self.ThinkName)
		-- hook.Remove("BA_TimeStop_StopTime", self.ThinkName)
		-- hook.Remove("BA_TimeStop_TimeResume", self.ThinkName)
	end

	if IsValid(self.Entity) then
		self.Entity.gebLib_statuseffects[self.Name] = nil
	end

	self = nil
end

function gebLib_statuseffects:Init()
	self.Initialized = true
	self.InitFunc(self)
	if self.FirstTimeApplied then self.FirstTimeApplied = false end
end

function gebLib_statuseffects:Update()
	self.UpdateTime = CurTime()
	self.UpdateFunc(self)
end

function gebLib_statuseffects:End()
	self.Ending = true
	--self:Update()
	self.EndFunc(self)
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

---comment
---@param someFlag StatusEffectFlag
---@return boolean
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
	shouldAppend = shouldAppend == nil and true or
		shouldAppend --If entity already has status effect, It won't replace, but prolong the effect

	if gebLib_statuseffects[name] then
		if not self.gebLib_StatusEffects then
			self.gebLib_StatusEffects = {}
		end

		if self:gebLib_HasStatusEffect(name) and shouldAppend then
			local status = self:gebLib_GetStatusEffect(name)
			status.LifeTime = status.LifeTime + lifeTime

			gebLib.PrintDebug("Appending to status: " .. tostring(name))

			return status
		else
			local status = table.Copy(gebLib_statuseffects[name])
			status.LifeTime = lifeTime
			status.Entity = self
			status.Attacker = attacker
			status.Inflictor = inflictor

			self.gebLib_StatusEffects[name] = status
			return status
		end
	else
		gebLib.PrintDebug("Status Effect: " .. tostring(name) .. " Does not exist!")
		return nil
	end

	hook.Run("gebLib.statuseffects.OnStatusEffectApplied", self, name, lifeTime, attacker, inflictor, shouldAppend)
end

---comment
---@return table
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
hook.Add("EntityRemoved", "gebLib.statuseffects.RemoveStatusEffects",
	function(ent) --Make sure status effects are removed on death
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
