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

--TODO: Add documentation to this
gebLib_net.VarsToIndexes = {}
gebLib_net.IndexedVars = {}

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
    net.WriteUInt(ply:EntIndex(), UIntToBits(player.GetCount() - 1))
end

function gebLib_net.ReadPlayer()
    local bits = UIntToBits(player.GetCount() - 1)
    return Entity(net.ReadUInt(bits))
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
    net.WriteUInt(entIndex, bitsAmount)
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
    net.WriteBool(isnumber(var))
    if isnumber(var) then
        net.WriteUInt(var, UIntToBits(#gebLib_net.IndexedVars))
    else
        net.WriteString(var)
    end
end

function gebLib_net.ReadEntityAndVar()
    local ent = ReadEntity()
    local isIndex = net.ReadBool()
    local var

    if isIndex then
        var = net.ReadUInt(UIntToBits(#gebLib_net.IndexedVars))
    else
        var = net.ReadString()
    end

    return ent, var
end

local WriteEntityAndVar = gebLib_net.WriteEntityAndVar
local ReadEntityAndVar = gebLib_net.ReadEntityAndVar

function gebLib_net.UpdateEntityValue(ent, varName, valueToSet)
    if CLIENT then return end
    ent[varName] = valueToSet

    if gebLib_net.VarsToIndexes[varName] then
        varName = gebLib_net.VarsToIndexes[varName]
    end

    if isstring(valueToSet) then
        gebLib_net.UpdateEntityString(ent, varName, valueToSet)
    elseif isnumber(valueToSet) then
        gebLib_net.UpdateEntityNumber(ent, varName, valueToSet)
    elseif isbool(valueToSet) then
        gebLib_net.UpdateEntityBool(ent, varName, valueToSet)
    elseif isvector(valueToSet) then
        gebLib_net.UpdateEntityVector(ent, varName, valueToSet)
    elseif isangle(valueToSet) then
        gebLib_net.UpdateEntityAngle(ent, varName, valueToSet)
    elseif IsColor(valueToSet) then
        gebLib_net.UpdateEntityColor(ent, varName, valueToSet)
    elseif istable(valueToSet) then
        gebLib_net.UpdateEntityTable(ent, varName, valueToSet)
    end
end

function gebLib_net.UpdateEntityString(ent, varName, stringToSet)
    net.Start("gebLib.cl.core.UpdateString")
    net.WriteString(stringToSet)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityTable(ent, varName, tableToSet)
    local json = TableToJSON(tableToSet)
    local compressedData = Compress(json)
    local bytesAmount = #compressedData

    net.Start("gebLib.cl.core.UpdateTable")
    net.WriteUInt(bytesAmount, 16)
    net.WriteData(compressedData, bytesAmount)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityColor(ent, varName, colorToSet)
    net.Start("gebLib.cl.core.UpdateColor")
    net.WriteColor(colorToSet, false)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityVector(ent, varName, vectorToSet)
    if gebLib_IsNormalized(vectorToSet) then
        gebLib_net.UpdateEntityNormalVector()
    else
        gebLib_net.UpdateEntityVectorSlow()
    end
end

function gebLib_net.UpdateEntityVectorSlow(ent, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVector")
    net.WriteVector(vectorToSet)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityNormalVector(ent, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVectorNormal")
    net.WriteNormal(vectorToSet)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityAngle(ent, varName, angleToSet)
    net.Start("gebLib.cl.core.UpdateAngle")
    net.WriteAngle(angleToSet)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityBool(ent, varName, boolToSet)
    net.Start("gebLib.cl.core.UpdateBool")
    net.WriteBool(boolToSet)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityNumber(ent, varName, numberToSet)
    if numberToSet % 1 != 0 then
        gebLib_net.UpdateEntityFloat(ent, varName, numberToSet)
    elseif numberToSet > 0 then
        gebLib_net.UpdateEntityUInt(ent, varName, numberToSet)
    else
        gebLib_net.UpdateEntityInt(ent, varName, numberToSet)
    end
end

function gebLib_net.UpdateEntityInt(ent, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = IntToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateInt")
    WriteBits(bitsAmount)
    net.WriteInt(numberToSet, bitsAmount)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

--Use with non negative numbers for smaller packets
function gebLib_net.UpdateEntityUInt(ent, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = UIntToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateUInt")
    WriteBits(bitsAmount)
    net.WriteUInt(numberToSet, bitsAmount)
    WriteEntityAndVar(ent, varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityFloat(ent, varName, numberToSet)
    net.Start("gebLib.cl.core.UpdateFloat")
    WriteEntityAndVar(ent, varName)
    net.WriteFloat(numberToSet)
    net.Broadcast()
end

local ply = Entity(1)
if SERVER then
    ply.test_int = 1

    gebLib_net.UpdateEntityValue(ply, "test_int", 5)
end

--Handling for clients
if CLIENT then
    local function DebugMessage(len, ent, varName, value)
        if gebLib.DebugMode() and gebLib.NetworkDebug() then
            local index = varName

            if isnumber(index) then
                varName = gebLib_net.IndexedVars[varName]
            end

            --TODO: Too long, change
            --TODO: Change to custom debug print
            print("Client: " .. tostring(LocalPlayer():GetName()) .. ", network message length: " .. len .. " bits, " .. "ent: " .. tostring(ent) .. ", variable name: " .. tostring(varName) .. ", variable value: " .. tostring(value) .. ", indexed: " .. tostring(isnumber(index)) .. ", index: " .. tostring(index))
        end
    end

    local function SetEntityValue(value, len)
        local ent, varName = ReadEntityAndVar()
        DebugMessage(len, ent, varName, value)

        if isnumber(varName) then
            varName = gebLib_net.IndexedVars[varName]
        end

        if not ent:IsValid() then
            error("gebLib Networking: Trying to update variable: " .. varName .. " to value: " .. tostring(value) .. " on ent that is nil, ent might not be loaded or does not exist on the client!")
        end

        ent[varName] = value
    end

    net.Receive("gebLib.cl.core.UpdateString", function(len)
        local text = net.ReadString()
        SetEntityValue(text, len)
    end)

    net.Receive("gebLib.cl.core.UpdateInt", function(len)
        local bitsAmount = ReadBits()
        local value = net.ReadInt(bitsAmount)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateUInt", function(len)
        local bitsAmount = ReadBits()
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