if SERVER then return end

gebLib.ReplicaTrail = {}
gebLib.ReplicaTrail.__index = gebLib.ReplicaTrail

local ReplicaTrail = gebLib.ReplicaTrail

local function copyPosition(position)
    return Vector(position.x, position.y, position.z)
end

local function copyAngles(angles)
    return Angle(angles.p, angles.y, angles.r)
end

local function removeSnapshot(snapshot)
    if IsValid(snapshot.Replica) then snapshot.Replica:Remove() end
    snapshot.Replica = nil
    snapshot.Active = false
end

local function syncAppearance(self, replica)
    if not gebLib.PlayerReplica.SyncAppearance(replica, self.Source) then return false end
    if self.AppearanceAdapter then self.AppearanceAdapter(replica, self.Source) end
    return true
end

function ReplicaTrail.New(source, options)
    if not IsValid(source) then error("replica trail requires a valid source", 2) end
    options = options or {}
    local mode = options.mode or "sequence"
    if mode ~= "sequence" and mode ~= "matrices" then
        error("replica trail mode must be sequence or matrices", 2)
    end
    if options.appearance ~= nil and not isfunction(options.appearance) then
        error("replica trail appearance must be a function", 2)
    end

    local self = setmetatable({}, ReplicaTrail)
    self.Source = source
    self.Mode = mode
    self.Interval = math.max(tonumber(options.interval) or 0.05, 0)
    self.Lifetime = math.max(tonumber(options.lifetime) or 0.4, 0.001)
    self.Limit = math.max(math.floor(tonumber(options.limit) or 12), 1)
    self.RenderGroup = options.renderGroup or RENDERGROUP_TRANSLUCENT
    self.Shadows = options.shadows == true
    self.AppearanceInterval = math.max(tonumber(options.appearanceInterval) or 0.25, 0)
    self.AppearanceAdapter = options.appearance
    self.NextAppearance = 0
    self.Snapshots = {}
    self.NextSlot = 0
    self.NextCapture = 0
    self.SharedReplica = mode == "sequence"
        and gebLib.PlayerReplica.Create(source, self.RenderGroup, self.Shadows)
        or nil
    return self
end

function ReplicaTrail:SyncAppearance(now, force)
    if self.Mode ~= "sequence" or not IsValid(self.SharedReplica) then return false end
    now = now or RealTime()
    if not force and now < self.NextAppearance then return false end
    self.NextAppearance = now + self.AppearanceInterval
    return syncAppearance(self, self.SharedReplica)
end

function ReplicaTrail:IsValid()
    return IsValid(self.Source)
        and (self.Mode ~= "sequence" or IsValid(self.SharedReplica))
end

function ReplicaTrail:GetCount(now)
    if now then self:Expire(now) end
    local count = 0
    for index = 1, #self.Snapshots do
        if self.Snapshots[index].Active then count = count + 1 end
    end
    return count
end

function ReplicaTrail:Capture(now, position, angles)
    if not self:IsValid() or now < self.NextCapture then return nil end
    self.NextCapture = now + self.Interval

    self.NextSlot = self.NextSlot % self.Limit + 1
    local snapshot = self.Snapshots[self.NextSlot] or {}
    self.Snapshots[self.NextSlot] = snapshot
    snapshot.Active = true
    snapshot.CreatedAt = now
    snapshot.Position = copyPosition(position or self.Source:GetPos())
    snapshot.Angles = copyAngles(angles or self.Source:GetRenderAngles())

    if self.Mode == "sequence" then
        self:SyncAppearance(now)
        snapshot.Sequence = self.Source:GetSequence()
        snapshot.Cycle = self.Source:GetCycle()
    else
        if not IsValid(snapshot.Replica) then
            snapshot.Replica = gebLib.PlayerReplica.Create(
                self.Source,
                self.RenderGroup,
                self.Shadows
            )
        end
        if not IsValid(snapshot.Replica) then
            snapshot.Active = false
            return nil
        end

        syncAppearance(self, snapshot.Replica)
        gebLib.PlayerReplica.SyncPose(snapshot.Replica, self.Source)
        snapshot.Replica:SetPos(snapshot.Position)
        snapshot.Replica:SetAngles(snapshot.Angles)
        snapshot.Replica:SetupBones()
        snapshot.BoneMatrices, snapshot.BoneCount = gebLib.PlayerReplica.CaptureBoneMatrices(
            self.Source,
            snapshot.BoneMatrices
        )
    end
    return snapshot
end

function ReplicaTrail:Expire(now)
    for index = 1, #self.Snapshots do
        local snapshot = self.Snapshots[index]
        if snapshot.Active and now - snapshot.CreatedAt >= self.Lifetime then
            snapshot.Active = false
        end
    end
end

function ReplicaTrail:Refresh(now)
    for index = 1, #self.Snapshots do
        local snapshot = self.Snapshots[index]
        if snapshot.Active then snapshot.CreatedAt = now end
    end
end

function ReplicaTrail:ClearSnapshots()
    for index = 1, #self.Snapshots do self.Snapshots[index].Active = false end
end

function ReplicaTrail:GetSnapshots(now, output)
    self:SyncAppearance(now)
    self:Expire(now)
    local active = output or {}
    for index = #active, 1, -1 do active[index] = nil end
    for index = 1, #self.Snapshots do
        local snapshot = self.Snapshots[index]
        if snapshot.Active then active[#active + 1] = snapshot end
    end
    table.sort(active, function(left, right) return left.CreatedAt < right.CreatedAt end)
    return active
end

function ReplicaTrail:ForEach(now, callback)
    local active = self:GetSnapshots(now)

    for index = 1, #active do
        local snapshot = active[index]
        callback(
            snapshot,
            math.Clamp((now - snapshot.CreatedAt) / self.Lifetime, 0, 1),
            index,
            #active
        )
    end
end

function ReplicaTrail:DrawSnapshot(snapshot, position, angles, drawCallback)
    if not snapshot or not snapshot.Active then return false end
    local replica = self.Mode == "sequence" and self.SharedReplica or snapshot.Replica
    if not IsValid(replica) then return false end

    replica:SetPos(position or snapshot.Position)
    replica:SetAngles(angles or snapshot.Angles)
    if self.Mode == "sequence" then
        replica:SetSequence(snapshot.Sequence)
        replica:SetCycle(snapshot.Cycle)
        replica:SetPlaybackRate(0)
        replica:SetupBones()
    else
        replica:SetupBones()
        gebLib.PlayerReplica.ApplyBoneMatrices(
            replica,
            snapshot.BoneMatrices,
            snapshot.BoneCount
        )
    end

    if drawCallback then drawCallback(replica, snapshot) else replica:DrawModel() end
    return true
end

function ReplicaTrail:Draw(now, drawCallback)
    self:ForEach(now, function(snapshot, progress, index, count)
        self:DrawSnapshot(snapshot, nil, nil, function(replica)
            if drawCallback then
                drawCallback(replica, progress, index, count, snapshot)
            else
                replica:DrawModel()
            end
        end)
    end)
end

function ReplicaTrail:Remove()
    if IsValid(self.SharedReplica) then self.SharedReplica:Remove() end
    self.SharedReplica = nil
    for index = 1, #self.Snapshots do removeSnapshot(self.Snapshots[index]) end
    self.Snapshots = {}
    self.Source = nil
end
