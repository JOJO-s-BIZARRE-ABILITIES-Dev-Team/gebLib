local Player = FindMetaTable("Player")

local messageName = "gebLib.PlayerAnimation"
local PLAY = 0
local STOP = 1
local PAUSE = 2
local RESUME = 3

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

local function send(player, operation, slot, sequence, cycle, autokill, playback)
    if CLIENT then return end

    net.Start(messageName)
    net.WriteEntity(player)
    net.WriteUInt(operation, 2)
    net.WriteUInt(slot, 3)

    if operation == PLAY then
        net.WriteUInt(sequence, 16)
        net.WriteFloat(cycle)
        net.WriteBool(autokill)
        net.WriteFloat(playback)
    elseif operation == RESUME then
        net.WriteFloat(playback)
    end

    net.Broadcast()
end

local function validSlot(slot)
    return isnumber(slot) and slot >= 0 and slot <= 7 and slot % 1 == 0
end

function Player:gebLib_PlaySequence(slot, sequence, cycle, autokill, playback)
    if not validSlot(slot) or not shouldApplyPredicted(self) then return false end

    sequence = resolveSequence(self, sequence)
    if not sequence then return false end

    cycle = cycle or 0
    playback = playback or 1
    if autokill == nil then autokill = true end

    if not isnumber(cycle) or not isnumber(playback) then return false end

    applyPlay(self, slot, sequence, cycle, autokill, playback)
    send(self, PLAY, slot, sequence, cycle, autokill, playback)
    return true
end

function Player:gebLib_StopSequence(slot)
    if not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    applyStop(self, slot)
    send(self, STOP, slot)
    return true
end

function Player:gebLib_PauseSequence(slot)
    if not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    self:SetLayerPlaybackRate(slot, 0)
    send(self, PAUSE, slot)
    return true
end

function Player:gebLib_ResumeSequence(slot, playback)
    if not validSlot(slot) or not shouldApplyPredicted(self) then return false end
    playback = playback or 1
    if not isnumber(playback) then return false end
    self:SetLayerPlaybackRate(slot, playback)
    send(self, RESUME, slot, nil, nil, nil, playback)
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

if SERVER then
    util.AddNetworkString(messageName)
else
    net.Receive(messageName, function()
        local player = net.ReadEntity()
        local operation = net.ReadUInt(2)
        local slot = net.ReadUInt(3)

        if not IsValid(player) or not player:IsPlayer() then return end

        if operation == PLAY then
            applyPlay(player, slot, net.ReadUInt(16), net.ReadFloat(), net.ReadBool(), net.ReadFloat())
        elseif operation == STOP then
            applyStop(player, slot)
        elseif operation == PAUSE then
            player:SetLayerPlaybackRate(slot, 0)
        elseif operation == RESUME then
            player:SetLayerPlaybackRate(slot, net.ReadFloat())
        end
    end)
end
