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
local mathAbs       = math.abs
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
--Helper functions
local function NumberToBits(num)
    if num < 0 then
        num = mathAbs(num + 1)
    end

    local bitsAmount = mathFloor(mathLog(num * 2, 2)) + 1

    if bitsAmount < 3 then
        bitsAmount = 3
    end

    return bitsAmount
end

--Used only for positive numbers, otherwise it will error
local function UnsignedNumberToBits(uNum)
    if uNum % 2 == 0 then
        uNum = uNum + 1
    end

    local bitsAmount = mathFloor(mathLog(uNum, 2)) + 1

    return bitsAmount
end

local function UIntToBits(uInt)
    if uInt < 0 then error("can't convert unsigned int that is less than 0") end
    if uInt == 0 then return 1 end

    local bitsAmount = 0
    while uInt > 0 do
        bitsAmount = bitsAmount + 1
        uInt = bit.rshift(uInt, 1)
    end

    return bitsAmount
end

local function IntToBits(int)
    if int < 0 then
        int = math.abs(int + 1)
    end

    return math.max(UIntToBits(int), 3)
end

if CLIENT then
    for i = -5, 50 do
        local num = i
        print("Num test: " .. num)
        print("New method: " .. UIntToBits(num))
        print("Old method: " .. UnsignedNumberToBits(num))
        print()
    end
end

--Class

gebLib_net = {}
gebLib_net.__index = gebLib_net

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
        bitsAmount = NumberToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateInt")
    net.WriteUInt(bitsAmount, 6)
    net.WriteInt(numberToSet, bitsAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

--Used for non negative numbers for higher speed
function gebLib_net.UpdateEntityUInt(entity, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = UnsignedNumberToBits(numberToSet)
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