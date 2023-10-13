--This is a static net class made for easier networking
--Made by T0M

if SERVER then
    util.AddNetworkString("gebLib.cl.core.UpdateString")
    util.AddNetworkString("gebLib.cl.core.UpdateInt")
    util.AddNetworkString("gebLib.cl.core.UpdateUInt")
    util.AddNetworkString("gebLib.cl.core.UpdateFloat")
    util.AddNetworkString("gebLib.cl.core.UpdateBool")
    util.AddNetworkString("gebLib.cl.core.UpdateTable")
    util.AddNetworkString("gebLib.cl.core.UpdateVector")
    util.AddNetworkString("gebLib.cl.core.UpdateVectorNormal")
    util.AddNetworkString("gebLib.cl.core.UpdateAngle")
    util.AddNetworkString("gebLib.cl.core.UpdateColor")
    util.AddNetworkString("gebLib.cl.core.UpdateByIndex")
end

//////////////////////////////////////
local rshift = bit.rshift
local max = math.max
local abs       = math.abs
local mathFloor     = math.floor
local mathLog       = math.log
local isstring      = isstring
local isnumber      = isnumber
local isbool        = isbool
local istable       = istable
local isvector      = isvector
local isangle       = isangle
local IsColor       = IsColor
local Compress      = util.Compress
local Decompress    = util.Decompress
local JSONToTable   = util.JSONToTable
local TableToJSON   = util.TableToJSON
-- local netStart      = net.Start              // i dont think localizing all of this will be even effective
-- local netWriteString    = net.WriteString
-- local netReadString     = net.ReadString
-- local netWriteBool      = net.WriteBool
-- local netReadBool       = net.ReadBool
-- local netWriteInt       = net.WriteInt
-- local netWriteUInt      = net.WriteUInt
-- local netWriteUInt64    = net.WriteUInt64
-- local netReadInt        = net.ReadInt
-- local netReadUInt       = net.ReadUInt
-- local netReadUInt64     = net.ReadUInt64
-- local netWriteData      = net.WriteData
-- local netReadData       = net.ReadData
-- local netWriteBit       = net.WriteBit  
-- local netReadBit        = net.ReadBit
//////////////////////////////////////

gebLib_net = {}

--Helper functions
function gebLib_net.UIntToBits(uInt)
    if uInt < 0 then error("can't convert unsigned int that is less than 0") end
    if uInt == 0 then return 1 end

    local bitsAmount = 0
    while uInt > 0 do
        bitsAmount = bitsAmount + 1
        uInt = rshift(uInt, 1)
    end

    return bitsAmount
end

function gebLib_net.IntToBits(int)
    if int < 0 then
        int = abs(int + 1)
    end

    return max(UIntToBits(int) + 1, 3)
end

local UIntToBits = gebLib_net.UIntToBits
local IntToBits = gebLib_net.IntToBits

--Substracting 1 from the amount, so that the range is from 0 - 31 instead of 1 - 32, saving one bit
function gebLib_net.WriteBits(amount)
    net.WriteUInt(amount - 1, 5)
end

--Adding the substracted 1 back, so it correctly represents the bits amount
function gebLib_net.ReadBits()
    return net.ReadUInt(5) + 1
end

local WriteBits = gebLib_net.WriteBits
local ReadBits = gebLib_net.ReadBits

function gebLib_net.WritePlayer(ply)
    net.WriteUInt(ply:EntIndex(), player.GetCount())
end

function gebLib_net.ReadPlayer()
    return Entity(net.ReadUInt(player.GetCount()))
end

local WritePlayer = gebLib_net.WritePlayer
local ReadPlayer = gebLib_net.ReadPlayer

function gebLib_net.WriteEntity(ent)
    local isPlayer = ent:IsPlayer()
    net.WriteBool(isPlayer)

    if isPlayer then
        WritePlayer(ent)
        return
    end

    local entIndex = ent:EntIndex()
    local bitsAmount = UIntToBits(entIndex)
    WriteBits(bitsAmount)
    net.WriteUInt(entIndex)
end

function gebLib_net.ReadEntity()
    local isPlayer = net.ReadBool()

    if isPlayer then
        return ReadPlayer()
    end

    local bits = ReadBits()
    return Entity(net.ReadUInt(bits))
end

local WriteEntity = gebLib_net.WriteEntity
local ReadEntity = gebLib_net.ReadEntity

function gebLib_net.WriteEntityAndVar(ent, var)
    WriteEntity(ent)
    net.WriteString(var)
end

function gebLib_net.ReadEntityAndVar()
    return ReadEntity(), net.ReadString()
end

function gebLib_net.UpdateEntityValue(entity, varName, valueToSet)
    if CLIENT then return end
    entity[varName] = valueToSet
    if isstring(valueToSet) then
        gebLib_net.UpdateEntityString(entity, varName, valueToSet)
    elseif isnumber(valueToSet) then
        gebLib_net.UpdateEntityNumber(entity, varName, valueToSet)
    elseif isbool(valueToSet) then
        gebLib_net.UpdateEntityBool(entity, varName, valueToSet)
    elseif isvector(valueToSet) then
        gebLib_net.UpdateEntityVector(entity, varName, valueToSet)
    elseif isangle(valueToSet) then
        gebLib_net.UpdateEntityAngle(entity, varName, valueToSet)
    elseif IsColor(valueToSet) then
        gebLib_net.UpdateEntityColor(entity, varName, valueToSet)
    elseif istable(valueToSet) then
        gebLib_net.UpdateEntityTable(entity, varName, valueToSet)
    end
end

function gebLib_net.UpdateEntityString(entity, varName, stringToSet)
    net.Start("gebLib.cl.core.UpdateString")
    net.WriteString(stringToSet) --Has to be first!
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityTable(entity, varName, tableToSet)
    local json = TableToJSON(tableToSet)
    local compressedData = Compress(json)
    local bytesAmount = #compressedData

    net.Start("gebLib.cl.core.UpdateTable")
    net.WriteUInt(bytesAmount, 16)
    net.WriteData(compressedData, bytesAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityColor(entity, varName, colorToSet)
    net.Start("gebLib.cl.core.UpdateColor")
    net.WriteColor(colorToSet, false)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityVector(entity, varName, vectorToSet)
    if gebLib_IsNormalized(vectorToSet) then
        gebLib_net.UpdateEntityNormalVector()
    else
        gebLib_net.UpdateEntityVectorSlow()
    end
end

function gebLib_net.UpdateEntityVectorSlow(entity, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVector")
    net.WriteVector(vectorToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityNormalVector(entity, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVectorNormal")
    net.WriteNormal(vectorToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityAngle(entity, varName, angleToSet)
    net.Start("gebLib.cl.core.UpdateAngle")
    net.WriteAngle(angleToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityBool(entity, varName, boolToSet)
    net.Start("gebLib.cl.core.UpdateBool")
    net.WriteBool(boolToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityNumber(entity, varName, numberToSet)
    if numberToSet % 1 != 0 then
        gebLib_net.UpdateEntityFloat(entity, varName, numberToSet)
    elseif numberToSet > 0 then
        gebLib_net.UpdateEntityUInt(entity, varName, numberToSet)
    else
        gebLib_net.UpdateEntityInt(entity, varName, numberToSet)
    end
end

function gebLib_net.UpdateEntityInt(entity, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = IntToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateInt")
    net.WriteUInt(bitsAmount, 6)
    net.WriteInt(numberToSet, bitsAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

--Use with non negative numbers for smaller packets
function gebLib_net.UpdateEntityUInt(entity, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = UIntToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateUInt")
    net.WriteUInt(bitsAmount, 6)
    net.WriteUInt(numberToSet, bitsAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityFloat(entity, varName, numberToSet)
    net.Start("gebLib.cl.core.UpdateFloat")
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.WriteFloat(numberToSet)
    net.Broadcast()
end

--Handling for clients
if CLIENT then
    local function DebugMessage(len, entity, varName, value)
        if gebLib.DebugMode() and gebLib.NetworkDebug() then
            gebLib_PrintDebug(tostring(LocalPlayer()) .. ": network message length: " .. len .. " bits, " .. "entity: " .. tostring(entity) .. ", variable name: " .. varName .. ", variable value: " ..tostring(value))
        end
    end

    local function SetEntityValue(value, len)
        local entity = net.ReadEntity()
        local varName = net.ReadString()
        DebugMessage(len, entity, varName, value)

        if !IsValid( entity ) then
            error("gebLib Networking: Trying to update variable: " .. varName .. " to value: " .. tostring(value) .. " on entity that is nil, entity might not be loaded or does not exist on the client!")
        end

        entity[varName] = value
    end

    net.Receive("gebLib.cl.core.UpdateString", function(len)
        local text = net.ReadString()
        SetEntityValue(text, len)
    end)

    net.Receive("gebLib.cl.core.UpdateInt", function(len)
        local bitsAmount = net.ReadUInt(6)
        local value = net.ReadInt(bitsAmount)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateUInt", function(len)
        local bitsAmount = net.ReadUInt(6)
        local value = net.ReadUInt(bitsAmount)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateFloat", function(len)
        local value = net.ReadFloat()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateBool", function(len)
        local value = net.ReadBool()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateVector", function(len)
        local value = net.ReadVector()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateVectorNormal", function(len)
        local value = net.ReadNormal()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateAngle", function(len)
        local value = net.ReadAngle()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateColor", function(len)
        local value = net.ReadColor(false)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateTable", function(len)
        local bytesAmount = net.ReadUInt(16)
        local value = JSONToTable(Decompress(net.ReadData(bytesAmount)))
        SetEntityValue(value, len)
    end)
end