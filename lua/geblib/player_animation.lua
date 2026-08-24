local Player = FindMetaTable("Player")

local playMessage = gebLib.Net.ToClient("geblib.player_animation.play", {
    gebLib.Net.Player,
    gebLib.Net.UInt(3),
    gebLib.Net.UInt(16),
    gebLib.Net.Float,
    gebLib.Net.Bool,
    gebLib.Net.Float,
})

local stopMessage = gebLib.Net.ToClient("geblib.player_animation.stop", {
    gebLib.Net.Player,
    gebLib.Net.UInt(3),
})

local pauseMessage = gebLib.Net.ToClient("geblib.player_animation.pause", {
    gebLib.Net.Player,
    gebLib.Net.UInt(3),
})

local resumeMessage = gebLib.Net.ToClient("geblib.player_animation.resume", {
    gebLib.Net.Player,
    gebLib.Net.UInt(3),
    gebLib.Net.Float,
})

local function shouldApplyPredicted(player)
    if SERVER then return true end
    return IsFirstTimePredicted() or LocalPlayer() ~= player
end

local function resolveSequence(player, sequence)
    if isstring(sequence) then
        sequence = player:LookupSequence(sequence)
    end

    if not isnumber(sequence) or sequence < 0 or sequence > 65535 or sequence % 1 ~= 0 then return nil end
    return sequence
end

local function applyPlay(player, slot, sequence, cycle, autokill, playback)
    player:AddVCDSequenceToGestureSlot(slot, sequence, cycle, autokill)
    player:SetLayerPlaybackRate(slot, playback)
end

local function applyStop(player, slot)
    player:SetLayerDuration(slot, 0)
    player:SetLayerCycle(slot, 1)
    player:SetLayerPlaybackRate(slot, 1)

    if SERVER then
        player:SetLayerLooping(slot, false)
    end
end

local function sendPlay(player, slot, sequence, cycle, autokill, playback)
    if CLIENT then return end
    playMessage:Broadcast(player, slot, sequence, cycle, autokill, playback)
end

local function validSlot(slot)
    return isnumber(slot) and slot >= 0 and slot <= 7 and slot % 1 == 0
end

function Player:gebLib_PlaySequence(slot, sequence, cycle, autokill, playback)
    if not IsValid(self) or not validSlot(slot) or not shouldApplyPredicted(self) then return false end

    sequence = resolveSequence(self, sequence)
    if not sequence then return false end

    cycle = cycle or 0
    playback = playback or 1
    if autokill == nil then autokill = true end

    if not isnumber(cycle) or not isnumber(playback) then return false end
    cycle = math.Clamp(cycle, 0, 1)

    applyPlay(self, slot, sequence, cycle, autokill, playback)
    sendPlay(self, slot, sequence, cycle, autokill, playback)
    return true
end

function Player:gebLib_StopSequence(slot)
    if not IsValid(self) or not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    applyStop(self, slot)
    if SERVER then stopMessage:Broadcast(self, slot) end
    return true
end

function Player:gebLib_PauseSequence(slot)
    if not IsValid(self) or not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    self:SetLayerPlaybackRate(slot, 0)
    if SERVER then pauseMessage:Broadcast(self, slot) end
    return true
end

function Player:gebLib_ResumeSequence(slot, playback)
    if not IsValid(self) or not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    playback = playback or 1
    if not isnumber(playback) then return false end
    self:SetLayerPlaybackRate(slot, playback)
    if SERVER then resumeMessage:Broadcast(self, slot, playback) end
    return true
end

function Player:gebLib_PlayAction(sequence, playback)
    return self:gebLib_PlaySequence(1, sequence, 0, true, playback)
end

function Player:gebLib_StopAction()
    return self:gebLib_StopSequence(1)
end

function Player:gebLib_PauseAction()
    return self:gebLib_PauseSequence(1)
end

function Player:gebLib_ResumeAction(playback)
    return self:gebLib_ResumeSequence(1, playback)
end

if CLIENT then
    playMessage:Receive(function(player, slot, sequence, cycle, autokill, playback)
        applyPlay(player, slot, sequence, cycle, autokill, playback)
    end)

    stopMessage:Receive(function(player, slot)
        applyStop(player, slot)
    end)

    pauseMessage:Receive(function(player, slot)
        player:SetLayerPlaybackRate(slot, 0)
    end)

    resumeMessage:Receive(function(player, slot, playback)
        player:SetLayerPlaybackRate(slot, playback)
    end)
end
